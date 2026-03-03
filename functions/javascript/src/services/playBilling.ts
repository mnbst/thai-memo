import { GoogleAuth } from 'google-auth-library';

const PLAY_API_BASE = 'https://androidpublisher.googleapis.com/androidpublisher/v3';

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

export interface PlayVerificationResult {
  valid: boolean;
  expiresAt: Date | null;
  autoRenewing: boolean;
  status: 'active' | 'canceled' | 'expired' | 'grace_period';
}

const auth = new GoogleAuth({
  scopes: ['https://www.googleapis.com/auth/androidpublisher'],
});

/**
 * Google Play Developer API v3 でサブスクリプション購入を検証
 */
export async function verifyPlayPurchase(
  packageName: string,
  subscriptionId: string,
  purchaseToken: string
): Promise<PlayVerificationResult> {
  const client = await auth.getClient();
  const url = `${PLAY_API_BASE}/applications/${packageName}/purchases/subscriptionsv2/tokens/${purchaseToken}`;

  const response = await client.request<SubscriptionPurchaseV2>({ url });
  const data = response.data;

  const lineItem = data.lineItems?.[0];
  const expiresAt = lineItem?.expiryTime ? new Date(lineItem.expiryTime) : null;
  const autoRenewing = lineItem?.autoRenewingPlan?.autoRenewEnabled ?? false;

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
