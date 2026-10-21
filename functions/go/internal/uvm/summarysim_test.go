package uvm

import (
	"math"
	"sort"
	"testing"
)

// prodSummaryPick は本番のまとめクイズの選び方（generate_quiz_srs.go の
// selectSentencesBySRS）を写す。
//
//   - SRS 枠: 問題数の半分まで（最大2）。1/3/7/14/30 日前をランダム順に見て、
//     その日に出た key_word のうち P が最も低い語を1つずつ。
//   - 補充枠: P の低い順に 50 語取り、「2回以上出題して P<0.3」を先頭に、
//     残りは P の低い順。直近 90 日に出た語だけ。
//   - 受験者は測定値より下の語を外し、空ならやり直す（quizKeyWordFilter）。
func (u *simUser) prodSummaryPick(n int) []int {
	pick := func(useFloor bool) []int {
		allowed := func(r int) bool { return !useFloor || u.floor <= 0 || r >= u.floor }
		used := map[int]bool{}
		var out []int

		srsLimit := min(2, n/2)
		intervals := []int{1, 3, 7, 14, 30}
		u.rnd.Shuffle(len(intervals), func(i, j int) {
			intervals[i], intervals[j] = intervals[j], intervals[i]
		})
		for _, iv := range intervals {
			if len(out) >= srsLimit {
				break
			}
			best, bestP := -1, math.Inf(1)
			for r, d := range u.bornDay {
				if d == u.day-iv && allowed(r) && u.words[r].p < bestP {
					best, bestP = r, u.words[r].p
				}
			}
			if best >= 0 {
				out = append(out, best)
				used[best] = true
			}
		}

		weak := func(r int) bool { w := u.words[r]; return w.attempts >= 2 && w.p < 0.3 }
		order := func(rs []int) {
			sort.Slice(rs, func(i, j int) bool {
				wi, wj := weak(rs[i]), weak(rs[j])
				if wi != wj {
					return wi
				}
				pi, pj := u.words[rs[i]].p, u.words[rs[j]].p
				if pi != pj {
					return pi < pj
				}
				return rs[i] < rs[j]
			})
		}
		if u.bandSummary {
			// 案: SyncEstimatedVocab と同じ走査帯の語を先に出す。
			low, high := max(u.floor, u.est-50), u.est+51
			var band []int
			for r := range u.words {
				if r >= low && r < high {
					band = append(band, r)
				}
			}
			order(band)
			for _, r := range band {
				if len(out) >= n {
					break
				}
				if used[r] || !allowed(r) || u.day-u.bornDay[r] > 90 {
					continue
				}
				out = append(out, r)
				used[r] = true
			}
		}

		var byP []int
		for r := range u.words {
			byP = append(byP, r)
		}
		sort.Slice(byP, func(i, j int) bool {
			pi, pj := u.words[byP[i]].p, u.words[byP[j]].p
			if pi != pj {
				return pi < pj
			}
			return byP[i] < byP[j]
		})
		byP = byP[:min(50, len(byP))]
		sort.SliceStable(byP, func(i, j int) bool {
			wi, wj := weak(byP[i]), weak(byP[j])
			if wi != wj {
				return wi
			}
			return u.words[byP[i]].p < u.words[byP[j]].p
		})
		for _, r := range byP {
			if len(out) >= n {
				break
			}
			if used[r] || !allowed(r) || u.day-u.bornDay[r] > 90 {
				continue
			}
			out = append(out, r)
			used[r] = true
		}
		return out
	}
	if out := pick(true); len(out) > 0 {
		return out
	}
	return pick(false)
}

// TestSummaryContribution は、確認クイズだけの語を推定の母数から外したとき
// （learningInPool=false、2026-10 からの本番）に、伸びとまとめクイズの寄与が
// どう変わるかを見る。まとめクイズの出題は、旧シミュレーションの「出題済みを
// 古い順に巡回」と本番の選び方（prodSummary）の両方で回す。
//
// 生成%: 90日の est の動きのうち、例文生成（確認クイズ込み）の sync で
// 動いたぶんの割合（下げも含めた符号つき）。残りがまとめクイズ。
// 帯優先: 補充枠を SyncEstimatedVocab の走査帯の語から先に選ぶ案。
func TestSummaryContribution(t *testing.T) {
	trials := 20
	worlds := []struct {
		name        string
		guess, slip float64
	}{
		{"推測0.25/slip0", 0.25, 0},
		{"推測0.45/slip0.10", 0.45, 0.10},
	}
	for _, w := range worlds {
		t.Logf("##### 世界 %s #####", w.name)
		for _, truth := range []int{150, 350, 700} {
			t.Logf("=== 真値 %d ===", truth)
			t.Logf("%-22s %-6s %5s %5s %5s %7s %7s", "母数/出題", "受験", "d7", "d30", "d90", "生成%", "誤既知%")
			for _, mode := range []string{"巡回", "本番出題", "帯優先"} {
				for _, inPool := range []bool{true, false} {
					for _, tested := range []bool{false, true} {
						var d7, d30, d90, gen, sum, bad, known int
						for s := range trials {
							r, u := runCellUser(s+1, truth, tested, true, 90, func(u *simUser) {
								u.worldGuess = w.guess
								u.worldSlip = w.slip
								u.learningInPool = inPool
								u.prodSummary = mode != "巡回"
								u.bandSummary = mode == "帯優先"
								u.bornDay = map[int]int{}
							})
							d7 += r[7]
							d30 += r[30]
							d90 += r[90]
							gen += u.genGain
							sum += u.sumGain
							b, k := falseKnown(u)
							bad += b
							known += k
						}
						name := "確認込み"
						if !inPool {
							name = "確認除外"
						}
						name += "/" + mode
						label := "未受験"
						if tested {
							label = "受験"
						}
						genPct := 0.0
						if tot := abs(gen) + abs(sum); tot > 0 {
							genPct = 100 * float64(gen) / float64(tot)
						}
						fk := 0.0
						if known > 0 {
							fk = 100 * float64(bad) / float64(known)
						}
						t.Logf("%-20s %-6s %5d %5d %5d %6.0f%% %6.1f%%", name, label,
							d7/trials, d30/trials, d90/trials, genPct, fk)
					}
				}
			}
		}
	}
}
