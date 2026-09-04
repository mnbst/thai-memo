package uvm

import "testing"

// 等倍で採点された回答だけが境界推定の母数に入る（IsGradedResult）。
func TestIsGradedResult(t *testing.T) {
	cases := []struct {
		name     string
		quizType string
		result   Result
		want     bool
	}{
		{"まとめクイズ・ヒント無し", "review", Result{}, true},
		{"確認クイズ", "learning", Result{}, false},
		{"ヒント1段", "review", Result{HintLevel: 1}, false},
		{"ヒント2段", "review", Result{HintLevel: 2}, false},
		{"例文レビュー由来", "review", Result{SentenceReviewed: true}, false},
		{"quiz_type 未指定", "", Result{}, true},
	}
	for _, c := range cases {
		if got := IsGradedResult(c.quizType, c.result); got != c.want {
			t.Errorf("%s: IsGradedResult = %v, want %v", c.name, got, c.want)
		}
	}
}

// 採点区分を持たない既存 doc は母数に残す（移行中に母数が急減しない）。
func TestGradedFieldDefaultsToTrue(t *testing.T) {
	if !boolField(map[string]any{"p": 0.5}, "graded", true) {
		t.Error("graded の無い doc が母数から外れた")
	}
	if boolField(map[string]any{"graded": false}, "graded", true) {
		t.Error("graded=false の doc が母数に入った")
	}
}
