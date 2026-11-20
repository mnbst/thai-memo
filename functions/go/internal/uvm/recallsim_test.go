package uvm

import (
	"math"
	"math/rand"
	"sort"
	"testing"
)

// recallPick は本番のまとめクイズの選び方（generate_quiz_srs.go）の写し。
// SRS 2問（作った日が 1/3/7/14/30 日前ちょうど、日ごとに P 最低）→
// 苦手枠1（範囲外・2回以上・P<0.3）→ スコア枠（P 昇順・同点ランダム）→ 低P枠。
func (u *simUser) recallPick(n int) []int {
	used := map[int]bool{}
	var out []int
	add := func(r int) { out = append(out, r); used[r] = true }
	alive := func(r int) bool { return u.day-u.bornDay[r] <= 90 }

	intervals := []int{1, 3, 7, 14, 30}
	u.rnd.Shuffle(len(intervals), func(i, j int) { intervals[i], intervals[j] = intervals[j], intervals[i] })
	for _, iv := range intervals {
		if len(out) >= min(2, n/2) {
			break
		}
		best, bestP := -1, math.Inf(1)
		for r, d := range u.bornDay {
			if d == u.day-iv && u.words[r].p < bestP {
				best, bestP = r, u.words[r].p
			}
		}
		if best >= 0 {
			add(best)
		}
	}

	_, kwHigh := KeyWordBand(u.est, u.floor)
	low, high := max(u.floor, u.est-QuizScoreBehind), min(u.est+QuizScoreAhead, kwHigh)
	all := make([]int, 0, len(u.words))
	for r := range u.words {
		all = append(all, r)
	}
	u.rnd.Shuffle(len(all), func(i, j int) { all[i], all[j] = all[j], all[i] })
	sort.SliceStable(all, func(i, j int) bool { return u.words[all[i]].p < u.words[all[j]].p })
	var weak, band, rest []int
	for _, r := range all {
		w := u.words[r]
		switch {
		case r >= low && r <= high:
			band = append(band, r)
		case w.attempts >= 2 && w.p < 0.3:
			weak = append(weak, r)
		default:
			rest = append(rest, r)
		}
	}
	take := func(rs []int, limit int) {
		got := 0
		for _, r := range rs {
			if len(out) >= n || got >= limit {
				return
			}
			if used[r] || !alive(r) {
				continue
			}
			add(r)
			got++
		}
	}
	take(weak, 1)
	take(band, n)
	take(rest, n)
	return out
}

type recallStats struct {
	events  int // その日に見た語をまとめクイズで正解した回数
	within  map[int]int
	never   int
	gapSum  int
	gapN    int
	estD90  int
	repeats int // 正解後に再出題されたまでの日数のサンプル
}

func runRecall(seed, truth int, tested bool, scale, guess, slip float64) recallStats {
	rnd := rand.New(rand.NewSource(int64(seed)))
	u := &simUser{rnd: rnd, truth: truth, words: map[int]*simWord{},
		sel: &SessionSelector{Rand: rnd}, bornDay: map[int]int{},
		recentCorrectScale: scale, worldGuess: guess, worldSlip: slip}
	if tested {
		u.floor = takeVocabTest(rnd, truth)
		u.est = u.floor
	}
	const days, follow = 120, 60
	appear := map[int][]int{} // rank -> まとめクイズに出た日
	type ev struct{ rank, day int }
	var events []ev
	st := recallStats{within: map[int]int{}}
	for day := 1; day <= days; day++ {
		u.day = day
		for range 5 {
			u.generate(true)
		}
		for _, r := range u.recallPick(5) {
			fresh := u.lastSeen[r] == float64(day)
			u.answer(r, false)
			appear[r] = append(appear[r], day)
			if fresh && u.lastAnswer && day <= days-follow {
				events = append(events, ev{r, day})
			}
		}
		u.sync()
		if day == 90 {
			st.estD90 = u.est
		}
	}
	for _, e := range events {
		st.events++
		next := -1
		for _, d := range appear[e.rank] {
			if d > e.day {
				next = d - e.day
				break
			}
		}
		if next < 0 || next > follow {
			st.never++
			continue
		}
		st.gapSum += next
		st.gapN++
		for _, k := range []int{1, 7, 30} {
			if next <= k {
				st.within[k]++
			}
		}
	}
	return st
}

// TestRecallAfterFreshCorrect は「その日に見た語をまとめクイズで正解したあと、
// 何日後にまとめクイズへ戻ってくるか」を、正解の重みを半減する案と比べる。
// 追跡は正解から60日。
func TestRecallAfterFreshCorrect(t *testing.T) {
	trials := 10
	worlds := []struct {
		name        string
		guess, slip float64
	}{{"推測0.25/slip0", 0.25, 0}, {"推測0.45/slip0.10", 0.45, 0.10}}
	for _, w := range worlds {
		t.Logf("##### 世界 %s #####", w.name)
		t.Logf("%-5s %-6s %-6s %6s %6s %6s %6s %6s %6s", "真値", "受験", "案", "件数", "1日内", "7日内", "30日内", "60日無", "d90")
		for _, truth := range []int{150, 350, 700} {
			for _, tested := range []bool{false, true} {
				for _, scale := range []float64{0, 0.5} {
					var agg recallStats
					agg.within = map[int]int{}
					for s := range trials {
						r := runRecall(s+1, truth, tested, scale, w.guess, w.slip)
						agg.events += r.events
						agg.never += r.never
						agg.estD90 += r.estD90
						for k, v := range r.within {
							agg.within[k] += v
						}
					}
					pct := func(v int) float64 { return 100 * float64(v) / math.Max(1, float64(agg.events)) }
					label, name := "未受験", "現行"
					if tested {
						label = "受験"
					}
					if scale > 0 {
						name = "半減"
					}
					t.Logf("%-5d %-6s %-6s %6d %5.0f%% %5.0f%% %5.0f%% %5.0f%% %6d", truth, label, name,
						agg.events/trials, pct(agg.within[1]), pct(agg.within[7]), pct(agg.within[30]),
						pct(agg.never), agg.estD90/trials)
				}
			}
		}
	}
}
