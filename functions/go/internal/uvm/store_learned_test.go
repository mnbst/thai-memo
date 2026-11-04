package uvm

import "testing"

func TestIsNewlyLearned(t *testing.T) {
	cases := []struct {
		name       string
		oldP, newP float64
		quizType   string
		want       bool
	}{
		{"まとめクイズで境目を超えた", 0.4, 0.618, "", true},
		{"すでに覚えていた", 0.618, 0.797, "", false},
		{"正解しても届かない", 0.15, 0.3, "", false},
		{"確認クイズは数えない", 0.4, 0.618, "learning", false},
		{"下がった", 0.618, 0.27, "", false},
	}
	for _, c := range cases {
		if got := IsNewlyLearned(c.oldP, c.newP, c.quizType); got != c.want {
			t.Errorf("%s: got %v, want %v", c.name, got, c.want)
		}
	}
}
