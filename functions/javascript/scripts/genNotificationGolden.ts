/**
 * genNotificationGolden.ts — 通知ハンドラの Firestore 更新内容を JS 実装から書き出す。
 *
 * handleAppStoreNotification / handlePlayNotification を、署名検証・ストア API・
 * Firestore をスタブした状態で本物のまま実行し、userDoc.ref.update() に渡された
 * 内容を記録する。Go 版との差分テストに使う。
 * 出力先: functions/javascript/scripts/notification_golden.json
 */
import * as fs from 'fs';
import * as path from 'path';
import * as crypto from 'crypto';
import { CompactSign, importPKCS8 } from 'jose';
import {
  TEST_LEAF_CERT_B64, TEST_ROOT_CERT_B64, TEST_LEAF_PRIVATE_KEY,
} from './appleTestCerts';

/* eslint-disable @typescript-eslint/no-explicit-any */

const NOW_MS = Date.parse('2026-08-27T15:30:00Z');
const RealDate = Date;
class FixedDate extends RealDate {
  constructor(...args: any[]) {
    if (args.length === 0) super(NOW_MS);
    else super(...(args as []));
  }
  static now() { return NOW_MS; }
}
(global as any).Date = FixedDate;

const SERVER_TIMESTAMP = { __sentinel: 'serverTimestamp' };
function makeTimestamp(ms: number) {
  return { __timestamp: ms, toMillis: () => ms, toDate: () => new RealDate(ms) };
}

/** 現在のクエリ結果（各ケースの前に差し替える） */
let queryDocs: any[] = [];
/** userDoc.ref.update() に渡された内容 */
let updates: { uid: string; data: any }[] = [];
/** 検索に使われたフィールドと値 */
let queried: { field: string; value: unknown } | null = null;

const adminStub: any = {
  firestore: Object.assign(
    () => ({
      collection: () => ({
        where: (field: string, _op: string, value: unknown) => {
          queried = { field, value };
          return {
            get: async () => ({ empty: queryDocs.length === 0, docs: queryDocs }),
          };
        },
      }),
    }),
    {
      Timestamp: {
        fromDate: (d: Date) => makeTimestamp(d.getTime()),
        fromMillis: makeTimestamp,
      },
      FieldValue: { serverTimestamp: () => SERVER_TIMESTAMP },
    }
  ),
  apps: [],
};

let capturedHandler: any = null;
const functionsStub: any = {
  https: {
    onRequest: (_c: unknown, h: any) => { capturedHandler = h; return h; },
  },
  pubsub: {
    onMessagePublished: (_c: unknown, h: any) => { capturedHandler = h; return h; },
  },
};

/** Play API のスタブ応答 */
let playResponse: any = null;

const Module = require('module');
const origLoad = Module._load;
Module._load = function (request: string, ...rest: any[]) {
  if (request === 'firebase-admin') return adminStub;
  if (request === 'firebase-functions/v2') return functionsStub;
  if (request === '@google-cloud/secret-manager') {
    return { SecretManagerServiceClient: class { } };
  }
  if (request === 'google-auth-library') {
    return {
      GoogleAuth: class {
        async getClient() {
          return { async request() { return { data: playResponse }; } };
        }
      },
    };
  }
  return origLoad.call(this, request, ...rest);
};

const { setAppleRootCaFingerprintForTest } = require('../src/services/appStoreServer');
setAppleRootCaFingerprintForTest(
  new crypto.X509Certificate(Buffer.from(TEST_ROOT_CERT_B64, 'base64')).fingerprint256
);

const appStoreModule = require('../src/handleAppStoreNotification');
const appStoreHandler = appStoreModule.handleAppStoreNotification;
const playModule = require('../src/handlePlayNotification');
const playHandler = playModule.handlePlayNotification;

/** Firestore の doc スタブ */
function makeDoc(uid: string, data: any) {
  return {
    id: uid,
    data: () => data,
    ref: { update: async (d: any) => { updates.push({ uid, data: d }); } },
  };
}

/** レスポンススタブ */
function makeRes() {
  const out: any = { status_code: 0, body: '' };
  const res: any = {
    status(code: number) { out.status_code = code; return res; },
    send(body: string) { out.body = body; return res; },
  };
  return { res, out };
}

function encode(value: any): any {
  if (value === null || value === undefined) return value;
  if (typeof value === 'object') {
    if (value.__sentinel === 'serverTimestamp') return { $server_timestamp: true };
    if (typeof value.__timestamp === 'number') return { $timestamp_ms: value.__timestamp };
    const o: any = {};
    for (const [k, v] of Object.entries(value)) o[k] = encode(v);
    return o;
  }
  return value;
}

async function signedJws(payload: unknown): Promise<string> {
  const key = await importPKCS8(TEST_LEAF_PRIVATE_KEY, 'ES256');
  return new CompactSign(Buffer.from(JSON.stringify(payload)))
    .setProtectedHeader({ alg: 'ES256', x5c: [TEST_LEAF_CERT_B64, TEST_ROOT_CERT_B64] })
    .sign(key);
}

function innerJws(payload: Record<string, unknown>): string {
  const header = Buffer.from(JSON.stringify({ alg: 'ES256' })).toString('base64url');
  const body = Buffer.from(JSON.stringify(payload)).toString('base64url');
  return `${header}.${body}.fakesignature`;
}

const DAY = 24 * 60 * 60 * 1000;
const ORIG_TX = 'orig_tx_999';

const NOTIFICATION_TYPES = [
  'SUBSCRIBED', 'DID_RENEW', 'BILLING_RECOVERY',
  'DID_CHANGE_RENEWAL_INFO', 'DID_CHANGE_RENEWAL_STATUS',
  'EXPIRED', 'REVOKE', 'REFUND', 'GRACE_PERIOD_EXPIRED',
  'DID_FAIL_TO_RENEW', 'CONSUMPTION_REQUEST', 'TEST', 'PRICE_INCREASE',
];
const SUBTYPES: (string | undefined)[] = [undefined, 'GRACE_PERIOD', 'BILLING_RETRY', 'RESUBSCRIBE'];
const AUTO_RENEW: (number | undefined)[] = [undefined, 0, 1];
const EXPIRES: (number | null)[] = [NOW_MS + 10 * DAY, NOW_MS - DAY, null];
const CURRENT_TIERS = ['free', 'premium', undefined];

async function main() {
  const appstoreCases: any[] = [];

  for (const notificationType of NOTIFICATION_TYPES) {
    for (const subtype of SUBTYPES) {
      for (const autoRenewStatus of AUTO_RENEW) {
        for (const expiresDate of EXPIRES) {
          for (const currentTier of CURRENT_TIERS) {
            const txPayload: any = {
              originalTransactionId: ORIG_TX,
              transactionId: 'tx_1',
              productId: 'com.thaimemo.monthly',
              type: 'Auto-Renewable Subscription',
              environment: 'Sandbox',
            };
            if (expiresDate !== null) txPayload.expiresDate = expiresDate;

            const notificationPayload: any = {
              notificationType,
              data: { signedTransactionInfo: innerJws(txPayload) },
            };
            if (subtype) notificationPayload.subtype = subtype;
            if (autoRenewStatus !== undefined) {
              notificationPayload.data.signedRenewalInfo = innerJws({
                autoRenewStatus,
                originalTransactionId: ORIG_TX,
                productId: 'com.thaimemo.monthly',
              });
            }

            const signedPayload = await signedJws(notificationPayload);

            const userData: any = {};
            if (currentTier !== undefined) userData.tier = currentTier;
            queryDocs = [makeDoc('user-a', userData)];
            updates = [];
            queried = null;

            const { res, out } = makeRes();
            await appStoreHandler(
              { method: 'POST', body: { signedPayload } }, res
            );

            appstoreCases.push({
              notification_type: notificationType,
              subtype: subtype ?? null,
              auto_renew_status: autoRenewStatus ?? null,
              expires_date: expiresDate,
              current_tier: currentTier ?? null,
              signed_payload: signedPayload,
              status_code: out.status_code,
              body: out.body,
              queried_field: queried ? (queried as any).field : null,
              updates: updates.map((u) => ({ uid: u.uid, data: encode(u.data) })),
            });
          }
        }
      }
    }
  }

  // --- 該当ユーザーなし / POST 以外 / signedPayload 欠落 / 署名不正 ---
  const extraSpecs: { name: string; run: () => Promise<any> }[] = [
    {
      name: '該当ユーザーなし',
      run: async () => {
        queryDocs = []; updates = [];
        const signedPayload = await signedJws({
          notificationType: 'DID_RENEW',
          data: { signedTransactionInfo: innerJws({ originalTransactionId: ORIG_TX }) },
        });
        const { res, out } = makeRes();
        await appStoreHandler({ method: 'POST', body: { signedPayload } }, res);
        return { out, signedPayload };
      },
    },
    {
      name: 'POST 以外',
      run: async () => {
        queryDocs = [makeDoc('user-a', { tier: 'free' })]; updates = [];
        const { res, out } = makeRes();
        await appStoreHandler({ method: 'GET', body: {} }, res);
        return { out, signedPayload: null };
      },
    },
    {
      name: 'signedPayload 欠落',
      run: async () => {
        queryDocs = [makeDoc('user-a', { tier: 'free' })]; updates = [];
        const { res, out } = makeRes();
        await appStoreHandler({ method: 'POST', body: {} }, res);
        return { out, signedPayload: null };
      },
    },
    {
      name: '署名が不正（改ざん）',
      run: async () => {
        queryDocs = [makeDoc('user-a', { tier: 'free' })]; updates = [];
        const valid = await signedJws({
          notificationType: 'DID_RENEW',
          data: { signedTransactionInfo: innerJws({ originalTransactionId: ORIG_TX }) },
        });
        const parts = valid.split('.');
        // 署名を1文字だけ変える
        const tampered = `${parts[0]}.${parts[1]}.${parts[2].slice(0, -1)}${
          parts[2].slice(-1) === 'A' ? 'B' : 'A'}`;
        const { res, out } = makeRes();
        await appStoreHandler({ method: 'POST', body: { signedPayload: tampered } }, res);
        return { out, signedPayload: tampered };
      },
    },
  ];

  const appstoreEdgeCases: any[] = [];
  for (const spec of extraSpecs) {
    updates = [];
    const { out, signedPayload } = await spec.run();
    appstoreEdgeCases.push({
      name: spec.name,
      signed_payload: signedPayload,
      status_code: out.status_code,
      body: out.body,
      updates: updates.map((u) => ({ uid: u.uid, data: encode(u.data) })),
    });
  }

  // --- Play RTDN ---
  const PLAY_STATES = [
    'SUBSCRIPTION_STATE_ACTIVE', 'SUBSCRIPTION_STATE_CANCELED',
    'SUBSCRIPTION_STATE_IN_GRACE_PERIOD', 'SUBSCRIPTION_STATE_ON_HOLD',
    'SUBSCRIPTION_STATE_PAUSED', 'SUBSCRIPTION_STATE_EXPIRED',
  ];
  const playCases: any[] = [];
  for (const state of PLAY_STATES) {
    for (const hasExpiry of [true, false]) {
      for (const currentTier of CURRENT_TIERS) {
        playResponse = {
          kind: 'k',
          subscriptionState: state,
          lineItems: [{
            productId: 'premium_monthly',
            expiryTime: hasExpiry ? '2026-09-30T12:34:56.789Z' : '',
            autoRenewingPlan: { autoRenewEnabled: true },
          }],
        };
        const userData: any = {};
        if (currentTier !== undefined) userData.tier = currentTier;
        queryDocs = [makeDoc('user-a', userData)];
        updates = [];
        queried = null;

        const rtdn = {
          packageName: 'com.thaimemo.thai_memo',
          subscriptionNotification: {
            version: '1.0', notificationType: 2,
            purchaseToken: 'ptok-1', subscriptionId: 'premium_monthly',
          },
        };
        await playHandler({
          data: {
            message: { data: Buffer.from(JSON.stringify(rtdn)).toString('base64') },
          },
        });

        playCases.push({
          subscription_state: state,
          has_expiry: hasExpiry,
          current_tier: currentTier ?? null,
          queried_field: queried ? (queried as any).field : null,
          updates: updates.map((u) => ({ uid: u.uid, data: encode(u.data) })),
        });
      }
    }
  }

  // テスト通知（subscriptionNotification なし）
  queryDocs = [makeDoc('user-a', { tier: 'free' })];
  updates = [];
  await playHandler({
    data: {
      message: {
        data: Buffer.from(JSON.stringify({
          packageName: 'com.thaimemo.thai_memo',
          testNotification: { version: '1.0' },
        })).toString('base64'),
      },
    },
  });
  const playTestNotificationUpdates = updates.length;

  const out = path.join(process.cwd(), 'scripts', 'notification_golden.json');
  fs.writeFileSync(out, JSON.stringify({
    now_ms: NOW_MS,
    root_fingerprint: new crypto.X509Certificate(
      Buffer.from(TEST_ROOT_CERT_B64, 'base64')).fingerprint256,
    appstore_cases: appstoreCases,
    appstore_edge_cases: appstoreEdgeCases,
    play_cases: playCases,
    play_test_notification_updates: playTestNotificationUpdates,
  }, null, 1));
  console.error(`wrote appstore=${appstoreCases.length} edge=${appstoreEdgeCases.length} play=${playCases.length} -> ${out}`);
}

main();
