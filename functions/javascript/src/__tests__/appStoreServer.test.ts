/**
 * appStoreServer.test.ts
 *
 * App Store Server API クライアントのテスト。
 *
 * テスト戦略:
 * 1. parseNotificationPayload / 署名検証（verifyAppleJwsSignature）
 *    - 事前生成した本物の EC 証明書チェーンと jose.CompactSign を使って
 *      実際の JWS 署名検証フローをテストする
 *    - 各エラーケース（不正フォーマット・チェーン不正・非 Apple CA・署名不一致）を網羅
 * 2. verifyAppStorePurchase
 *    - Secret Manager と fetch をモック化して API 呼び出しフローをテスト
 *    - transactionId の JWS デコード・エンドポイント切替・ステータス判定を検証
 *
 * 【テスト用証明書について】
 * openssl で生成した EC（P-256）証明書チェーン。
 * Apple Root CA の代わりに "Apple Root CA - G3" という Subject を持つ
 * テスト用自己署名ルート CA を使用している。
 */

// ============================================================
// モック定義
// ============================================================

/** Secret Manager accessSecretVersion のモック */
const mockAccessSecretVersion = jest.fn();

/**
 * @google-cloud/secret-manager モック
 * SecretManagerServiceClient のインスタンスメソッドを制御する
 */
jest.mock('@google-cloud/secret-manager', () => ({
  SecretManagerServiceClient: jest.fn().mockImplementation(() => ({
    accessSecretVersion: mockAccessSecretVersion,
  })),
}));

// ============================================================
// テスト本体
// ============================================================
import * as crypto from 'crypto';
import { CompactSign, importPKCS8 } from 'jose';
import { parseNotificationPayload, verifyAppStorePurchase, setAppleRootCaFingerprintForTest, getAppleRootCaFingerprint } from '../services/appStoreServer';

// ──────────────────────────────────────────────────────────
// テスト用証明書データ（事前生成済み）
//
// 生成コマンド:
//   openssl ecparam -name prime256v1 -genkey -noout -out root.key
//   openssl req -new -x509 -key root.key -out root.crt -days 3650 \
//     -subj "/CN=Apple Root CA - G3/OU=Apple Certification Authority/O=Apple Inc./C=US"
//   openssl ecparam -name prime256v1 -genkey -noout -out leaf.key
//   openssl req -new -key leaf.key -out leaf.csr -subj "/CN=Apple App Store/O=Apple Inc./C=US"
//   openssl x509 -req -in leaf.csr -CA root.crt -CAkey root.key -out leaf.crt -days 3650
// ──────────────────────────────────────────────────────────

/**
 * テスト用リーフ証明書（Apple App Store）
 * ルート CA（Apple Root CA - G3）によって署名されている
 */
// prettier-ignore
const TEST_LEAF_CERT_B64 = 'MIIB5zCCAY2gAwIBAgIUB/i2+9EPTxOX+7gkKVDDuvsHDD8wCgYIKoZIzj0EAwIwZzEbMBkGA1UEAwwSQXBwbGUgUm9vdCBDQSAtIEczMSYwJAYDVQQLDB1BcHBsZSBDZXJ0aWZpY2F0aW9uIEF1dGhvcml0eTETMBEGA1UECgwKQXBwbGUgSW5jLjELMAkGA1UEBhMCVVMwHhcNMjYwNDA3MDgwNjQxWhcNMzYwNDA0MDgwNjQxWjA8MRgwFgYDVQQDDA9BcHBsZSBBcHAgU3RvcmUxEzARBgNVBAoMCkFwcGxlIEluYy4xCzAJBgNVBAYTAlVTMFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEJrQFjQfnXLw3NyIIKqARwnpLnEHv4Q4PihO7Lk7+ewTL896khTGDqhPOG1Z3QQJ8GNyzSbt0Qb0RF7RbGIgvq6NCMEAwHQYDVR0OBBYEFC/2AmMfRo21pTMcnK057SPvKsWTMB8GA1UdIwQYMBaAFAttHIdWHHvwQTpcxixZBd0rSVPhMAoGCCqGSM49BAMCA0gAMEUCIB5wkZEvj2z8gxgVj/kphtGA7cm4R4S0bc7peRi3zjzqAiEAg/wVaZNYWzHVSQNVm4S2Kb+MxvmwcQqQWL1H86+eUjg=';

/**
 * テスト用ルート証明書（"Apple Root CA - G3" Subject を持つ自己署名証明書）
 * 本番の Apple Root CA とは別物だが Subject 名が一致するためテストで使用できる
 */
// prettier-ignore
const TEST_ROOT_CERT_B64 = 'MIICIjCCAcmgAwIBAgIUJLV3Miy+t2h4XuxPTaARWIifL2kwCgYIKoZIzj0EAwIwZzEbMBkGA1UEAwwSQXBwbGUgUm9vdCBDQSAtIEczMSYwJAYDVQQLDB1BcHBsZSBDZXJ0aWZpY2F0aW9uIEF1dGhvcml0eTETMBEGA1UECgwKQXBwbGUgSW5jLjELMAkGA1UEBhMCVVMwHhcNMjYwNDA3MDgwNjQxWhcNMzYwNDA0MDgwNjQxWjBnMRswGQYDVQQDDBJBcHBsZSBSb290IENBIC0gRzMxJjAkBgNVBAsMHUFwcGxlIENlcnRpZmljYXRpb24gQXV0aG9yaXR5MRMwEQYDVQQKDApBcHBsZSBJbmMuMQswCQYDVQQGEwJVUzBZMBMGByqGSM49AgEGCCqGSM49AwEHA0IABKwqSayyS+CvSbN727PYuvdWPOpjh2oOQndrDe5gZmfgkfbAASnClDd+8dzJmgJqAyo6Yfl32VUJH4DEMa5Wp9ajUzBRMB0GA1UdDgQWBBQLbRyHVhx78EE6XMYsWQXdK0lT4TAfBgNVHSMEGDAWgBQLbRyHVhx78EE6XMYsWQXdK0lT4TAPBgNVHRMBAf8EBTADAQH/MAoGCCqGSM49BAMCA0cAMEQCIBpkmOiEpVnqnqemCDX3M47T9JHADRTkMffogl3tDW6bAiAXpadIx98O4MFpKvhLq8E778X+WfZxBywF6lvexd8MRg==';

/**
 * テスト用リーフ証明書の秘密鍵（PKCS8 PEM 形式）
 * TEST_LEAF_CERT_B64 に対応する秘密鍵
 */
const TEST_LEAF_PRIVATE_KEY = `-----BEGIN PRIVATE KEY-----
MIGHAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBG0wawIBAQQgImQr8t/9up0mFIdr
suF/Fekl9XJPeeG6vTTzZ+cV8SahRANCAAQmtAWNB+dcvDc3IggqoBHCekucQe/h
Dg+KE7suTv57BMvz3qSFMYOqE84bVndBAnwY3LNJu3RBvREXtFsYiC+r
-----END PRIVATE KEY-----`;

/**
 * テスト用非 Apple リーフ証明書（"Evil Corp" の CA によって署名）
 * ルート CA Subject に "Apple Root CA" が含まれないため署名検証で拒否されることを確認
 */
// prettier-ignore
const EVIL_LEAF_CERT_B64 = 'MIIBsjCCAVegAwIBAgIUa9eo56Q+czq2eUXx/OPIYclt4KgwCgYIKoZIzj0EAwIwODEVMBMGA1UEAwwMRXZpbCBSb290IENBMRIwEAYDVQQKDAlFdmlsIENvcnAxCzAJBgNVBAYTAlVTMB4XDTI2MDQwNzA4MTUyNloXDTM2MDQwNDA4MTUyNlowNTESMBAGA1UEAwwJRXZpbCBMZWFmMRIwEAYDVQQKDAlFdmlsIENvcnAxCzAJBgNVBAYTAlVTMFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAESdZ1Mr6a1n7El4EtIqRDBjUyn/VsN/AsIh0LAStF2WPCYGQNQOZazk5Rdk9bwFDZjwn2w7qMqRnkxk4VtV/hPaNCMEAwHQYDVR0OBBYEFJYRR3NWbutC9AjV9+aTP8jc0FDZMB8GA1UdIwQYMBaAFMx2AQUi3b/vjsCgmvzPDJdVR/hzMAoGCCqGSM49BAMCA0kAMEYCIQDblrRWJZeqQT69x8G5T0EKUbx47MM6yHyvzLCNJu3aGQIhAKutlsthIV+2rb0OoGoJm9swqWJVnvOUhiqRR9Ysehna';

/**
 * テスト用非 Apple ルート証明書（"Evil Root CA" Subject）
 * verifyAppleJwsSignature の Root CA Subject チェックで拒否されることを確認
 */
// prettier-ignore
const EVIL_ROOT_CERT_B64 = 'MIIBxTCCAWugAwIBAgIUFrYuiOfNeIG2+qTASbU0IabEHHgwCgYIKoZIzj0EAwIwODEVMBMGA1UEAwwMRXZpbCBSb290IENBMRIwEAYDVQQKDAlFdmlsIENvcnAxCzAJBgNVBAYTAlVTMB4XDTI2MDQwNzA4MTUyNloXDTM2MDQwNDA4MTUyNlowODEVMBMGA1UEAwwMRXZpbCBSb290IENBMRIwEAYDVQQKDAlFdmlsIENvcnAxCzAJBgNVBAYTAlVTMFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEUzqTwVzsYY0dZkKV4o0jjxYubmDKBp5jtu9oMrsbpmVEcCEmk/708jrAxL7Kwe+fXeA5korAeGF4QRhU70msXaNTMFEwHQYDVR0OBBYEFMx2AQUi3b/vjsCgmvzPDJdVR/hzMB8GA1UdIwQYMBaAFMx2AQUi3b/vjsCgmvzPDJdVR/hzMA8GA1UdEwEB/wQFMAMBAf8wCgYIKoZIzj0EAwIDSAAwRQIhAJJxpuQo9KfPmnZq6IdH2PqDVUlSoRvFjy03ZTnnNRM3AiBRdqeHCWpUUdtXfGTJ6j/UWRtQRFqvZ2O2CIzJ9pCSsQ==';

/** 非 Apple CA のリーフ秘密鍵 */
const EVIL_LEAF_PRIVATE_KEY = `-----BEGIN PRIVATE KEY-----
MIGHAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBG0wawIBAQQgmsj+NpQD3RNfyO2R
hWX7YHZnh+5tiPak7idoF9ejIUmhRANCAARJ1nUyvprWfsSXgS0ipEMGNTKf9Ww3
8CwiHQsBK0XZY8JgZA1A5lrOTlF2T1vAUNmPCfbDuoypGeTGThW1X+E9
-----END PRIVATE KEY-----`;

/**
 * 中間CA偽装用の偽リーフ証明書と、その秘密鍵。
 *
 * TEST_LEAF_CERT_B64（CA:FALSE）の秘密鍵で署名して作った証明書。
 * 生成手順は scripts/appleTestCerts.ts を参照。
 */
// prettier-ignore
const FORGED_LEAF_CERT_B64 = 'MIIBqTCCAVCgAwIBAgICEjQwCgYIKoZIzj0EAwIwPDEYMBYGA1UEAwwPQXBwbGUgQXBwIFN0b3JlMRMwEQYDVQQKDApBcHBsZSBJbmMuMQswCQYDVQQGEwJVUzAeFw0yNjA4MjcwMTIzNDBaFw0zNjA4MjQwMTIzNDBaMDwxGDAWBgNVBAMMD0FwcGxlIEFwcCBTdG9yZTETMBEGA1UECgwKQXBwbGUgSW5jLjELMAkGA1UEBhMCVVMwWTATBgcqhkjOPQIBBggqhkjOPQMBBwNCAASnYGXSr/0iVB+/4ksO/Azo0WYy87sGGqDB0WJZndBStkwMYQHwwCoX2CT6GzthJoPfJcx1ySzbD0VZMDGYteYBo0IwQDAdBgNVHQ4EFgQUxKP0fPd6re95elMU0+QRUbyhBmswHwYDVR0jBBgwFoAUL/YCYx9GjbWlMxycrTntI+8qxZMwCgYIKoZIzj0EAwIDRwAwRAIgNQJuRZ2NcNr18CtMvDzw3BDwRaMiC43ew2H2ERMaqtoCIGNyiandqZLJEqTe/11SJOD0cujSz3oP2mSDozRhQ9o0';

const FORGED_LEAF_PRIVATE_KEY = `-----BEGIN PRIVATE KEY-----
MIGHAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBG0wawIBAQQgPQ3a3UcI2D5xQUeV
nFHcpNlC8b7wUhP1DNS/BWswmZqhRANCAASnYGXSr/0iVB+/4ksO/Azo0WYy87sG
GqDB0WJZndBStkwMYQHwwCoX2CT6GzthJoPfJcx1ySzbD0VZMDGYteYB
-----END PRIVATE KEY-----`;

// ──────────────────────────────────────────────────────────
// テスト用 JWS 生成ヘルパー
// ──────────────────────────────────────────────────────────

/**
 * 検証が通る正規の JWS を生成するヘルパー
 * テスト用リーフ秘密鍵で署名し、x5c ヘッダーに [leaf, root] チェーンを含める
 */
async function createValidJws(payload: Record<string, unknown>): Promise<string> {
  const privateKey = await importPKCS8(TEST_LEAF_PRIVATE_KEY, 'ES256');
  return new CompactSign(Buffer.from(JSON.stringify(payload)))
    .setProtectedHeader({
      alg: 'ES256',
      x5c: [TEST_LEAF_CERT_B64, TEST_ROOT_CERT_B64],
    })
    .sign(privateKey);
}

/**
 * 非 Apple CA チェーンで署名した JWS（ルート CA Subject チェックで失敗するケース）
 */
async function createEvilJws(payload: Record<string, unknown>): Promise<string> {
  const privateKey = await importPKCS8(EVIL_LEAF_PRIVATE_KEY, 'ES256');
  return new CompactSign(Buffer.from(JSON.stringify(payload)))
    .setProtectedHeader({
      alg: 'ES256',
      x5c: [EVIL_LEAF_CERT_B64, EVIL_ROOT_CERT_B64],
    })
    .sign(privateKey);
}

/**
 * 正規発行の非CA証明書を中間CAとして使った JWS（中間CA偽装）
 *
 * x5c = [偽leaf, TEST_LEAF（CA:FALSE）, TEST_ROOT]。
 * 偽leaf は TEST_LEAF の秘密鍵で署名してあるため、隣接署名は全て正当になる。
 */
async function createForgedIntermediateJws(
  payload: Record<string, unknown>
): Promise<string> {
  const privateKey = await importPKCS8(FORGED_LEAF_PRIVATE_KEY, 'ES256');
  return new CompactSign(Buffer.from(JSON.stringify(payload)))
    .setProtectedHeader({
      alg: 'ES256',
      x5c: [FORGED_LEAF_CERT_B64, TEST_LEAF_CERT_B64, TEST_ROOT_CERT_B64],
    })
    .sign(privateKey);
}

/**
 * チェーンが不正な JWS（リーフ証明書を2回使用 → 署名チェック失敗）
 * 証明書[0] がその公開鍵で証明書[1] を検証できない
 */
async function createBrokenChainJws(payload: Record<string, unknown>): Promise<string> {
  const privateKey = await importPKCS8(TEST_LEAF_PRIVATE_KEY, 'ES256');
  return new CompactSign(Buffer.from(JSON.stringify(payload)))
    .setProtectedHeader({
      alg: 'ES256',
      // リーフ証明書を2回並べるとチェーン検証失敗
      // leaf.verify(leaf.publicKey) = false（leaf は root によって署名されている）
      x5c: [TEST_LEAF_CERT_B64, TEST_LEAF_CERT_B64],
    })
    .sign(privateKey);
}

/**
 * 別のキーで署名した JWS（証明書チェーンは正当だが署名が不一致）
 * x5c のリーフ証明書とは別の秘密鍵で署名するため jose.compactVerify で失敗する
 */
async function createWrongKeyJws(payload: Record<string, unknown>): Promise<string> {
  // 別の EC キーペアを生成（リーフ証明書の公開鍵とは異なる）
  const wrongKeyPair = crypto.generateKeyPairSync('ec', { namedCurve: 'P-256' });
  const wrongKeyPem = wrongKeyPair.privateKey.export({ type: 'pkcs8', format: 'pem' }) as string;
  const wrongPrivateKey = await importPKCS8(wrongKeyPem, 'ES256');
  return new CompactSign(Buffer.from(JSON.stringify(payload)))
    .setProtectedHeader({
      alg: 'ES256',
      // チェーンは正当（Apple Root CA - G3 で終端）
      x5c: [TEST_LEAF_CERT_B64, TEST_ROOT_CERT_B64],
    })
    .sign(wrongPrivateKey); // リーフ証明書の鍵とは別の鍵で署名
}

/**
 * 内側の JWS（signedTransactionInfo / signedRenewalInfo）を作成するヘルパー
 *
 * Apple の二重 JWS 構造では、外側 JWS の署名検証で Apple 発行を保証しているため、
 * 内側の JWS（signedTransactionInfo / signedRenewalInfo）はデコードのみで
 * 署名検証を行わない設計になっている（appStoreServer.ts の decodeSignedPayload を参照）。
 * そのため署名部には任意の文字列を使用できる。
 */
function makeFakeInnerJws(payload: Record<string, unknown>): string {
  const header = Buffer.from(JSON.stringify({ alg: 'ES256' })).toString('base64url');
  const body = Buffer.from(JSON.stringify(payload)).toString('base64url');
  return `${header}.${body}.fakesignature`;
}

/**
 * signedTransactionInfo JWS 内でデコードされる Apple トランザクション情報
 * Apple API レスポンスの signedTransactionInfo ペイロードに対応
 *
 * parseNotificationPayload のテストでは外側JWSの署名検証のみが目的のため fakesignature を使用。
 * verifyAppStorePurchase のテストでは signedTransactionInfo 自体の署名検証も行われるため
 * createValidJws で正規のJWSを生成する。
 */
function makeSignedTransactionInfo(overrides: Record<string, unknown> = {}): string {
  return makeFakeInnerJws({
    originalTransactionId: 'orig_tx_123',
    transactionId: 'tx_123',
    productId: 'com.thaimemo.monthly',
    expiresDate: Date.now() + 86_400_000,
    type: 'Auto-Renewable Subscription',
    environment: 'Sandbox',
    ...overrides,
  });
}

async function makeValidSignedTransactionInfo(overrides: Record<string, unknown> = {}): Promise<string> {
  return createValidJws({
    originalTransactionId: 'orig_tx_123',
    transactionId: 'tx_123',
    productId: 'com.thaimemo.monthly',
    expiresDate: Date.now() + 86_400_000,
    type: 'Auto-Renewable Subscription',
    environment: 'Sandbox',
    ...overrides,
  });
}

// ──────────────────────────────────────────────────────────
// Secret Manager モック設定ヘルパー
// ──────────────────────────────────────────────────────────

/**
 * Secret Manager のモックを設定する
 * verifyAppStorePurchase が内部で generateAppStoreJWT を呼ぶとき、
 * Secret Manager から秘密鍵・Key ID・Issuer ID を取得するため設定が必要
 */
function setupSecretManagerMock() {
  mockAccessSecretVersion.mockImplementation(({ name }: { name: string }) => {
    if (name.includes('appstore-connect-key')) {
      // JWT 署名に使用する秘密鍵（テスト用リーフ鍵）
      return Promise.resolve([{ payload: { data: Buffer.from(TEST_LEAF_PRIVATE_KEY) } }]);
    }
    if (name.includes('appstore-key-id')) {
      // App Store Connect API の Key ID
      return Promise.resolve([{ payload: { data: Buffer.from('TESTKEY01') } }]);
    }
    if (name.includes('appstore-issuer-id')) {
      // App Store Connect の Issuer ID（UUID 形式）
      return Promise.resolve([{ payload: { data: Buffer.from('11111111-test-issuer-id-uuid') } }]);
    }
    return Promise.reject(new Error(`Unknown secret: ${name}`));
  });
}

// ──────────────────────────────────────────────────────────
// テストスイート
// ──────────────────────────────────────────────────────────

// テスト用ルート証明書のSHA-256フィンガープリント
const TEST_ROOT_FINGERPRINT =
  '5E:3F:E2:90:32:88:B9:9B:50:3C:8D:BB:CE:A6:5A:4F:74:99:20:C9:C0:0B:52:BA:4C:3F:50:6F:B3:EB:B0:67';

describe('parseNotificationPayload（署名検証含む）', () => {
  let originalFingerprint: string;

  beforeAll(() => {
    originalFingerprint = getAppleRootCaFingerprint();
    setAppleRootCaFingerprintForTest(TEST_ROOT_FINGERPRINT);
  });

  afterAll(() => {
    setAppleRootCaFingerprintForTest(originalFingerprint);
  });

  // ────────────────────────────────────────────────
  // 署名検証エラーケース
  // ────────────────────────────────────────────────
  describe('署名検証エラーケース', () => {
    test('JWS が3パートでない場合は例外をスローする', async () => {
      // "header.payload.signature" の3パート構造でない場合
      await expect(parseNotificationPayload('not.a.valid.jws.here')).rejects.toThrow(
        'Invalid JWS format'
      );
    });

    test('JWS ヘッダーに x5c が存在しない場合は例外をスローする', async () => {
      // x5c なしの JWS（通常の JWT とは異なり Apple 通知には x5c が必須）
      const privateKey = await importPKCS8(TEST_LEAF_PRIVATE_KEY, 'ES256');
      const jws = await new CompactSign(Buffer.from('{}'))
        .setProtectedHeader({ alg: 'ES256' }) // x5c なし
        .sign(privateKey);
      await expect(parseNotificationPayload(jws)).rejects.toThrow(
        'Missing or incomplete x5c certificate chain'
      );
    });

    test('x5c に証明書が1件しかない場合は例外をスローする（最低2件必要）', async () => {
      // leaf と root で最低2証明書が必要（チェーン検証のため）
      const privateKey = await importPKCS8(TEST_LEAF_PRIVATE_KEY, 'ES256');
      const jws = await new CompactSign(Buffer.from('{}'))
        .setProtectedHeader({ alg: 'ES256', x5c: [TEST_LEAF_CERT_B64] }) // 1件のみ
        .sign(privateKey);
      await expect(parseNotificationPayload(jws)).rejects.toThrow(
        'Missing or incomplete x5c certificate chain'
      );
    });

    test('発行者の位置に非CA証明書があれば例外をスローする', async () => {
      // リーフ証明書を2回並べる。1件目の発行者の位置に立つのはリーフ（CA:FALSE）
      const jws = await createBrokenChainJws({});
      await expect(parseNotificationPayload(jws)).rejects.toThrow(
        'Non-CA certificate used as issuer at index 1'
      );
    });

    test('正規発行の非CA証明書を中間CAとして持ち込む攻撃を拒否する', async () => {
      // TEST_LEAF_CERT_B64 は「ピン留めしたルートが正規に発行した、秘密鍵を
      // こちらが持つ非CA証明書」= Apple の開発者向け配布証明書に相当する。
      // これを中間CAの位置に置くと、隣接署名は全て正当・ルートの
      // フィンガープリントも一致するチェーンが作れてしまう。
      // basicConstraints を見ていないと通過する（2026-08 以前はこれが通った）。
      const jws = await createForgedIntermediateJws({
        notificationType: 'DID_RENEW',
        data: {},
      });
      await expect(parseNotificationPayload(jws)).rejects.toThrow(
        'Non-CA certificate used as issuer at index 1'
      );
    });

    test('証明書チェーンの署名が不正な場合は例外をスローする', async () => {
      // 発行者は CA（テスト用ルート）だが、リーフはそのルートで署名されていない
      const privateKey = await importPKCS8(EVIL_LEAF_PRIVATE_KEY, 'ES256');
      const jws = await new CompactSign(Buffer.from('{}'))
        .setProtectedHeader({
          alg: 'ES256',
          x5c: [EVIL_LEAF_CERT_B64, TEST_ROOT_CERT_B64],
        })
        .sign(privateKey);
      await expect(parseNotificationPayload(jws)).rejects.toThrow(
        'Certificate chain verification failed'
      );
    });

    test('ルート CA が Apple Root CA でない場合は例外をスローする', async () => {
      // 悪意あるCA（"Evil Root CA"）によって署名された通知を拒否する
      // チェーン自体は有効だが Subject に "Apple Root CA" が含まれない
      const jws = await createEvilJws({ notificationType: 'DID_RENEW', data: {} });
      await expect(parseNotificationPayload(jws)).rejects.toThrow(
        'Untrusted root CA'
      );
    });

    test('JWS 署名が改ざんされた場合（証明書チェーンは正当）は例外をスローする', async () => {
      // x5c のリーフ証明書公開鍵とは別のキーで署名した JWS を拒否
      // jose.compactVerify がリーフ証明書の公開鍵で検証して失敗する
      const jws = await createWrongKeyJws({ notificationType: 'DID_RENEW', data: {} });
      await expect(parseNotificationPayload(jws)).rejects.toThrow('signature verification failed');
    });
  });

  // ────────────────────────────────────────────────
  // 正常ケース
  // ────────────────────────────────────────────────
  describe('正常ケース', () => {
    test('有効な Apple チェーンと正しい署名で通知タイプとトランザクション情報を返す', async () => {
      // テスト用証明書チェーン（Apple Root CA - G3 Subject で終端）で署名した JWS
      const signedRenewalInfo = makeFakeInnerJws({
        autoRenewStatus: 1,
        originalTransactionId: 'orig_tx_123',
        productId: 'com.thaimemo.monthly',
      });
      const jws = await createValidJws({
        notificationType: 'DID_RENEW',
        data: {
          signedTransactionInfo: makeSignedTransactionInfo(),
          signedRenewalInfo,
        },
      });

      const result = await parseNotificationPayload(jws);

      expect(result.notificationType).toBe('DID_RENEW');
      expect(result.transactionInfo.originalTransactionId).toBe('orig_tx_123');
      expect(result.transactionInfo.productId).toBe('com.thaimemo.monthly');
      expect(result.renewalInfo?.autoRenewStatus).toBe(1);
    });

    test('subtype が存在する通知タイプを正しく抽出する', async () => {
      const jws = await createValidJws({
        notificationType: 'DID_FAIL_TO_RENEW',
        subtype: 'GRACE_PERIOD',
        data: { signedTransactionInfo: makeSignedTransactionInfo() },
      });

      const result = await parseNotificationPayload(jws);

      expect(result.notificationType).toBe('DID_FAIL_TO_RENEW');
      expect(result.subtype).toBe('GRACE_PERIOD');
    });

    test('signedRenewalInfo がない通知の場合 renewalInfo は undefined を返す', async () => {
      // EXPIRED など renewalInfo が含まれない通知タイプへの対応
      const jws = await createValidJws({
        notificationType: 'EXPIRED',
        data: {
          signedTransactionInfo: makeSignedTransactionInfo(),
          // signedRenewalInfo: なし
        },
      });

      const result = await parseNotificationPayload(jws);

      expect(result.renewalInfo).toBeUndefined();
    });

    test('expiresDate が transactionInfo に正しく格納される', async () => {
      const futureDate = Date.now() + 86_400_000;
      const jws = await createValidJws({
        notificationType: 'DID_RENEW',
        data: {
          signedTransactionInfo: makeSignedTransactionInfo({ expiresDate: futureDate }),
        },
      });

      const result = await parseNotificationPayload(jws);

      expect(result.transactionInfo.expiresDate).toBe(futureDate);
    });
  });
});

// ──────────────────────────────────────────────────────────
// verifyAppStorePurchase テスト
// ──────────────────────────────────────────────────────────
describe('verifyAppStorePurchase', () => {
  let originalFingerprint: string;

  beforeAll(() => {
    originalFingerprint = getAppleRootCaFingerprint();
    setAppleRootCaFingerprintForTest(TEST_ROOT_FINGERPRINT);
  });

  afterAll(() => {
    setAppleRootCaFingerprintForTest(originalFingerprint);
  });

  beforeEach(() => {
    jest.clearAllMocks();
    setupSecretManagerMock();
    global.fetch = jest.fn();
    delete process.env.APP_STORE_ENVIRONMENT;
  });

  afterEach(() => {
    delete (global as Record<string, unknown>).fetch;
  });

  // ──────────────────────────────────────────────
  // transactionId 処理
  // ──────────────────────────────────────────────
  describe('transactionId 処理', () => {
    test('数値文字列の transactionId はそのままリクエスト URL に使用される', async () => {
      const numericId = '2000001147800705';
      const signedTxInfo = await makeValidSignedTransactionInfo({ transactionId: numericId });
      (global.fetch as jest.Mock).mockResolvedValueOnce({
        ok: true,
        json: () => Promise.resolve({ signedTransactionInfo: signedTxInfo }),
      });

      await verifyAppStorePurchase(numericId);

      const calledUrl = (global.fetch as jest.Mock).mock.calls[0][0] as string;
      expect(calledUrl).toContain(`/inApps/v1/transactions/${numericId}`);
    });

    test('JWS 形式の transactionId から内部 transactionId を抽出してリクエストする', async () => {
      const innerTransactionId = '1234567890';
      const innerPayload = { transactionId: innerTransactionId };
      const header = Buffer.from(JSON.stringify({ alg: 'ES256' })).toString('base64url');
      const body = Buffer.from(JSON.stringify(innerPayload)).toString('base64url');
      const jwsToken = `${header}.${body}.fakesig`;

      const signedTxInfo = await makeValidSignedTransactionInfo({ transactionId: innerTransactionId });
      (global.fetch as jest.Mock).mockResolvedValueOnce({
        ok: true,
        json: () => Promise.resolve({ signedTransactionInfo: signedTxInfo }),
      });

      await verifyAppStorePurchase(jwsToken);

      const calledUrl = (global.fetch as jest.Mock).mock.calls[0][0] as string;
      expect(calledUrl).toContain(`/inApps/v1/transactions/${innerTransactionId}`);
    });
  });

  // ──────────────────────────────────────────────
  // エンドポイント切替
  // ──────────────────────────────────────────────
  describe('エンドポイント切替', () => {
    test('APP_STORE_ENVIRONMENT 未設定の場合はサンドボックスエンドポイントを使用する', async () => {
      const signedTxInfo = await makeValidSignedTransactionInfo();
      (global.fetch as jest.Mock).mockResolvedValueOnce({
        ok: true,
        json: () => Promise.resolve({ signedTransactionInfo: signedTxInfo }),
      });

      await verifyAppStorePurchase('tx_123');

      const calledUrl = (global.fetch as jest.Mock).mock.calls[0][0] as string;
      expect(calledUrl).toContain('api.storekit-sandbox.apple.com');
    });

    test('APP_STORE_ENVIRONMENT=production の場合は本番エンドポイントを使用する', async () => {
      process.env.APP_STORE_ENVIRONMENT = 'production';
      const signedTxInfo = await makeValidSignedTransactionInfo();
      (global.fetch as jest.Mock).mockResolvedValueOnce({
        ok: true,
        json: () => Promise.resolve({ signedTransactionInfo: signedTxInfo }),
      });

      await verifyAppStorePurchase('tx_123');

      const calledUrl = (global.fetch as jest.Mock).mock.calls[0][0] as string;
      expect(calledUrl).toContain('api.storekit.apple.com');
      expect(calledUrl).not.toContain('sandbox');
    });

    test('本番が 404 の場合はサンドボックスにフォールバックして検証する', async () => {
      // TestFlight の購入は本番配布ビルドでも Sandbox 扱いになる
      process.env.APP_STORE_ENVIRONMENT = 'production';
      const signedTxInfo = await makeValidSignedTransactionInfo();
      (global.fetch as jest.Mock)
        .mockResolvedValueOnce({
          ok: false,
          status: 404,
          text: () => Promise.resolve(JSON.stringify({ errorCode: 4040010 })),
        })
        .mockResolvedValueOnce({
          ok: true,
          json: () => Promise.resolve({ signedTransactionInfo: signedTxInfo }),
        });

      const result = await verifyAppStorePurchase('tx_123');

      const calls = (global.fetch as jest.Mock).mock.calls;
      expect(calls[0][0]).toContain('api.storekit.apple.com');
      expect(calls[1][0]).toContain('api.storekit-sandbox.apple.com');
      expect(result.valid).toBe(true);
    });

    test('404 以外のエラーではフォールバックしない', async () => {
      process.env.APP_STORE_ENVIRONMENT = 'production';
      (global.fetch as jest.Mock).mockResolvedValueOnce({
        ok: false,
        status: 401,
        text: () => Promise.resolve(''),
      });

      await expect(verifyAppStorePurchase('tx_123')).rejects.toThrow(
        'App Store API error: 401'
      );
      expect((global.fetch as jest.Mock)).toHaveBeenCalledTimes(1);
    });
  });

  // ──────────────────────────────────────────────
  // API エラーハンドリング
  // ──────────────────────────────────────────────
  describe('API エラーハンドリング', () => {
    test('App Store API が 401 を返した場合は例外をスローする', async () => {
      // JWT 認証失敗（本番/サンドボックスの環境不一致など）
      (global.fetch as jest.Mock).mockResolvedValueOnce({
        ok: false,
        status: 401,
        text: () => Promise.resolve(''),
      });

      await expect(verifyAppStorePurchase('tx_123')).rejects.toThrow(
        'App Store API error: 401'
      );
    });

    test('両方の環境で 404 の場合は例外をスローする', async () => {
      // トランザクション ID が存在しない場合
      const notFound = () => ({
        ok: false,
        status: 404,
        text: () => Promise.resolve(JSON.stringify({ errorCode: 4040010 })),
      });
      (global.fetch as jest.Mock)
        .mockResolvedValueOnce(notFound())
        .mockResolvedValueOnce(notFound());

      await expect(verifyAppStorePurchase('tx_123')).rejects.toThrow(
        'App Store API error: 404'
      );
      expect((global.fetch as jest.Mock)).toHaveBeenCalledTimes(2);
    });
  });

  // ──────────────────────────────────────────────
  // サブスクリプションステータス判定
  // ──────────────────────────────────────────────
  describe('サブスクリプションステータス判定', () => {
    test('期限内のサブスクリプション → status=active / valid=true を返す', async () => {
      const futureExpiry = Date.now() + 86_400_000;
      const signedTxInfo = await makeValidSignedTransactionInfo({ expiresDate: futureExpiry });
      (global.fetch as jest.Mock).mockResolvedValueOnce({
        ok: true,
        json: () => Promise.resolve({ signedTransactionInfo: signedTxInfo }),
      });

      const result = await verifyAppStorePurchase('tx_123');

      expect(result.status).toBe('active');
      expect(result.valid).toBe(true);
      expect(result.originalTransactionId).toBe('orig_tx_123');
    });

    test('expiresDate が過去の場合 → status=expired を返す', async () => {
      const pastExpiry = Date.now() - 86_400_000;
      const signedTxInfo = await makeValidSignedTransactionInfo({ expiresDate: pastExpiry });
      (global.fetch as jest.Mock).mockResolvedValueOnce({
        ok: true,
        json: () => Promise.resolve({ signedTransactionInfo: signedTxInfo }),
      });

      const result = await verifyAppStorePurchase('tx_123');

      expect(result.status).toBe('expired');
    });

    test('revocationDate が存在する場合 → status=expired / valid=false を返す', async () => {
      const signedTxInfo = await makeValidSignedTransactionInfo({ revocationDate: Date.now() - 3600_000 });
      (global.fetch as jest.Mock).mockResolvedValueOnce({
        ok: true,
        json: () => Promise.resolve({ signedTransactionInfo: signedTxInfo }),
      });

      const result = await verifyAppStorePurchase('tx_123');

      expect(result.status).toBe('expired');
      expect(result.valid).toBe(false);
    });

    // expires_at が無い premium は期限切れフォールバックが働かず永久 premium になる
    test('expiresDate なしのトランザクション → expiresAt=null / status=expired を返す', async () => {
      const signedTxInfo = await makeValidSignedTransactionInfo({ expiresDate: undefined });
      (global.fetch as jest.Mock).mockResolvedValueOnce({
        ok: true,
        json: () => Promise.resolve({ signedTransactionInfo: signedTxInfo }),
      });

      const result = await verifyAppStorePurchase('tx_123');

      expect(result.expiresAt).toBeNull();
      expect(result.status).toBe('expired');
    });

    test('renewalInfo の autoRenewStatus=0 → status=canceled / autoRenewing=false を返す', async () => {
      const signedTxInfo = await makeValidSignedTransactionInfo();
      const signedRenewalInfo = await createValidJws({
        autoRenewStatus: 0,
        originalTransactionId: 'orig_tx_123',
        productId: 'com.thaimemo.monthly',
      });
      (global.fetch as jest.Mock)
        .mockResolvedValueOnce({
          ok: true,
          json: () => Promise.resolve({ signedTransactionInfo: signedTxInfo }),
        })
        .mockResolvedValueOnce({
          ok: true,
          json: () => Promise.resolve({
            data: [{ lastTransactions: [{ originalTransactionId: 'orig_tx_123', signedRenewalInfo }] }],
          }),
        });

      const result = await verifyAppStorePurchase('tx_123');

      expect(result.status).toBe('canceled');
      expect(result.autoRenewing).toBe(false);
      // 期限内なので valid は true（premium は期限まで維持）
      expect(result.valid).toBe(true);
    });

    test('renewalInfo の autoRenewStatus=1 → status=active / autoRenewing=true を返す', async () => {
      const signedTxInfo = await makeValidSignedTransactionInfo();
      const signedRenewalInfo = await createValidJws({
        autoRenewStatus: 1,
        originalTransactionId: 'orig_tx_123',
        productId: 'com.thaimemo.monthly',
      });
      (global.fetch as jest.Mock)
        .mockResolvedValueOnce({
          ok: true,
          json: () => Promise.resolve({ signedTransactionInfo: signedTxInfo }),
        })
        .mockResolvedValueOnce({
          ok: true,
          json: () => Promise.resolve({
            data: [{ lastTransactions: [{ originalTransactionId: 'orig_tx_123', signedRenewalInfo }] }],
          }),
        });

      const result = await verifyAppStorePurchase('tx_123');

      expect(result.status).toBe('active');
      expect(result.autoRenewing).toBe(true);
    });

    test('subscriptions API が失敗した場合 → status=active / autoRenewing=true にフォールバックする', async () => {
      const signedTxInfo = await makeValidSignedTransactionInfo();
      (global.fetch as jest.Mock)
        .mockResolvedValueOnce({
          ok: true,
          json: () => Promise.resolve({ signedTransactionInfo: signedTxInfo }),
        })
        .mockResolvedValueOnce({
          ok: false,
          status: 500,
        });

      const result = await verifyAppStorePurchase('tx_123');

      expect(result.status).toBe('active');
      expect(result.autoRenewing).toBe(true);
    });

    test('subscriptions API には originalTransactionId でリクエストされる', async () => {
      const signedTxInfo = await makeValidSignedTransactionInfo();
      (global.fetch as jest.Mock)
        .mockResolvedValueOnce({
          ok: true,
          json: () => Promise.resolve({ signedTransactionInfo: signedTxInfo }),
        })
        .mockResolvedValueOnce({ ok: false, status: 404 });

      await verifyAppStorePurchase('tx_123');

      const secondUrl = (global.fetch as jest.Mock).mock.calls[1][0] as string;
      expect(secondUrl).toContain('/inApps/v1/subscriptions/orig_tx_123');
    });

    test('リクエストヘッダーに Authorization: Bearer <JWT> が設定される', async () => {
      const signedTxInfo = await makeValidSignedTransactionInfo();
      (global.fetch as jest.Mock).mockResolvedValueOnce({
        ok: true,
        json: () => Promise.resolve({ signedTransactionInfo: signedTxInfo }),
      });

      await verifyAppStorePurchase('tx_123');

      const calledOptions = (global.fetch as jest.Mock).mock.calls[0][1] as RequestInit;
      const authHeader = (calledOptions.headers as Record<string, string>)?.Authorization;
      // JWT は "Bearer eyJ..." 形式
      expect(authHeader).toMatch(/^Bearer eyJ/);
    });
  });
});
