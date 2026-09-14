package uvm

import (
	"testing"
	"time"
)

func TestEstimatedVocabCapUsesEffectiveEntitlement(t *testing.T) {
	now := time.Date(2026, 9, 13, 0, 0, 0, 0, time.UTC)
	cases := []struct {
		name string
		data map[string]any
		want int
	}{
		{name: "freeは100", data: map[string]any{"tier": "free"}, want: 100},
		{
			name: "tier反映待ちでも有効な購読は上限なし",
			data: map[string]any{"tier": "free", "subscription": map[string]any{
				"status": "active", "expires_at": now.Add(time.Hour),
			}},
			want: -1,
		},
		{
			name: "期限切れ購読は100",
			data: map[string]any{"tier": "free", "subscription": map[string]any{
				"status": "expired", "expires_at": now.Add(-time.Hour),
			}},
			want: 100,
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := estimatedVocabCap(tc.data, now); got != tc.want {
				t.Fatalf("estimatedVocabCap() = %d, want %d", got, tc.want)
			}
		})
	}
}
