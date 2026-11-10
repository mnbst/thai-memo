package uvm

import (
	"fmt"
	"os"
	"sync"
	"testing"
)

// TestAccuracyCutoff は、まとめクイズの正答率でスコアの基準（VocabCutoffP）を
// 変える案を比べる。値は d30 / d90 の誤差（スコア−実力）。
//
// 結論（2026-11、60試行。本番は SummaryCutoff）:
//
//   - 2段（80%以上 0.42）より4段（90% 0.41 / 80% 0.42 / 60% 0.45 / 未満 0.49）が
//     よい。上級・伸びる未受験の d90 が −283 → −70、詰まる人の上振れも −7〜−16。
//     90% を 0.40 にすると中級・上級が +50 前後に上振れする。
//
//   - 見る範囲は直近20問を1回目から。10問たまるまで待つ案とほぼ同じで、
//     最後の1回（5問）だけだと詰まる人の上振れが増える（入門 +76 → +96）。
//
//     ACC_CUTOFF_SIM=1 go test ./internal/uvm -run TestAccuracyCutoff -v
func TestAccuracyCutoff(t *testing.T) {
	if os.Getenv("ACC_CUTOFF_SIM") == "" {
		t.Skip("ACC_CUTOFF_SIM=1 で実行")
	}
	flat := func(c float64) func(float64, int) float64 {
		return func(float64, int) float64 { return c }
	}
	step := func(minAcc, c float64) func(float64, int) float64 {
		return func(acc float64, n int) float64 {
			if n >= 10 && acc >= minAcc {
				return c
			}
			return 0
		}
	}
	// 正答率 lo で 0.45、hi 以上で c まで直線で下げる。
	ramp := func(lo, hi, c float64) func(float64, int) float64 {
		return func(acc float64, n int) float64 {
			if n < 10 || acc <= lo {
				return 0
			}
			k := min(1, (acc-lo)/(hi-lo))
			return VocabCutoffP - k*(VocabCutoffP-c)
		}
	}
	// tiers は正答率の下限と閾値の組（高い順）。どれにも当たらなければ base。
	tiers := func(base float64, ts ...[2]float64) func(float64, int) float64 {
		return func(acc float64, n int) float64 {
			if n < 10 {
				return 0
			}
			for _, t := range ts {
				if acc >= t[0] {
					return t[1]
				}
			}
			return base
		}
	}
	_ = ramp
	_, _ = flat, step
	t4 := func(minN int) func(float64, int) float64 {
		return func(acc float64, n int) float64 {
			if n < minN {
				return 0
			}
			return tiers(0, [2]float64{0.90, 0.41}, [2]float64{0.80, 0.42}, [2]float64{0.60, 0.45}, [2]float64{0, 0.49})(acc, 10)
		}
	}
	cfgs := []adaptCfg{
		{name: "現行.45"},
		{name: "20問(10問から)", cutFn: t4(10)},
		{name: "20問(1回目から)", cutFn: t4(1)},
		{name: "10問(1回目から)", cutFn: t4(1), cutWindow: 10},
		{name: "最後の1回", cutFn: t4(1), cutWindow: -1},
	}
	const trials = 60.0
	worlds := []struct {
		name        string
		guess, slip float64
	}{{"推測.25 slip0", 0.25, 0}, {"推測.45 slip.10", 0.45, 0.10}}
	for _, w := range worlds {
		t.Logf("##### 世界 %s（d30誤差/d90誤差、末尾は現行の正答率%%）", w.name)
		head := ""
		for _, c := range cfgs {
			head += " " + c.name
		}
		t.Logf("案:%s", head)
		for _, base := range adaptPersonas {
			p := base
			p.guess, p.slip = w.guess, w.slip
			type cell struct{ e30, e90, acc float64 }
			cells := make([]cell, len(cfgs))
			var wg sync.WaitGroup
			for i, cfg := range cfgs {
				cfg.sparse = true
				wg.Add(1)
				go func() {
					defer wg.Done()
					for s := range int(trials) {
						r30 := runAdaptive(s+1, p, cfg, 30)
						r90 := runAdaptive(s+1, p, cfg, 90)
						cells[i].e30 += (r30.est - r30.truth) / trials
						cells[i].e90 += (r90.est - r90.truth) / trials
						cells[i].acc += r90.acc / trials
					}
				}()
			}
			wg.Wait()
			row := ""
			for _, c := range cells {
				row += sprintfCell(c.e30, c.e90)
			}
			t.Logf("%-22s%s  acc=%.0f", p.name, row, cells[0].acc)
		}
	}
}

func sprintfCell(a, b float64) string { return fmt.Sprintf(" %+5.0f/%+5.0f", a, b) }
