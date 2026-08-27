// Package subscription はサブスクリプション期限判定の定数。
// functions/javascript/src/constants/subscription.ts の移植。**両者を必ず一致させること。**
//
// ストア通知（App Store Server Notifications / Play RTDN）の取りこぼし時に
// premium が永久に残らないよう、フォールバック側で使う上限値を定義する。
// dailyBatch, subscriptionStatus で使用。
package subscription

import "time"

// ExpiryDemotionMargin は期限切れ判定の猶予。
// 更新直後の通知遅延で誤って free に落とさないため。
const ExpiryDemotionMargin = 24 * time.Hour

// GracePeriodMax は grace_period を premium のまま維持する上限。
//
// 猶予期間は Apple が最長16日、Google Play が最長30日。
// GRACE_PERIOD_EXPIRED / EXPIRED 通知を取りこぼしても、期限からこの期間を
// 過ぎた grace_period は free に落とす。
const GracePeriodMax = 30 * 24 * time.Hour

// storePlatforms はストア購入由来の subscription.platform 値（手動付与と区別する）。
var storePlatforms = []string{"ios", "android"}

// IsStorePlatform は JS の STORE_PLATFORMS.includes(subscription.platform)。
// platform が未設定・文字列以外なら false（JS では undefined が渡って false）。
func IsStorePlatform(platform any) bool {
	s, ok := platform.(string)
	if !ok {
		return false
	}
	for _, p := range storePlatforms {
		if p == s {
			return true
		}
	}
	return false
}
