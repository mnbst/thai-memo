package uvm

import (
	"os"
	"testing"
)

// TestThresholdSweep は「1問正解で進みすぎる」への 3 案を比べる（SIM=1 で実行）。
//
//	A: knownMaxRank に数える P を 0.5 → 0.65（2 連続正解で既知）
//	B: BayesGuessTop 0.35 → 0.45
//	C: EstimateVocab の cutoff 0.42 → 0.45
//
// 誤既知は各案の既知の基準で数える。素通りは floor〜d90 の間で一度も
// key_word にならなかった rank 数。
//
//	SIM=1 go test ./internal/uvm -run TestThresholdSweep -v
func TestThresholdSweep(t *testing.T) {
	if os.Getenv("SIM") == "" {
		t.Skip("SIM=1 で実行する")
	}
	trials := 20
	variants := []struct {
		name   string
		knownP float64
		tune   func(*simUser)
	}{
		{"現行", 0.5, func(u *simUser) {}},
		{"A known.60", 0.6, func(u *simUser) { u.knownP = 0.6 }},
		{"A known.65", 0.65, func(u *simUser) { u.knownP = 0.65 }},
		{"B g.45", 0.5, func(u *simUser) { u.bayesGuess, u.bayesSlip = 0.45, BayesSlip }},
		{"C cut.45", 0.5, func(u *simUser) { u.cutoff = 0.45 }},
	}
	worlds := []struct {
		name        string
		guess, slip float64
	}{
		{"g_true=.25", 0.25, 0.10},
		{"g_true=.08", 0.08, 0.10},
		{"g_true=.50", 0.50, 0.10},
	}
	for _, w := range worlds {
		for _, tested := range []bool{false, true} {
			label := "未受験"
			if tested {
				label = "受験"
			}
			for _, truth := range []int{150, 350, 700} {
				t.Logf("=== %s slip=.10 / %s 真値%d ===", w.name, label, truth)
				t.Logf("%-12s %5s %5s %6s %12s %6s", "案", "d30", "d90", "誤差", "誤既知/既知", "素通り")
				for _, v := range variants {
					d30, d90, bad, known, skip := 0, 0, 0, 0, 0
					for s := range trials {
						r, u := runCellUser(s+1, truth, tested, true, 90, func(su *simUser) {
							su.worldGuess, su.worldSlip = w.guess, w.slip
							v.tune(su)
						})
						d30 += r[30]
						d90 += r[90]
						for rank, wd := range u.words {
							if wd.p > v.knownP {
								known++
								if pKnow(rank, u.truth) < 0.5 {
									bad++
								}
							}
						}
						for rank := u.floor + 1; rank <= r[90]; rank++ {
							if _, ok := u.words[rank]; !ok {
								skip++
							}
						}
					}
					n := float64(trials)
					t.Logf("%-12s %5d %5d %+6d %5.1f/%5.1f %6.1f", v.name,
						d30/trials, d90/trials, d90/trials-truth,
						float64(bad)/n, float64(known)/n, float64(skip)/n)
				}
			}
		}
	}
}
