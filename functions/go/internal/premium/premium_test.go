package premium

import (
	"testing"
	"time"
)

func TestIsEffectivePremiumUsesSubscriptionWhileTierCatchesUp(t *testing.T) {
	now := time.Date(2026, 9, 13, 0, 0, 0, 0, time.UTC)
	cases := []struct {
		name string
		data map[string]any
		want bool
	}{
		{
			name: "tierはfreeでも有効期限内",
			data: map[string]any{"tier": "free", "subscription": map[string]any{
				"status": "active", "expires_at": now.Add(time.Hour),
			}},
			want: true,
		},
		{
			name: "tierはfreeでも買い切り",
			data: map[string]any{"tier": "free", "subscription": map[string]any{
				"lifetime": true, "status": "active",
			}},
			want: true,
		},
		{
			name: "取消済み買い切りは復活させない",
			data: map[string]any{"tier": "free", "subscription": map[string]any{
				"lifetime": true, "status": "expired",
			}},
			want: false,
		},
		{
			name: "取消済み購読は期限が未来でも復活させない",
			data: map[string]any{"tier": "free", "subscription": map[string]any{
				"status": "expired", "expires_at": now.Add(time.Hour),
			}},
			want: false,
		},
		{
			name: "保留中の購読は期限が未来でも復活させない",
			data: map[string]any{"tier": "free", "subscription": map[string]any{
				"status": "on_hold", "expires_at": now.Add(time.Hour),
			}},
			want: false,
		},
		{
			name: "猶予期間内",
			data: map[string]any{"tier": "free", "subscription": map[string]any{
				"status": "grace_period", "expires_at": now.Add(-24 * time.Hour),
			}},
			want: true,
		},
		{
			name: "期限切れ",
			data: map[string]any{"tier": "free", "subscription": map[string]any{
				"status": "expired", "expires_at": now.Add(-time.Hour),
			}},
			want: false,
		},
		{
			name: "期限の無い月額記録",
			data: map[string]any{"tier": "free", "subscription": map[string]any{
				"status": "active", "lifetime": false,
			}},
			want: false,
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := IsEffectivePremium(tc.data, now); got != tc.want {
				t.Fatalf("IsEffectivePremium() = %v, want %v", got, tc.want)
			}
		})
	}
}
