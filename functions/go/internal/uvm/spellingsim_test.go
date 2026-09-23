package uvm

import (
	"fmt"
	"math/rand"
	"os"
	"testing"
)

// 綴り4択（FormatScale=0.5）が estimated_vocab の進みをどれだけ鈍らせるかの
// シミュレーション（SIM=1 で実行）。
//
//	SIM=1 go test ./internal/uvm -run TestSimSpellingScale -v
//
// 入力は本番実測（2026-09、語彙テスト100未満の104人 / 語1,194 / 回答3,597）:
//   - 1語あたりの回答数 平均 3.01（2回以上出た語 61.6%）
//   - 綴り4択にできる語は 58.2%、その語への回答は全体の 51.0%
//
// 出題は「初見で正解したらその語は次から穴埋め」なので、綴りに回るのは
// 各語の最初の数回だけ。重複が多いほど影響は薄まる。
const (
	simSpellEligible = 0.582 // 綴り4択にできる語の割合
	simSpellRepeat   = 0.66  // 既出の語をもう一度出す確率（平均3.0回/語に合わせる）
	simSpellDays     = 60
	simSpellPerDay   = 5
)

type spellSimWord struct {
	rank   int
	p      float64
	elig   bool
	passed bool
	seen   int
}

// runSpellingSim は estimated_vocab の日次推移を返す。
// spelling が false なら全部従来の穴埋め。
func runSpellingSim(
	rnd *rand.Rand, trueVocab int, spelling bool, repeat float64,
) ([]int, float64) {
	words := map[int]*spellSimWord{}
	var order []int
	next := 1
	est := 0
	var hist []int
	spellAnswers, total := 0, 0

	for day := 0; day < simSpellDays; day++ {
		for q := 0; q < simSpellPerDay; q++ {
			var w *spellSimWord
			if len(order) > 0 && rnd.Float64() < repeat {
				w = words[order[rnd.Intn(len(order))]]
			} else {
				w = &spellSimWord{rank: next, p: NewWordP, elig: rnd.Float64() < simSpellEligible}
				words[next] = w
				order = append(order, next)
				next++
			}
			w.seen++
			total++

			useSpelling := spelling && w.elig && !w.passed
			guess := BayesGuessTop // 穴埋めは 0.35
			scale := 1.0
			if useSpelling {
				guess = 0.25 // ダミーが全部非語なので素の4択
				scale = SpellingChoiceScale
				spellAnswers++
			}

			known := w.rank <= trueVocab
			pCorrect := guess
			if known {
				pCorrect = 1 - BayesSlip
			}
			correct := rnd.Float64() < pCorrect
			// P の更新は本番と同じく hint_level から g を取る（0.35 固定）。
			w.p = UpdateP(w.p, correct, 0, scale)
			if useSpelling && correct {
				w.passed = true
			}
		}

		entries := make([]RankedP, 0, len(words))
		for _, w := range words {
			entries = append(entries, RankedP{Rank: w.rank, P: w.p})
		}
		est = EstimateVocab(entries, est, 0)
		hist = append(hist, est)
	}
	return hist, float64(spellAnswers) / float64(total)
}

func TestSimSpellingScale(t *testing.T) {
	if os.Getenv("SIM") == "" {
		t.Skip("SIM=1 で実行")
	}
	const trials = 200
	run := func(trueVocab int, spelling bool, repeat float64) ([]float64, float64) {
		sum := make([]float64, simSpellDays)
		share := 0.0
		for i := 0; i < trials; i++ {
			rnd := rand.New(rand.NewSource(int64(i)))
			hist, s := runSpellingSim(rnd, trueVocab, spelling, repeat)
			share += s
			for d, v := range hist {
				sum[d] += float64(v) / trials
			}
		}
		return sum, 100 * share / trials
	}

	t.Log("--- 実測の重複（平均3.0回/語）で真値を振る ---")
	for _, trueVocab := range []int{50, 100, 200} {
		base, _ := run(trueVocab, false, simSpellRepeat)
		with, share := run(trueVocab, true, simSpellRepeat)
		t.Logf("真値%3d: d14 %.0f→%.0f / d30 %.0f→%.0f / d60 %.0f→%.0f (綴り %.0f%%)",
			trueVocab, base[13], with[13], base[29], with[29], base[59], with[59], share)
	}

	t.Log("--- 重複の量を振る（真値100）---")
	for _, repeat := range []float64{0.0, 0.33, 0.66, 0.85} {
		base, _ := run(100, false, repeat)
		with, share := run(100, true, repeat)
		perWord := 1 / (1 - repeat)
		t.Logf("重複%.0f%%（平均%.1f回/語）: d30 %.0f→%.0f (%.1f%%) / d60 %.0f→%.0f (%.1f%%) 綴り %.0f%%",
			100*repeat, perWord,
			base[29], with[29], 100*(with[29]-base[29])/base[29],
			base[59], with[59], 100*(with[59]-base[59])/base[59], share)
	}
	fmt.Println()
}
