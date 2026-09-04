package uvm

import (
	"math/rand"
	"testing"
)

// TestGenerationDrop は「例文を生成すると語彙スコアが少し落ちる」現象の再現。
// graded 導入前（全部を母数に入れる）と、前方帯をいじる案、導入後を比べる。
func TestGenerationDrop(t *testing.T) {
	trials := 20
	type cfg struct {
		name         string
		ahead        int
		answeredOnly bool
		legacy       bool
		noLearning   bool
	}
	cfgs := []cfg{
		{"実装前（全部を母数に）", 0, false, true, false},
		{"実装前 + 前方を狭める(8)", 8, false, true, false},
		{"実装前 + 前方を狭める(3)", 3, false, true, false},
		{"実装前 + 前方を広げる(40)", 40, false, true, false},
		{"実装後（等倍のみ）", 0, false, false, false},
		{"実装後 + 確認クイズ無し", 0, false, false, true},
	}
	for _, truth := range []int{150, 350, 700} {
		t.Logf("=== 真値 %d ===", truth)
		t.Logf("%-22s %8s %8s %8s", "設定", "d90", "低下回数", "平均低下")
		for _, c := range cfgs {
			var sumEst, sumDrops, sumWidth int
			for s := range trials {
				rnd := rand.New(rand.NewSource(int64(s + 1)))
				u := &simUser{rnd: rnd, truth: truth, words: map[int]*simWord{},
					sel: &SessionSelector{Rand: rnd}, aheadOverride: c.ahead,
					answeredOnly: c.answeredOnly, legacyUngraded: c.legacy}
				u.floor = takeVocabTest(rnd, truth)
				u.est = u.floor
				for range 90 {
					for range 5 {
						u.generate(!c.noLearning)
					}
					u.summaryQuiz(5)
					u.sync()
				}
				sumEst += u.est
				sumDrops += u.drops
				sumWidth += u.dropSum
			}
			avgDrop := 0.0
			if sumDrops > 0 {
				avgDrop = float64(sumWidth) / float64(sumDrops)
			}
			t.Logf("%-20s %8d %8d %8.1f", c.name, sumEst/trials, sumDrops/trials, avgDrop)
		}
	}
}
