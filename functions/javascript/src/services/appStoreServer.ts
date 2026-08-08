/**
 * appStoreServer.ts — App Store Server API クライアント
 *
 * Apple の App Store Server API v1 を使用してサブスクリプション購入を検証するサービス。
 * また、App Store Server Notifications V2 の JWS ペイロードのデコードも担当する。
 *
 * 【認証方式】
 * App Store Server API は JWT（ES256 署名）による認証を使用する。
 * 認証に必要なシークレット（秘密鍵、Key ID、Issuer ID）は
 * GCP Secret Manager から取得する。
 *
 * 【使用箇所】
 * - verifySubscription.ts: クライアントからの購入検証リクエスト時に verifyAppStorePurchase() を呼出
 * - handleAppStoreNotification.ts: Apple からの通知受信時に parseNotificationPayload() を呼出
 *
 * 【環境切替】
 * - 本番: api.storekit.apple.com
 * - サンドボックス: api.storekit-sandbox.apple.com
 *   ※ APP_STORE_ENVIRONMENT 環境変数で切替（Cloud Functions の環境設定）
 *
 * 【署名検証】
 * parseNotificationPayload() は JWS の x5c 証明書チェーンを検証し、
 * リーフ証明書の公開鍵で署名を確認する。
 * チェーンのルートが Apple Root CA G3 であることをフィンガープリントで確認している。
 */
import * as crypto from 'crypto';
import * as jose from 'jose';
import { SecretManagerServiceClient } from '@google-cloud/secret-manager';

// Apple Root CA G3 の SHA-256 フィンガープリント（証明書ピン留め用）
// https://www.apple.com/certificateauthority/ から取得した公式ルート証明書に基づく
let _appleRootCaG3Fingerprint =
  '63:34:3A:BF:B8:9A:6A:03:EB:B5:7E:9B:3F:5F:A7:BE:7C:4F:5C:75:6F:30:17:B3:A8:C4:88:C3:65:3E:91:79';

export function getAppleRootCaFingerprint(): string {
  return _appleRootCaG3Fingerprint;
}

export function setAppleRootCaFingerprintForTest(fingerprint: string): void {
  _appleRootCaG3Fingerprint = fingerprint;
}

/** GCP Secret Manager クライアント（API キーやシークレットの取得に使用） */
const secretClient = new SecretManagerServiceClient();
const projectId = process.env.GCLOUD_PROJECT;
const defaultAppStoreBundleId = 'com.thaimemo.thaiMemo';

/** App Store 購入検証の結果 */
export interface AppStoreVerificationResult {
  valid: boolean;
  originalTransactionId: string;
  expiresAt: Date | null;
  autoRenewing: boolean;
  status: 'active' | 'canceled' | 'expired' | 'grace_period';
}

/** App Store Server Notifications V2 の通知ペイロード構造 */
export interface AppStoreNotificationPayload {
  notificationType: string;
  subtype?: string;
  data: {
    signedTransactionInfo: string;
    signedRenewalInfo?: string;
  };
}

/**
 * Apple のトランザクション情報（JWS デコード後の構造）
 *
 * originalTransactionId: サブスクリプションの初回購入時のトランザクションID。
 *   更新・復元時も同じ値が使われるため、ユーザー検索のキーとして Firestore に保存する。
 * expiresDate: サブスクリプションの有効期限（ミリ秒タイムスタンプ）
 * revocationDate: 返金・取消日（存在する場合はサブスクリプション無効）
 */
interface TransactionInfo {
  originalTransactionId: string;
  transactionId: string;
  productId: string;
  expiresDate?: number;
  revocationDate?: number;
  type: string;
  environment: string;
}

/**
 * Apple の更新情報（JWS デコード後の構造）
 *
 * autoRenewStatus: 自動更新の状態（1=ON, 0=OFF）
 * expirationIntent: 期限切れの理由（1=ユーザーキャンセル, 2=課金エラー, 3=同意なし, 4=商品変更）
 */
interface RenewalInfo {
  autoRenewStatus: number; // 1 = will renew, 0 = turned off
  originalTransactionId: string;
  productId: string;
  expirationIntent?: number;
}

/**
 * Secret Managerからシークレットを取得
 */
async function getSecret(secretId: string): Promise<string> {
  const name = `projects/${projectId}/secrets/${secretId}/versions/latest`;
  const [version] = await secretClient.accessSecretVersion({ name });
  const value = version.payload?.data?.toString();
  if (!value) throw new Error(`Secret ${secretId} is empty`);
  return value;
}

/**
 * App Store Server API 認証用の JWT トークンを生成
 *
 * Apple の App Store Server API は JWT（ES256 アルゴリズム）で認証する。
 * 必要なシークレットを Secret Manager から取得し、有効期限20分の JWT を生成する。
 * - appstore-connect-key: App Store Connect で生成した秘密鍵（.p8 ファイルの内容）
 * - appstore-key-id: API キーの Key ID
 * - appstore-issuer-id: App Store Connect の Issuer ID
 * - APP_STORE_BUNDLE_ID: 検証対象アプリの Bundle ID（未設定時は現行本番ID）
 */
async function generateAppStoreJWT(): Promise<string> {
  const [privateKeyPem, keyId, issuerId] = await Promise.all([
    getSecret('appstore-connect-key'),
    getSecret('appstore-key-id'),
    getSecret('appstore-issuer-id'),
  ]);
  const bundleId = process.env.APP_STORE_BUNDLE_ID || defaultAppStoreBundleId;

  const privateKey = await jose.importPKCS8(privateKeyPem, 'ES256');

  const jwt = await new jose.SignJWT({ bid: bundleId })
    .setProtectedHeader({ alg: 'ES256', kid: keyId, typ: 'JWT' })
    .setIssuer(issuerId)
    .setIssuedAt()
    .setExpirationTime('20m')
    .setAudience('appstoreconnect-v1')
    .sign(privateKey);

  return jwt;
}

/**
 * JWS（JSON Web Signature）ペイロードをデコード（署名検証なし）
 *
 * 署名検証済みの JWS からペイロードを取り出す用途に使用。
 * 呼び出し前に verifyAppleJwsSignature() で署名検証を行うこと。
 */
function decodeSignedPayload<T>(signedPayload: string): T {
  const parts = signedPayload.split('.');
  if (parts.length !== 3) {
    throw new Error('Invalid JWS format');
  }
  const payload = JSON.parse(
    Buffer.from(parts[1], 'base64url').toString('utf-8')
  );
  return payload as T;
}

/**
 * Apple からの JWS 通知ペイロードの署名を検証する
 *
 * x5c ヘッダーの証明書チェーンを検証し、リーフ証明書の公開鍵で JWS 署名を確認する。
 *
 * 検証内容:
 * 1. x5c チェーン内の各証明書が次の証明書で署名されていること
 * 2. ルート証明書のフィンガープリントが Apple Root CA G3 と一致すること
 * 3. リーフ証明書の公開鍵で JWS 署名が正当であること
 *
 * @throws 検証失敗時は Error をスロー
 */
async function verifyAppleJwsSignature(signedPayload: string): Promise<void> {
  const parts = signedPayload.split('.');
  if (parts.length !== 3) throw new Error('Invalid JWS format');

  const header = JSON.parse(Buffer.from(parts[0], 'base64url').toString('utf-8'));
  const x5c: string[] | undefined = header.x5c;

  if (!x5c || x5c.length < 2) {
    throw new Error('Missing or incomplete x5c certificate chain in JWS header');
  }

  // base64 DER → X509Certificate
  const certs = x5c.map(b64 => new crypto.X509Certificate(Buffer.from(b64, 'base64')));

  // 証明書チェーンの署名を検証（leaf → ... → root）
  for (let i = 0; i < certs.length - 1; i++) {
    if (!certs[i].verify(certs[i + 1].publicKey)) {
      throw new Error(`Certificate chain verification failed at index ${i}`);
    }
  }

  // ルート証明書が Apple CA であることをフィンガープリントで確認
  const rootCert = certs[certs.length - 1];
  const rootFingerprint = rootCert.fingerprint256;
  if (rootFingerprint !== _appleRootCaG3Fingerprint) {
    throw new Error(`Untrusted root CA fingerprint: ${rootFingerprint}`);
  }

  // リーフ証明書の公開鍵で JWS 署名を検証
  const leafPem = certs[0].publicKey.export({ type: 'spki', format: 'pem' }) as string;
  const publicKey = await jose.importSPKI(leafPem, 'ES256');
  await jose.compactVerify(signedPayload, publicKey);
}

/**
 * App Store Server API v1 でトランザクションを検証
 *
 * transactionId を使って Apple のサーバーにトランザクション情報を問い合わせ、
 * サブスクリプションの有効性（期限切れ・返金済みかどうか）を判定する。
 *
 * クライアント（iOS アプリ）から送られる purchase_token が transactionId として使用される。
 *
 * @param transactionId - iOS の購入時に取得したトランザクション ID
 * @returns 検証結果（有効性、有効期限、自動更新状態、ステータス）
 */
export async function verifyAppStorePurchase(
  transactionId: string
): Promise<AppStoreVerificationResult> {
  // StoreKit 2 の場合、serverVerificationData は JWS 形式（eyJ...）で届く
  // JWS をデコードして実際の transactionId を取り出す
  const parts = transactionId.split('.');
  if (parts.length === 3) {
    try {
      const payload = JSON.parse(Buffer.from(parts[1], 'base64url').toString('utf-8'));
      if (payload.transactionId) {
        transactionId = payload.transactionId;
      }
    } catch {
      // デコード失敗時はそのまま使用
    }
  }

  const jwt = await generateAppStoreJWT();
  const environment = process.env.APP_STORE_ENVIRONMENT === 'production'
    ? 'api.storekit' : 'api.storekit-sandbox';

  const url = `https://${environment}.apple.com/inApps/v1/transactions/${transactionId}`;

  const response = await fetch(url, {
    headers: { Authorization: `Bearer ${jwt}` },
  });

  if (!response.ok) {
    const errorBody = await response.text();
    console.error(`App Store API error: ${response.status}`, { transactionId, errorBody });
    throw new Error(`App Store API error: ${response.status}`);
  }

  const body = await response.json() as { signedTransactionInfo: string };
  await verifyAppleJwsSignature(body.signedTransactionInfo);
  const txInfo = decodeSignedPayload<TransactionInfo>(body.signedTransactionInfo);

  const expiresAt = txInfo.expiresDate ? new Date(txInfo.expiresDate) : null;
  // 自動更新サブスクなら expiresDate は必ず来る。無い場合に premium を付与すると
  // 期限判定が働かず永久 premium になるため、expired として扱う
  if (!expiresAt) {
    console.error('Transaction has no expiresDate; treating as expired', {
      transactionId,
      originalTransactionId: txInfo.originalTransactionId,
    });
  }
  const isExpired = expiresAt ? expiresAt < new Date() : true;
  const isRevoked = !!txInfo.revocationDate;

  // 自動更新状態は transaction API には含まれないため、subscriptions API から取得する。
  // 取得失敗時（null）は従来通り autoRenewing=true / active にフォールバック
  const renewalInfo = await fetchRenewalInfo(
    txInfo.originalTransactionId, jwt, environment
  );
  const autoRenewing = renewalInfo ? renewalInfo.autoRenewStatus === 1 : true;

  let status: AppStoreVerificationResult['status'];
  if (isRevoked || isExpired) {
    status = 'expired';
  } else if (renewalInfo && renewalInfo.autoRenewStatus === 0) {
    // 解約済み（自動更新OFF）だが期限内 → premium は期限まで維持
    status = 'canceled';
  } else {
    status = 'active';
  }

  return {
    valid: !isRevoked,
    originalTransactionId: txInfo.originalTransactionId,
    expiresAt,
    autoRenewing,
    status,
  };
}

/**
 * Get All Subscription Statuses API で最新の更新情報（RenewalInfo）を取得する
 *
 * transaction API のレスポンスには autoRenewStatus が含まれないため、
 * /inApps/v1/subscriptions/{originalTransactionId} から signedRenewalInfo を取得する。
 * 取得・検証に失敗しても購入検証自体は成立させたいので、失敗時は null を返す。
 */
async function fetchRenewalInfo(
  originalTransactionId: string,
  jwt: string,
  environment: string
): Promise<RenewalInfo | null> {
  try {
    const url = `https://${environment}.apple.com/inApps/v1/subscriptions/${originalTransactionId}`;
    const response = await fetch(url, {
      headers: { Authorization: `Bearer ${jwt}` },
    });
    if (!response.ok) {
      console.error(`App Store subscriptions API error: ${response.status}`, {
        originalTransactionId,
      });
      return null;
    }

    const body = await response.json() as {
      data?: Array<{
        lastTransactions?: Array<{
          originalTransactionId: string;
          signedRenewalInfo?: string;
        }>;
      }>;
    };
    const lastTx = body.data
      ?.flatMap(group => group.lastTransactions ?? [])
      .find(tx => tx.originalTransactionId === originalTransactionId);
    if (!lastTx?.signedRenewalInfo) return null;

    await verifyAppleJwsSignature(lastTx.signedRenewalInfo);
    return decodeSignedPayload<RenewalInfo>(lastTx.signedRenewalInfo);
  } catch (error) {
    console.error('Failed to fetch renewal info:', error);
    return null;
  }
}

/**
 * App Store Server Notifications V2 のペイロードを署名検証してパースする
 *
 * Apple からの通知は二重 JWS 構造になっている:
 * 1. 外側の JWS: 通知全体（notificationType, data を含む）← 署名検証する
 * 2. 内側の JWS: data.signedTransactionInfo（トランザクション詳細）と
 *    data.signedRenewalInfo（更新情報、オプション）← デコードのみ
 *
 * 署名検証に失敗した場合は Error をスローする。
 * handleAppStoreNotification.ts から呼び出される。
 */
export async function parseNotificationPayload(signedPayload: string): Promise<{
  notificationType: string;
  subtype?: string;
  transactionInfo: TransactionInfo;
  renewalInfo?: RenewalInfo;
}> {
  // 外側 JWS の署名を検証（x5c チェーン + Apple Root CA 確認）
  await verifyAppleJwsSignature(signedPayload);

  const notification = decodeSignedPayload<{
    notificationType: string;
    subtype?: string;
    data: {
      signedTransactionInfo: string;
      signedRenewalInfo?: string;
    };
  }>(signedPayload);

  const transactionInfo = decodeSignedPayload<TransactionInfo>(
    notification.data.signedTransactionInfo
  );

  let renewalInfo: RenewalInfo | undefined;
  if (notification.data.signedRenewalInfo) {
    renewalInfo = decodeSignedPayload<RenewalInfo>(
      notification.data.signedRenewalInfo
    );
  }

  return {
    notificationType: notification.notificationType,
    subtype: notification.subtype,
    transactionInfo,
    renewalInfo,
  };
}
