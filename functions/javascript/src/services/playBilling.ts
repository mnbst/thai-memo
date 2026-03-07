/**
 * playBilling.ts — Google Play Developer API クライアント
 *
 * Google Play Developer API v3（Subscriptions v2）を使用して
 * Android サブスクリプション購入を検証するサービス。
 *
 * 【認証方式】
 * Google Cloud のサービスアカウント認証（ADC: Application Default Credentials）を使用。
 * Cloud Functions 上では自動的にプロジェクトのサービスアカウントが使われる。
 * Google Play Console で該当サービスアカウントに「財務データの閲覧」権限が必要。
 *
 * 【使用箇所】
 * - verifySubscription.ts: クライアントからの購入検証リクエスト時
 * - handlePlayNotification.ts: Google Play RTDN 受信時の再検証
 *
 * 【API エンドポイント】
 * purchases.subscriptionsv2.get — 購入トークンからサブスクリプション状態を取得
 */
import { GoogleAuth } from 'google-auth-library';

/** Google Play Developer API v3 のベース URL */
const PLAY_API_BASE = 'https://androidpublisher.googleapis.com/androidpublisher/v3';

/**
 * Google Play Subscriptions v2 API のレスポンス型
 *
 * lineItems: サブスクリプションに含まれるアイテム（通常は1つ）
 * subscriptionState: サブスクリプションの状態を表す列挙値
 *   - ACTIVE: 有効（自動更新される）
 *   - CANCELED: キャンセル済み（現在の期間終了まで有効）
 *   - IN_GRACE_PERIOD: 支払い猶予期間（決済失敗後の一定期間、まだサービス提供する）
 *   - ON_HOLD: 保留中（決済失敗が続きサービス停止だが、回復の余地あり）
 *   - PAUSED: 一時停止（ユーザーが自ら一時停止した）
 *   - EXPIRED: 期限切れ（完全に終了）
 */
interface SubscriptionPurchaseV2 {
  kind: string;
  lineItems?: Array<{
    productId: string;
    expiryTime: string;
    autoRenewingPlan?: {
      autoRenewEnabled: boolean;
    };
  }>;
  subscriptionState:
    | 'SUBSCRIPTION_STATE_ACTIVE'
    | 'SUBSCRIPTION_STATE_CANCELED'
    | 'SUBSCRIPTION_STATE_IN_GRACE_PERIOD'
    | 'SUBSCRIPTION_STATE_ON_HOLD'
    | 'SUBSCRIPTION_STATE_PAUSED'
    | 'SUBSCRIPTION_STATE_EXPIRED'
    | 'SUBSCRIPTION_STATE_PENDING_PURCHASE_CANCELED'
    | 'SUBSCRIPTION_STATE_UNSPECIFIED';
}

/** Play 購入検証の結果（アプリ内部で統一的に扱うための型） */
export interface PlayVerificationResult {
  valid: boolean;
  expiresAt: Date | null;
  autoRenewing: boolean;
  /** アプリ内で統一的に扱うステータス（Google Play の詳細な状態をマッピング） */
  status: 'active' | 'canceled' | 'expired' | 'grace_period';
}

/** Google Play Developer API へのアクセスに必要な OAuth2 認証クライアント */
const auth = new GoogleAuth({
  scopes: ['https://www.googleapis.com/auth/androidpublisher'],
});

/**
 * Google Play Developer API v3 でサブスクリプション購入を検証
 *
 * purchaseToken を使って Google のサーバーにサブスクリプション状態を問い合わせ、
 * アプリ内で統一的に扱えるステータス（active / canceled / expired / grace_period）に
 * マッピングして返す。
 *
 * @param packageName - Android アプリのパッケージ名（例: com.gaku.thaimemo）
 * @param subscriptionId - 商品ID（Google Play Console で設定した ID）
 * @param purchaseToken - 購入時にクライアントが受け取った購入トークン
 * @returns 検証結果（有効性、有効期限、自動更新状態、ステータス）
 */
export async function verifyPlayPurchase(
  packageName: string,
  subscriptionId: string,
  purchaseToken: string
): Promise<PlayVerificationResult> {
  const client = await auth.getClient();
  // Subscriptions v2 API: 購入トークンからサブスクリプション情報を取得
  const url = `${PLAY_API_BASE}/applications/${packageName}/purchases/subscriptionsv2/tokens/${purchaseToken}`;

  const response = await client.request<SubscriptionPurchaseV2>({ url });
  const data = response.data;

  // lineItems[0] にサブスクリプションの詳細（有効期限、自動更新状態）が含まれる
  const lineItem = data.lineItems?.[0];
  const expiresAt = lineItem?.expiryTime ? new Date(lineItem.expiryTime) : null;
  const autoRenewing = lineItem?.autoRenewingPlan?.autoRenewEnabled ?? false;

  // Google Play の詳細な状態をアプリ内の4種のステータスにマッピング
  // CANCELED: ユーザーがキャンセルしたが現在の期間は有効（Firestore では tier='premium' を維持）
  // IN_GRACE_PERIOD / ON_HOLD: 決済失敗だが回復の余地あり → grace_period として premium 維持
  // その他（EXPIRED, PAUSED 等）: サービス提供を停止 → expired として tier='free' に
  let status: PlayVerificationResult['status'];
  switch (data.subscriptionState) {
    case 'SUBSCRIPTION_STATE_ACTIVE':
      status = 'active';
      break;
    case 'SUBSCRIPTION_STATE_CANCELED':
      status = 'canceled';
      break;
    case 'SUBSCRIPTION_STATE_IN_GRACE_PERIOD':
    case 'SUBSCRIPTION_STATE_ON_HOLD':
      status = 'grace_period';
      break;
    default:
      status = 'expired';
      break;
  }

  return { valid: true, expiresAt, autoRenewing, status };
}
