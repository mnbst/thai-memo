/**
 * subscription.ts — サブスクリプション期限判定の定数
 *
 * ストア通知（App Store Server Notifications / Play RTDN）の取りこぼし時に
 * premium が永久に残らないよう、フォールバック側で使う上限値を定義する。
 * dailyBatch, subscriptionStatus で使用。
 */

/** 期限切れ判定の猶予（更新直後の通知遅延で誤って free に落とさないため） */
export const EXPIRY_DEMOTION_MARGIN_MS = 24 * 60 * 60 * 1000;

/**
 * grace_period を premium のまま維持する上限。
 *
 * 猶予期間は Apple が最長16日、Google Play が最長30日。
 * GRACE_PERIOD_EXPIRED / EXPIRED 通知を取りこぼしても、期限からこの期間を
 * 過ぎた grace_period は free に落とす。
 */
export const GRACE_PERIOD_MAX_MS = 30 * 24 * 60 * 60 * 1000;

/** ストア購入由来の subscription.platform 値（手動付与と区別する） */
export const STORE_PLATFORMS = ['ios', 'android'] as const;
