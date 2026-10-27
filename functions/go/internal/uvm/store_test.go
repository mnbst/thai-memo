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

func TestQuizScoreBand(t *testing.T) {
	now := time.Date(2026, 10, 19, 0, 0, 0, 0, time.UTC)
	cases := []struct {
		name      string
		data      map[string]any
		low, high int
	}{
		{
			name: "未受験premiumは後方50・前方は key_word 帯の上端まで",
			data: map[string]any{"tier": "premium", "estimated_vocab": int64(252)},
			low:  202, high: 260,
		},
		{
			name: "freeは上限100で切る",
			data: map[string]any{"tier": "free", "estimated_vocab": int64(100), "vocab_test_vocab": int64(500)},
			low:  100, high: 100,
		},
		{
			name: "freeの測定値が上限より下ならそこから見る",
			data: map[string]any{"tier": "free", "estimated_vocab": int64(60), "vocab_test_vocab": int64(40)},
			low:  40, high: 68,
		},
		{
			name: "受験者は測定値より下を見ない",
			data: map[string]any{"tier": "premium", "estimated_vocab": int64(520), "vocab_test_vocab": int64(500)},
			low:  500, high: 536,
		},
		{
			name: "上限到達者は前方が est×1.5% まで広がる",
			data: map[string]any{"tier": "premium", "estimated_vocab": int64(3000), "vocab_test_vocab": int64(3000)},
			low:  3000, high: 3045,
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			low, high := QuizScoreBand(tc.data, now)
			if low != tc.low || high != tc.high {
				t.Fatalf("QuizScoreBand = [%d, %d], want [%d, %d]", low, high, tc.low, tc.high)
			}
		})
	}
}

func TestEstimateRangeFreeFloor(t *testing.T) {
	now := time.Date(2026, 10, 19, 0, 0, 0, 0, time.UTC)
	cases := []struct {
		name string
		data map[string]any
		want int
	}{
		{name: "未受験は0", data: map[string]any{"tier": "free", "estimated_vocab": int64(50)}, want: 0},
		{name: "上限より下は測定値", data: map[string]any{"tier": "free", "vocab_test_vocab": int64(40)}, want: 40},
		{name: "上限より上は100", data: map[string]any{"tier": "free", "vocab_test_vocab": int64(1395)}, want: 100},
		{name: "下限より下に落ちた人も範囲は下限から", data: map[string]any{"tier": "free", "estimated_vocab": int64(0), "vocab_test_vocab": int64(1395)}, want: 100},
		{name: "premiumは測定値そのまま", data: map[string]any{"tier": "premium", "vocab_test_vocab": int64(1395)}, want: 1395},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got, low, high := EstimateRange(tc.data, now)
			if got != tc.want || low < got || high <= low {
				t.Fatalf("EstimateRange = (%d, [%d, %d)), want tested %d", got, low, high, tc.want)
			}
		})
	}
}

// 測定 1395 の free が、上限付近の語を2つ間違えても 100 から落ちない
// （prod で 100 → 50 → 0 と落ちていた）。
func TestEstimateVocabFreeFloorKeepsScore(t *testing.T) {
	now := time.Date(2026, 10, 19, 0, 0, 0, 0, time.UTC)
	data := map[string]any{"tier": "free", "estimated_vocab": int64(100), "vocab_test_vocab": int64(1395)}
	tested, _, _ := EstimateRange(data, now)
	entries := []RankedP{{Rank: 98, P: 0.1}, {Rank: 101, P: 0.1}}
	if got := EstimateVocab(entries, 100, tested); got < 100 {
		t.Fatalf("EstimateVocab = %d, want >= 100", got)
	}
}
