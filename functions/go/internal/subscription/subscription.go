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

// IsLifetime は買い切り（非消費型）購入かどうか。
//
// 買い切りは expires_at を持たない。ストア購入で expires_at が無いものは
// 「期限判定が効かない premium」として free に落とす扱いなので、そこから
// 除外するためにこの目印を見る（verifySubscription が必ず書く）。
func IsLifetime(sub map[string]any) bool {
	lifetime, _ := sub["lifetime"].(bool)
	return lifetime
}

// LifetimeSource は買い切りの出所（"monthly_migration" なら無償移行、
// 空なら買い切りそのものの購入）。
func LifetimeSource(sub map[string]any) string {
	source, _ := sub["lifetime_source"].(string)
	return source
}

// LifetimeTransactionID は買い切りを検証したときの originalTransactionId。
//
// subscription.original_transaction_id は月額を再検証すると上書きされるため、
// 買い切りの返金・取消通知はこちらでも引けるようにしている。
func LifetimeTransactionID(sub map[string]any) string {
	id, _ := sub["lifetime_transaction_id"].(string)
	return id
}

// Entitled は subscription の記録だけを見て「まだ premium を維持してよいか」を返す。
// 期限切れフォールバック（dailyBatch / subscriptionStatus）の判定はここに集約する。
//
// margin は期限超過を見逃す幅（ストア通知の遅延ぶん）。grace_period は期限超過が
// 前提なので、margin が短くても GracePeriodMax まで維持する。
//
//   - 買い切り（購入・無償移行とも）: 期限を持たないのが正常なので常に維持する。
//     返金・取消は subscription.lifetime を落とす側で表現する。
//   - expires_at あり: 超過が margin 以内なら維持。
//   - expires_at なし: ストア購入なら期限判定が効かないので維持しない
//     （手動付与・体験トライアルの無期限はここで維持される）。
func Entitled(sub map[string]any, now time.Time, margin time.Duration) bool {
	if IsLifetime(sub) {
		return true
	}
	if status, _ := sub["status"].(string); status == "grace_period" &&
		margin < GracePeriodMax {
		margin = GracePeriodMax
	}
	expiresAt, ok := sub["expires_at"].(time.Time)
	if !ok {
		return !IsStorePlatform(sub["platform"])
	}
	return now.Sub(expiresAt) <= margin
}
