/**
 * genAppStoreGolden.ts — verifyAppStorePurchase の判定を JS 実装から書き出す。
 *
 * Secret Manager と fetch をスタブし、本物の appStoreServer.ts を通して
 * 「どの HTTP レスポンスなら何を返すか」を記録する。
 * Go 版 internal/appstore との差分テストに使う。
 * 出力先: functions/javascript/scripts/appstore_golden.json
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

const SECRETS: Record<string, string> = {
  'appstore-connect-key': TEST_LEAF_PRIVATE_KEY,
  'appstore-key-id': 'TESTKEYID1',
  'appstore-issuer-id': '11111111-2222-3333-4444-555555555555',
};

const Module = require('module');
const origLoad = Module._load;
Module._load = function (request: string, ...rest: any[]) {
  if (request === '@google-cloud/secret-manager') {
    return {
      SecretManagerServiceClient: class {
        async accessSecretVersion({ name }: { name: string }) {
          const id = name.split('/secrets/')[1].split('/')[0];
          if (!(id in SECRETS)) throw new Error(`unknown secret ${id}`);
          return [{ payload: { data: Buffer.from(SECRETS[id]) } }];
        }
      },
    };
  }
  return origLoad.call(this, request, ...rest);
};

const {
  verifyAppStorePurchase, setAppleRootCaFingerprintForTest,
} = require('../src/services/appStoreServer');

setAppleRootCaFingerprintForTest(
  new crypto.X509Certificate(Buffer.from(TEST_ROOT_CERT_B64, 'base64')).fingerprint256
);

/** テスト用チェーンで正しく署名した JWS */
async function signed(payload: unknown): Promise<string> {
  const key = await importPKCS8(TEST_LEAF_PRIVATE_KEY, 'ES256');
  return new CompactSign(Buffer.from(JSON.stringify(payload)))
    .setProtectedHeader({
      alg: 'ES256', x5c: [TEST_LEAF_CERT_B64, TEST_ROOT_CERT_B64],
    })
    .sign(key);
}

const DAY = 24 * 60 * 60 * 1000;

type StubResponse = { status: number; body: string };
/** URL の部分一致 → 返すレスポンス。順に評価し最初に当たったものを使う。 */
type Route = { match: string; response: StubResponse };

type Case = {
  name: string;
  env: string | null;
  transaction_id: string;
  routes: Route[];
  requested_urls: string[];
  ok: boolean;
  error: string | null;
  result: {
    valid: boolean;
    original_transaction_id: string;
    expires_at: number | null;
    auto_renewing: boolean;
    status: string;
  } | null;
};

async function main() {
  const baseTx = {
    originalTransactionId: 'orig_tx_123',
    transactionId: 'tx_456',
    productId: 'com.thaimemo.monthly',
    type: 'Auto-Renewable Subscription',
    environment: 'Sandbox',
  };

  const txActive = await signed({ ...baseTx, expiresDate: NOW_MS + 10 * DAY });
  const txPast = await signed({ ...baseTx, expiresDate: NOW_MS - DAY });
  const txRevoked = await signed({
    ...baseTx, expiresDate: NOW_MS + 10 * DAY, revocationDate: NOW_MS - DAY,
  });
  const txNoExpiry = await signed({ ...baseTx });

  const renewalOn = await signed({
    autoRenewStatus: 1, originalTransactionId: 'orig_tx_123',
    productId: 'com.thaimemo.monthly',
  });
  const renewalOff = await signed({
    autoRenewStatus: 0, originalTransactionId: 'orig_tx_123',
    productId: 'com.thaimemo.monthly',
  });

  const subsBody = (signedRenewalInfo: string) => JSON.stringify({
    data: [{
      lastTransactions: [
        { originalTransactionId: 'someone_else', signedRenewalInfo: renewalOn },
        { originalTransactionId: 'orig_tx_123', signedRenewalInfo },
      ],
    }],
  });

  const txRoute = (jws: string, status = 200): Route => ({
    match: '/inApps/v1/transactions/',
    response: { status, body: JSON.stringify({ signedTransactionInfo: jws }) },
  });
  const subsRoute = (jws: string): Route => ({
    match: '/inApps/v1/subscriptions/',
    response: { status: 200, body: subsBody(jws) },
  });

  // JWS 形式の transactionId（内部の transactionId を取り出せるか）
  const jwsTransactionId = await signed({ transactionId: 'inner_tx_789' });

  const specs: Omit<Case, 'requested_urls' | 'ok' | 'error' | 'result'>[] = [
    {
      name: '期限内・自動更新ON → active',
      env: null, transaction_id: '2000000123456789',
      routes: [txRoute(txActive), subsRoute(renewalOn)],
    },
    {
      name: 'expiresDate が過去 → expired',
      env: null, transaction_id: '2000000123456789',
      routes: [txRoute(txPast), subsRoute(renewalOn)],
    },
    {
      name: 'revocationDate あり → expired / valid=false',
      env: null, transaction_id: '2000000123456789',
      routes: [txRoute(txRevoked), subsRoute(renewalOn)],
    },
    {
      name: 'expiresDate なし → expiresAt=null / expired',
      env: null, transaction_id: '2000000123456789',
      routes: [txRoute(txNoExpiry), subsRoute(renewalOn)],
    },
    {
      name: '自動更新OFF・期限内 → canceled',
      env: null, transaction_id: '2000000123456789',
      routes: [txRoute(txActive), subsRoute(renewalOff)],
    },
    {
      name: 'subscriptions API 失敗 → active / autoRenewing=true',
      env: null, transaction_id: '2000000123456789',
      routes: [
        txRoute(txActive),
        { match: '/inApps/v1/subscriptions/', response: { status: 500, body: 'boom' } },
      ],
    },
    {
      name: 'APP_STORE_ENVIRONMENT=production で本番を先に叩く',
      env: 'production', transaction_id: '2000000123456789',
      routes: [txRoute(txActive), subsRoute(renewalOn)],
    },
    {
      name: '本番404 → サンドボックスへフォールバック',
      env: 'production', transaction_id: '2000000123456789',
      routes: [
        {
          match: 'api.storekit.apple.com/inApps/v1/transactions/',
          response: { status: 404, body: '{"errorCode":4040010}' },
        },
        txRoute(txActive),
        subsRoute(renewalOn),
      ],
    },
    {
      name: '404 以外ではフォールバックしない（401）',
      env: null, transaction_id: '2000000123456789',
      routes: [txRoute(txActive, 401)],
    },
    {
      name: '両方404 → 例外',
      env: null, transaction_id: '2000000123456789',
      routes: [{
        match: '/inApps/v1/transactions/',
        response: { status: 404, body: '{"errorCode":4040010}' },
      }],
    },
    {
      name: 'JWS 形式の transactionId から内部IDを取り出す',
      env: null, transaction_id: jwsTransactionId,
      routes: [txRoute(txActive), subsRoute(renewalOn)],
    },
  ];

  const cases: Case[] = [];
  for (const spec of specs) {
    const requested: string[] = [];
    (global as any).fetch = async (url: string) => {
      requested.push(url);
      const route = spec.routes.find((r) => url.includes(r.match));
      if (!route) throw new Error(`no stub route for ${url}`);
      return {
        ok: route.response.status >= 200 && route.response.status < 300,
        status: route.response.status,
        text: async () => route.response.body,
        json: async () => JSON.parse(route.response.body),
      };
    };

    if (spec.env) process.env.APP_STORE_ENVIRONMENT = spec.env;
    else delete process.env.APP_STORE_ENVIRONMENT;

    const c: Case = {
      ...spec, requested_urls: requested, ok: false, error: null, result: null,
    };
    try {
      const r = await verifyAppStorePurchase(spec.transaction_id);
      c.ok = true;
      c.result = {
        valid: r.valid,
        original_transaction_id: r.originalTransactionId,
        expires_at: r.expiresAt ? r.expiresAt.getTime() : null,
        auto_renewing: r.autoRenewing,
        status: r.status,
      };
    } catch (e) {
      c.error = (e as Error).message;
    }
    cases.push(c);
  }

  const out = path.join(process.cwd(), 'scripts', 'appstore_golden.json');
  fs.writeFileSync(out, JSON.stringify({
    now_ms: NOW_MS,
    root_fingerprint: new crypto.X509Certificate(
      Buffer.from(TEST_ROOT_CERT_B64, 'base64')).fingerprint256,
    private_key_pem: TEST_LEAF_PRIVATE_KEY,
    cases,
  }, null, 1));
  console.error(`wrote ${cases.length} cases -> ${out}`);
  for (const c of cases) {
    console.error(`  ${c.ok ? `OK  ${c.result!.status.padEnd(12)}` : `NG  ${c.error}`} | ${c.name}`);
  }
}

main();
