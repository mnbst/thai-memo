package uvm

import (
	"math"
	"testing"
)

// 並び替え（word_order）をまとめクイズに混ぜたときの P 更新の決め方を比べる。
//
// 並び替えは key_word の意味より語順を測るので、世界側は穴埋めと別に持つ。
//   - slip: key_word を知っていても並びを間違える確率（文法・他の語で落とす）
//   - guess: key_word を知らなくても並びが合う確率（消去法で残りの枠に入る）
type wordOrderSim struct {
	perQuiz int // まとめクイズ5問のうち何問を並び替えにするか

	// モデル側。skip なら P も evidence も動かさない。
	skip  bool
	scale float64 // 証拠の重み（FormatScale）。0 なら 1
	slip  float64 // UpdateP の s。0 なら BayesSlip

	// 世界側
	worldSlip, worldGuess float64
	hint                  int // >0 ならまとめクイズのヒント段と別にこの段で解く
}

func (u *simUser) answerWordOrder(w *simWord, rank, hint int) {
	wo := u.wordOrder
	if wo.hint > 0 {
		hint = wo.hint
	}
	if wo.skip {
		return
	}
	var correct bool
	if u.rnd.Float64() < pKnow(rank, u.truth) {
		correct = u.rnd.Float64() >= wo.worldSlip
	} else {
		// ヒントを出すほど当たりやすい比は穴埋めと同じに保つ
		correct = u.rnd.Float64() < math.Min(0.95, wo.worldGuess*guessRate(hint)/guessRate(0))
	}
	scale := wo.scale
	if scale <= 0 {
		scale = 1
	}
	slip := wo.slip
	if slip <= 0 {
		slip = BayesSlip
	}
	w.p = bayesUpdate(w.p, correct, GuessRate(hint), slip, scale)
	w.p = math.Max(math.Min(PFloor, w.p), w.p)
	w.attempts++
	w.evidence += ResultEvidence("", Result{HintLevel: hint, FormatScale: scale})
	w.graded = true
}

// falseUnknown は回答済みで P<0.5 だが実際は知っている（pKnow>0.5）語の数。
func falseUnknown(u *simUser) int {
	n := 0
	for r, w := range u.words {
		if w.attempts > 0 && w.p < 0.5 && pKnow(r, u.truth) > 0.5 {
			n++
		}
	}
	return n
}

func TestWordOrderRule(t *testing.T) {
	trials := 20
	type rule struct {
		name string
		wo   *wordOrderSim // perQuiz と世界側は後で入れる
	}
	rules := []rule{
		{"穴埋めのみ(現行)", nil},
		{"並び替え=穴埋め扱い", &wordOrderSim{}},
		{"A scale.5", &wordOrderSim{scale: 0.5}},
		{"B s.40", &wordOrderSim{slip: 0.40}},
		{"P更新しない", &wordOrderSim{skip: true}},
	}
	worlds := []struct {
		name        string
		slip, guess float64
	}{
		{"slip.20 guess.25", 0.20, 0.25},
		{"slip.40 guess.25", 0.40, 0.25},
		{"slip.40 guess.50", 0.40, 0.50},
	}
	cells := []struct {
		tested bool
		truth  int
		hint   int // 並び替えのヒント段（入門は発音を最初から出す＝1）
	}{
		{false, 150, 1},
		{true, 150, 1},
		{true, 700, 0},
	}
	for _, wd := range worlds {
		for _, c := range cells {
			label := "未受験"
			if c.tested {
				label = "受験"
			}
			t.Logf("=== %s / %s 真値%d 並び替えヒント%d ===", wd.name, label, c.truth, c.hint)
			t.Logf("%-20s %6s %6s %8s %12s %8s", "決め方", "d30", "d90", "d90誤差", "誤既知/既知", "誤未知")
			for _, r := range rules {
				d30, d90, bad, known, fu := 0, 0, 0, 0, 0
				for s := range trials {
					res, u := runCellUser(s+1, c.truth, c.tested, true, 90, func(su *simUser) {
						if r.wo != nil {
							wo := *r.wo
							wo.perQuiz = 1
							wo.worldSlip, wo.worldGuess = wd.slip, wd.guess
							wo.hint = c.hint
							su.wordOrder = &wo
						}
						su.worldSlip = 0.10
					})
					d30 += res[30]
					d90 += res[90]
					b, k := falseKnown(u)
					bad += b
					known += k
					fu += falseUnknown(u)
				}
				avg90 := d90 / trials
				t.Logf("%-18s %6d %6d %+8d %6.1f/%-5.1f %8.1f", r.name,
					d30/trials, avg90, avg90-c.truth,
					float64(bad)/float64(trials), float64(known)/float64(trials),
					float64(fu)/float64(trials))
			}
		}
	}
}
