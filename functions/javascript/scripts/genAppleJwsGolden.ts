/**
 * genAppleJwsGolden.ts — Apple JWS の署名検証ケースを JS 実装から書き出す。
 *
 * 実際に JWS を作り、JS 側（appStoreServer.ts の verifyAppleJwsSignature を
 * 通る parseNotificationPayload）が通すか弾くかを記録する。
 * Go 版 internal/applejws が同じ判定をすることを差分テストで確かめる。
 * 出力先: functions/javascript/scripts/apple_jws_golden.json
 */
import * as fs from 'fs';
import * as path from 'path';
import * as crypto from 'crypto';
import { CompactSign, importPKCS8 } from 'jose';
import {
  TEST_LEAF_CERT_B64, TEST_ROOT_CERT_B64,
  EVIL_LEAF_CERT_B64, EVIL_ROOT_CERT_B64,
  TEST_LEAF_PRIVATE_KEY, EVIL_LEAF_PRIVATE_KEY,
  FORGED_LEAF_CERT_B64, FORGED_LEAF_PRIVATE_KEY,
} from './appleTestCerts';

/* eslint-disable @typescript-eslint/no-explicit-any */

// Secret Manager は読み込み時に生成されるだけなので、実際の呼び出しは起きない。
// それでも認証情報を引きに行かせないようにスタブしておく。
const Module = require('module');
const origLoad = Module._load;
Module._load = function (request: string, ...rest: any[]) {
  if (request === '@google-cloud/secret-manager') {
    return { SecretManagerServiceClient: class { } };
  }
  return origLoad.call(this, request, ...rest);
};

const {
  parseNotificationPayload, setAppleRootCaFingerprintForTest,
} = require('../src/services/appStoreServer');

const testRootFingerprint = new crypto.X509Certificate(
  Buffer.from(TEST_ROOT_CERT_B64, 'base64')
).fingerprint256;
setAppleRootCaFingerprintForTest(testRootFingerprint);

/** 内側の JWS。外側の署名で担保されるので署名部は任意。 */
function innerJws(payload: Record<string, unknown>): string {
  const header = Buffer.from(JSON.stringify({ alg: 'ES256' })).toString('base64url');
  const body = Buffer.from(JSON.stringify(payload)).toString('base64url');
  return `${header}.${body}.fakesignature`;
}

async function sign(
  payload: unknown, keyPem: string, x5c: string[] | undefined
): Promise<string> {
  const key = await importPKCS8(keyPem, 'ES256');
  const header: any = { alg: 'ES256' };
  if (x5c) header.x5c = x5c;
  return new CompactSign(Buffer.from(JSON.stringify(payload)))
    .setProtectedHeader(header)
    .sign(key);
}

type Case = {
  name: string;
  jws: string;
  /** JS が署名検証を通したか */
  ok: boolean;
  /** 弾いた場合のエラーメッセージ */
  error: string | null;
  /** 通した場合に取り出せた値 */
  notification_type: string | null;
  subtype: string | null;
  original_transaction_id: string | null;
  expires_date: number | null;
  auto_renew_status: number | null;
  has_renewal_info: boolean;
};

async function main() {
  const validChain = [TEST_LEAF_CERT_B64, TEST_ROOT_CERT_B64];
  const evilChain = [EVIL_LEAF_CERT_B64, EVIL_ROOT_CERT_B64];

  const txInfo = {
    originalTransactionId: 'orig_tx_123',
    transactionId: 'tx_456',
    productId: 'com.thaimemo.monthly',
    expiresDate: 1793750400000,
    type: 'Auto-Renewable Subscription',
    environment: 'Production',
  };
  const renewalInfo = {
    autoRenewStatus: 1,
    originalTransactionId: 'orig_tx_123',
    productId: 'com.thaimemo.monthly',
  };

  // 別鍵（リーフ証明書の公開鍵とは一致しない）
  const wrongKeyPem = crypto.generateKeyPairSync('ec', { namedCurve: 'P-256' })
    .privateKey.export({ type: 'pkcs8', format: 'pem' }) as string;

  const specs: { name: string; jws: string | Promise<string> }[] = [
    { name: '3パートでない', jws: 'not.a.valid.jws.here' },
    { name: 'パートが2つしかない', jws: 'aaa.bbb' },
    { name: 'x5c なし', jws: sign({}, TEST_LEAF_PRIVATE_KEY, undefined) },
    { name: 'x5c が1件だけ', jws: sign({}, TEST_LEAF_PRIVATE_KEY, [TEST_LEAF_CERT_B64]) },
    {
      name: 'チェーン不正（リーフを2回）',
      jws: sign({}, TEST_LEAF_PRIVATE_KEY, [TEST_LEAF_CERT_B64, TEST_LEAF_CERT_B64]),
    },
    {
      name: 'Apple 以外のルート CA',
      jws: sign({ notificationType: 'DID_RENEW', data: {} },
        EVIL_LEAF_PRIVATE_KEY, evilChain),
    },
    {
      // 中間CA偽装。TEST_LEAF は「ピン留めしたルートが正規に発行した非CA証明書」で、
      // その秘密鍵をこちらが持っている（= Apple の開発者向け配布証明書に相当）。
      // これを中間CAの位置に置くと、隣接署名は全て正当・ルートの
      // フィンガープリントも一致するチェーンが作れてしまう。
      name: '非CA証明書を中間CAとして持ち込む',
      jws: sign({ notificationType: 'DID_RENEW', data: {} },
        FORGED_LEAF_PRIVATE_KEY,
        [FORGED_LEAF_CERT_B64, TEST_LEAF_CERT_B64, TEST_ROOT_CERT_B64]),
    },
    {
      name: '署名鍵が違う（チェーンは正当）',
      jws: sign({ notificationType: 'DID_RENEW', data: {} }, wrongKeyPem, validChain),
    },
    {
      name: '正当（renewalInfo あり）',
      jws: sign({
        notificationType: 'DID_RENEW',
        data: {
          signedTransactionInfo: innerJws(txInfo),
          signedRenewalInfo: innerJws(renewalInfo),
        },
      }, TEST_LEAF_PRIVATE_KEY, validChain),
    },
    {
      name: '正当（subtype あり）',
      jws: sign({
        notificationType: 'DID_CHANGE_RENEWAL_STATUS',
        subtype: 'AUTO_RENEW_DISABLED',
        data: {
          signedTransactionInfo: innerJws(txInfo),
          signedRenewalInfo: innerJws({ ...renewalInfo, autoRenewStatus: 0 }),
        },
      }, TEST_LEAF_PRIVATE_KEY, validChain),
    },
    {
      name: '正当（renewalInfo なし）',
      jws: sign({
        notificationType: 'EXPIRED',
        data: { signedTransactionInfo: innerJws(txInfo) },
      }, TEST_LEAF_PRIVATE_KEY, validChain),
    },
    {
      name: '正当（expiresDate なし）',
      jws: sign({
        notificationType: 'REFUND',
        data: {
          signedTransactionInfo: innerJws({
            ...txInfo, expiresDate: undefined, revocationDate: 1790000000000,
          }),
        },
      }, TEST_LEAF_PRIVATE_KEY, validChain),
    },
  ];

  const cases: Case[] = [];
  for (const spec of specs) {
    const jws = await spec.jws;
    const c: Case = {
      name: spec.name, jws, ok: false, error: null,
      notification_type: null, subtype: null,
      original_transaction_id: null, expires_date: null,
      auto_renew_status: null, has_renewal_info: false,
    };
    try {
      const parsed = await parseNotificationPayload(jws);
      c.ok = true;
      c.notification_type = parsed.notificationType;
      c.subtype = parsed.subtype ?? null;
      c.original_transaction_id = parsed.transactionInfo.originalTransactionId;
      c.expires_date = parsed.transactionInfo.expiresDate ?? null;
      c.has_renewal_info = parsed.renewalInfo !== undefined;
      c.auto_renew_status = parsed.renewalInfo?.autoRenewStatus ?? null;
    } catch (e) {
      c.error = (e as Error).message;
    }
    cases.push(c);
  }

  const out = path.join(process.cwd(), 'scripts', 'apple_jws_golden.json');
  fs.writeFileSync(out, JSON.stringify({
    root_fingerprint: testRootFingerprint,
    cases,
  }, null, 1));
  console.error(`wrote ${cases.length} cases -> ${out}`);
  for (const c of cases) {
    console.error(`  ${c.ok ? 'OK  ' : 'NG  '} ${c.name}${c.error ? ` : ${c.error}` : ''}`);
  }
}

main();
