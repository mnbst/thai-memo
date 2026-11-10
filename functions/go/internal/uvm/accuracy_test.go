package uvm

import "testing"

func TestAppendSummaryRecent(t *testing.T) {
	got := AppendSummaryRecent("10", []Result{
		{IsCorrect: true},
		{IsCorrect: true, HintLevel: 1}, // ヒントありの正解は不正解として数える
		{IsCorrect: false},
	})
	if got != "10100" {
		t.Fatalf("got %q", got)
	}
	long := AppendSummaryRecent("00000000000000000000", []Result{{IsCorrect: true}})
	if len(long) != SummaryRecentSize || long[len(long)-1] != '1' {
		t.Fatalf("got %q", long)
	}
}

func TestSummaryCutoff(t *testing.T) {
	cases := []struct {
		recent string
		want   float64
	}{
		{"", VocabCutoffP},
		{"11111", 0.41},                // 1 回目から効く
		{"1111111110", 0.41},           // 90%
		{"1111011110", 0.42},           // 80%
		{"11110", 0.42},                // 80%
		{"11100", VocabCutoffP},        // 60%
		{"11000", summaryLowCutoff},    // 40%
		{"00000000000000000000", 0.49}, // 0%
	}
	for _, c := range cases {
		if got := SummaryCutoff(map[string]any{SummaryRecentField: c.recent}); got != c.want {
			t.Errorf("%q: got %v want %v", c.recent, got, c.want)
		}
	}
	for _, tier := range summaryCutoffTiers {
		if tier.cutoff <= UnknownWordP {
			t.Errorf("cutoff %v は UnknownWordP 以下", tier.cutoff)
		}
	}
}
