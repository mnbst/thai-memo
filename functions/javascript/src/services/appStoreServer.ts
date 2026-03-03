import * as jose from 'jose';
import { SecretManagerServiceClient } from '@google-cloud/secret-manager';

const secretClient = new SecretManagerServiceClient();
const projectId = process.env.GCLOUD_PROJECT;

export interface AppStoreVerificationResult {
  valid: boolean;
  originalTransactionId: string;
  expiresAt: Date | null;
  autoRenewing: boolean;
  status: 'active' | 'canceled' | 'expired' | 'grace_period';
}

export interface AppStoreNotificationPayload {
  notificationType: string;
  subtype?: string;
  data: {
    signedTransactionInfo: string;
    signedRenewalInfo?: string;
  };
}

interface TransactionInfo {
  originalTransactionId: string;
  transactionId: string;
  productId: string;
  expiresDate?: number;
  revocationDate?: number;
  type: string;
  environment: string;
}

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
 * App Store Server APIのJWTトークンを生成
 */
async function generateAppStoreJWT(): Promise<string> {
  const [privateKeyPem, keyId, issuerId] = await Promise.all([
    getSecret('appstore-connect-key'),
    getSecret('appstore-key-id'),
    getSecret('appstore-issuer-id'),
  ]);

  const privateKey = await jose.importPKCS8(privateKeyPem, 'ES256');

  const jwt = await new jose.SignJWT({})
    .setProtectedHeader({ alg: 'ES256', kid: keyId, typ: 'JWT' })
    .setIssuer(issuerId)
    .setIssuedAt()
    .setExpirationTime('20m')
    .setAudience('appstoreconnect-v1')
    .setSubject('com.gaku.thaimemo') // Bundle ID
    .sign(privateKey);

  return jwt;
}

/**
 * JWSペイロードをデコード（App Store Server Notification v2）
 *
 * 本番ではApple Root CAによる証明書チェーン検証が必要。
 * ここではペイロードのデコードを行う最小実装。
 */
export function decodeSignedPayload<T>(signedPayload: string): T {
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
 * App Store Server API v2でトランザクションを検証
 */
export async function verifyAppStorePurchase(
  transactionId: string
): Promise<AppStoreVerificationResult> {
  const jwt = await generateAppStoreJWT();
  const environment = process.env.APP_STORE_ENVIRONMENT === 'production'
    ? 'api.storekit' : 'api.storekit-sandbox';

  const url = `https://${environment}.apple.com/inApps/v1/transactions/${transactionId}`;

  const response = await fetch(url, {
    headers: { Authorization: `Bearer ${jwt}` },
  });

  if (!response.ok) {
    throw new Error(`App Store API error: ${response.status}`);
  }

  const body = await response.json() as { signedTransactionInfo: string };
  const txInfo = decodeSignedPayload<TransactionInfo>(body.signedTransactionInfo);

  const expiresAt = txInfo.expiresDate ? new Date(txInfo.expiresDate) : null;
  const isExpired = expiresAt ? expiresAt < new Date() : false;
  const isRevoked = !!txInfo.revocationDate;

  let status: AppStoreVerificationResult['status'];
  if (isRevoked || isExpired) {
    status = 'expired';
  } else {
    status = 'active';
  }

  return {
    valid: !isRevoked,
    originalTransactionId: txInfo.originalTransactionId,
    expiresAt,
    autoRenewing: true, // Will be updated by renewal info notifications
    status,
  };
}

/**
 * App Store Server Notification v2のペイロードをパースし処理結果を返す
 */
export function parseNotificationPayload(signedPayload: string): {
  notificationType: string;
  subtype?: string;
  transactionInfo: TransactionInfo;
  renewalInfo?: RenewalInfo;
} {
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
