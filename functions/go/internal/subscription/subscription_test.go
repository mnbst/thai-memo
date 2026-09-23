package subscription

import (
	"testing"
	"time"
)

// TestEntitled は「まだ premium を維持してよいか」の判定。
// dailyBatch と subscriptionStatus が同じ規則を共有するための唯一の関数。
func TestEntitled(t *testing.T) {
	now := time.Date(2026, 10, 1, 0, 0, 0, 0, time.UTC)
	past := now.Add(-48 * time.Hour)
	future := now.Add(48 * time.Hour)

	cases := []struct {
		name   string
		sub    map[string]any
		margin time.Duration
		want   bool
	}{
		{"買い切りは期限が無くても維持", map[string]any{
			"platform": "ios", "lifetime": true, "status": "expired"},
			0, true},
		{"期限内", map[string]any{
			"platform": "ios", "status": "active", "expires_at": future},
			0, true},
		{"期限切れ（margin なし）", map[string]any{
			"platform": "ios", "status": "active", "expires_at": past},
			0, false},
		{"期限切れだが margin 内", map[string]any{
			"platform": "ios", "status": "active", "expires_at": past},
			ExpiryDemotionMargin * 3, true},
		{"猶予期間は margin が短くても上限まで維持", map[string]any{
			"platform": "ios", "status": "grace_period", "expires_at": past},
			0, true},
		{"猶予期間の上限超え", map[string]any{
			"platform": "ios", "status": "grace_period",
			"expires_at": now.Add(-GracePeriodMax - time.Hour)},
			0, false},
		{"ストア購入で expires_at なし", map[string]any{
			"platform": "android", "status": "active"},
			0, false},
		{"手動付与の無期限は維持", map[string]any{
			"platform": "manual", "status": "active"},
			0, true},
	}

	for _, c := range cases {
		if got := Entitled(c.sub, now, c.margin); got != c.want {
			t.Errorf("%s: Entitled=%t want=%t", c.name, got, c.want)
		}
	}
}
