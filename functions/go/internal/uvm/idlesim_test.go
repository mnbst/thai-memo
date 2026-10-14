package uvm

import (
	"math/rand"
	"testing"
)

// idleResult は休眠→復帰の推移。
type idleResult struct {
	before int    // 休眠直前
	back   [6]int // 復帰日: 例文生成1〜5回目の直後、まとめクイズ後
	week   int    // 復帰から7日後
}

// runIdle は activeDays 毎日使ってから idleDays 休み、戻って毎日使う。
// 1日の流れは runCellUser と同じ（例文5回 → まとめクイズ5問 → sync）で、
// 休眠中も含めて毎晩 dailyBatch の P 減衰（DecayP）をかける。
func runIdle(seed, truth int, tested bool, activeDays, idleDays int) idleResult {
	rnd := rand.New(rand.NewSource(int64(seed)))
	u := &simUser{rnd: rnd, truth: truth, words: map[int]*simWord{},
		sel: &SessionSelector{Rand: rnd}}
	if tested {
		u.floor = takeVocabTest(rnd, truth)
		u.est = u.floor
	}
	decay := func() {
		for _, w := range u.words {
			w.p = DecayP(w.p)
		}
	}
	day := func(r *idleResult) {
		for i := range 5 {
			u.generate(true)
			if r != nil {
				r.back[i] = u.est
			}
		}
		u.summaryQuiz(5)
		u.sync()
		if r != nil {
			r.back[5] = u.est
		}
		decay()
	}
	var res idleResult
	for range activeDays {
		day(nil)
	}
	res.before = u.est
	for range idleDays {
		decay()
	}
	day(&res)
	for range 7 {
		day(nil)
	}
	res.week = u.est
	return res
}

// TestIdleReturn は 90 日使ってから休んだ人が、戻った日にどこまで落ちるか。
//
// 休眠日数で P の減衰を速める案（最大10倍）はこれで退けた。未受験者は
// 走査帯ごと P が沈んで sync のたびに 50 ずつ落ち、真値350・60日休眠は
// 戻った翌週に 0、30日休眠でも 354→164。受験者は測定値の床で止まる。
// 等倍の現行は全ケースで休眠直前から 10 以内。
func TestIdleReturn(t *testing.T) {
	trials := 20
	for _, truth := range []int{150, 350, 700} {
		for _, tested := range []bool{true, false} {
			label := "受験"
			if !tested {
				label = "未受験"
			}
			t.Logf("=== 真値%d %s ===", truth, label)
			t.Logf("%-6s %5s %5s %5s %5s %5s %5s %5s %5s", "休眠", "直前", "g1", "g2", "g3", "g4", "g5", "まとめ", "+7日")
			for _, idle := range []int{0, 30, 60, 120} {
				var sum idleResult
				for s := range trials {
					r := runIdle(s+1, truth, tested, 90, idle)
					sum.before += r.before
					for i := range sum.back {
						sum.back[i] += r.back[i]
					}
					sum.week += r.week
				}
				b := sum.back
				t.Logf("%3d日 %5d %5d %5d %5d %5d %5d %5d %5d", idle,
					sum.before/trials, b[0]/trials, b[1]/trials, b[2]/trials, b[3]/trials,
					b[4]/trials, b[5]/trials, sum.week/trials)
				if drop := sum.before/trials - b[5]/trials; drop > 20 {
					t.Errorf("真値%d %s %d日休眠: 復帰日に %d 落ちた", truth, label, idle, drop)
				}
			}
		}
	}
}
