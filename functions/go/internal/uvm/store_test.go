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
			name: "未受験premiumは後方50・前方8",
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
			data: map[string]any{"tier": "free", "estimated_vocab": int64(45), "vocab_test_vocab": int64(40)},
			low:  40, high: 53,
		},
		{
			name: "受験者は測定値より下を見ない",
			data: map[string]any{"tier": "premium", "estimated_vocab": int64(505), "vocab_test_vocab": int64(500)},
			low:  500, high: 513,
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

// 原点から OriginKnownSpan までは、覚えた語の最大 rank がスコアになる。
// 窓の平均がまだ届かない入門者の初回（綴り2問）でもスコアが動くことを固定する。
func TestEstimateVocabOriginKnownMax(t *testing.T) {
	cases := []struct {
		name          string
		entries       []RankedP
		center, floor int
		want          int
	}{
		{"未受験・15位を覚えた", []RankedP{{Rank: 3, P: 0.51}, {Rank: 15, P: 0.51}}, 0, 0, 15},
		{"未受験・帯の外は見ない", []RankedP{{Rank: 21, P: 0.62}}, 0, 0, 0},
		{"未受験・0.5以下は数えない", []RankedP{{Rank: 10, P: 0.5}}, 0, 0, 0},
		{"受験者は測定値が原点", []RankedP{{Rank: 512, P: 0.62}, {Rank: 530, P: 0.62}}, 500, 500, 512},
		{"測定値以下は見ない", []RankedP{{Rank: 495, P: 0.9}}, 500, 500, 500},
	}
	for _, c := range cases {
		if got := EstimateVocab(c.entries, c.center, c.floor); got != c.want {
			t.Errorf("%s: EstimateVocab = %d, want %d", c.name, got, c.want)
		}
	}
}

func TestAnswerMultiplier(t *testing.T) {
	now := 1_000_000.0
	fresh := map[string]any{"last_exposed_at": now - 3600}
	stale := map[string]any{"last_exposed_at": now - FreshExposureWindow}
	// 昨日の回答で last_seen だけ新しい語（例文に出たのは前日より前）。
	answeredYesterday := map[string]any{"last_seen": now - 3600, "last_exposed_at": now - 3*FreshExposureWindow}
	cases := []struct {
		name     string
		quizType string
		r        Result
		data     map[string]any
		want     float64
	}{
		{"まとめ・24時間以内の正解は半減", "", Result{IsCorrect: true}, fresh, FreshMultiplier},
		{"まとめ・24時間ちょうどは満額", "", Result{IsCorrect: true}, stale, 1},
		{"last_seen だけ新しい語は満額", "", Result{IsCorrect: true}, answeredYesterday, 1},
		{"last_exposed_at の無い旧 doc は満額", "", Result{IsCorrect: true}, map[string]any{"last_seen": now}, 1},
		{"未登録語は満額", "", Result{IsCorrect: true}, nil, 1},
		{"まとめ・24時間以内の不正解も弱める", "", Result{IsCorrect: false}, fresh, FreshMultiplier},
		{"まとめ・24時間過ぎの不正解は満額", "", Result{IsCorrect: false}, stale, 1},
		{"例文を見直した不正解は満額", "", Result{IsCorrect: false, SentenceReviewed: true}, fresh, 1},
		{"確認クイズの不正解は満額", "learning", Result{IsCorrect: false}, fresh, 1},
		{"例文を見直した正解は重ねない", "", Result{IsCorrect: true, SentenceReviewed: true}, fresh, SentenceReviewCorrectMultiplier},
		{"確認クイズの正解は従来どおり", "learning", Result{IsCorrect: true}, fresh, LearningCorrectMultiplier},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := answerMultiplier(tc.quizType, tc.r, tc.data, now); got != tc.want {
				t.Fatalf("answerMultiplier = %v, want %v", got, tc.want)
			}
		})
	}
}
