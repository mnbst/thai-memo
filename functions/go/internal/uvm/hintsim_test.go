package uvm

import (
	"math"
	"math/rand"
	"testing"
)

// legacyGuessRate は 2026-11 までの GuessRate（ヒント段の g を BayesGuessTop の
// 倍数で置き、MaxGuessRate で頭打ち）。
func legacyGuessRate(hintLevel int) float64 {
	switch hintLevel {
	case 0:
		return BayesGuessTop
	case 1:
		return math.Min(MaxGuessRate, BayesGuessTop*1.8)
	default:
		return math.Min(MaxGuessRate, BayesGuessTop*3.0)
	}
}

// legacyUpdateP は UpdateP の g だけを legacyGuessRate にしたもの。
func legacyUpdateP(p float64, correct bool, hintLevel int, weight float64) float64 {
	p = math.Max(1e-6, math.Min(1-1e-6, p))
	g := legacyGuessRate(hintLevel)
	lr := BayesSlip / (1 - g)
	if correct {
		lr = (1 - BayesSlip) / g
	}
	odds := p / (1 - p) * math.Pow(lr, weight)
	lower := math.Min(PFloor, p)
	return math.Max(lower, math.Min(PMax, odds/(1+odds)))
}

// pickHint は mix（ヒント段 0/1/2 の割合）から 1 問ぶんのヒント段を引く。
func pickHint(rnd *rand.Rand, mix []float64) int {
	x := rnd.Float64()
	for h, w := range mix {
		if x < w {
			return h
		}
		x -= w
	}
	return len(mix) - 1
}

// TestHintRecovery は PFloor から何問連続正解で P>0.5 に戻るかを固定する。
// ヒント段の g を決めた根拠（HintPronGuess のコメント）そのもの。
func TestHintRecovery(t *testing.T) {
	for _, c := range []struct{ hint, want int }{{0, 2}, {1, 5}, {2, 9}} {
		p, n := PFloor, 0
		for p <= 0.5 {
			p = UpdateP(p, true, c.hint, 1)
			n++
		}
		if n != c.want {
			t.Errorf("hint=%d: PFloor から %d 問で 0.5 超え（期待 %d）", c.hint, n, c.want)
		}
	}
}

// TestHintGuessSweep はヒント段の g を旧値（発音 0.63・日本語 0.80）から新値
// （0.55・0.63）へ変えたときの d90 と誤既知を比べる。
//
// 世界側の推測率は 2 通り振る:
//   - sim既定 : 0.25 / 0.45 / 0.75（日本語ヒントでほぼ当たる悲観側）
//   - prod寄り: 0.35 / 0.50 / 0.55（prod 実測の正答率 81/77/56% の上限に合わせる）
//
// ユーザーはヒント段を常用（0/1/2）と、prod で見えた混ぜ方（uvlWqP 型
// 30/51/18%、KCYhqP 型 9/0/91%）。
func TestHintGuessSweep(t *testing.T) {
	trials := 20
	worlds := []struct {
		name string
		g    []float64
	}{
		{"sim既定", []float64{0.25, 0.45, 0.75}},
		{"prod寄り", []float64{0.35, 0.50, 0.55}},
	}
	users := []struct {
		name string
		mix  []float64
	}{
		{"常にh0", []float64{1, 0, 0}},
		{"常にh1", []float64{0, 1, 0}},
		{"常にh2", []float64{0, 0, 1}},
		{"uvlWqP型", []float64{0.30, 0.51, 0.19}},
		{"KCYhqP型", []float64{0.09, 0, 0.91}},
	}
	for _, w := range worlds {
		for _, slip := range []float64{0.05, 0.15} {
			t.Logf("=== 世界 %s slip=%.2f  （d90 / 誤既知%%）旧→新 ===", w.name, slip)
			t.Logf("%-10s %22s %22s %22s", "ユーザー", "真150", "真350", "真700")
			for _, us := range users {
				row := []any{us.name}
				for _, truth := range []int{150, 350, 700} {
					var res [2][2]float64
					for i, legacy := range []bool{true, false} {
						var d90, bad, known int
						for s := range trials {
							r, u := runCellUser(s+1, truth, false, true, 90, func(u *simUser) {
								u.hintMix = us.mix
								u.worldHintG = w.g
								u.worldSlip = slip
								u.legacyHintG = legacy
								u.dynCutoff = 0.45
							})
							d90 += r[90]
							b, k := falseKnown(u)
							bad += b
							known += k
						}
						res[i][0] = float64(d90) / float64(trials)
						res[i][1] = 100 * float64(bad) / math.Max(1, float64(known))
					}
					row = append(row, res[0][0], res[0][1], res[1][0], res[1][1])
				}
				t.Logf("%-10s %4.0f/%3.0f%%→%4.0f/%3.0f%%  %4.0f/%3.0f%%→%4.0f/%3.0f%%  %4.0f/%3.0f%%→%4.0f/%3.0f%%", row...)
			}
		}
	}
}

// TestHintSteps は新語（NewWordP）が何問の正解で LearnedP を越えるかを固定する。
// ヒント段の g と FreshMultiplierFor を決めた根拠（HintPronGuess のコメント）。
func TestHintSteps(t *testing.T) {
	for _, c := range []struct{ hint, full, fresh int }{{0, 1, 2}, {1, 2, 3}, {2, 3, 4}} {
		for _, k := range []struct {
			name   string
			weight float64
			want   int
		}{{"満額", 1, c.full}, {"当日", FreshMultiplierFor(c.hint), c.fresh}} {
			p, n := NewWordP, 0
			for p <= LearnedP {
				p = UpdateP(p, true, c.hint, k.weight)
				n++
			}
			if n != k.want {
				t.Errorf("hint=%d %s: %d 問で LearnedP 超え（期待 %d）", c.hint, k.name, n, k.want)
			}
		}
	}
}
