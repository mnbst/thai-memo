package uvm

import (
	"fmt"
	"math"
	"math/rand"
	"os"
	"sort"
	"testing"
)

// 「下振れは許す」前提での掃き出し（SIM=1 で実行）。
//
//	SIM=1 go test ./internal/uvm -run TestSimDownward -v
//
// estimated_vocab は測定値をそのまま書く唯一の経路で、上振れると教材が難しく
// なり、その後のクイズでしか下げられない。下振れはクイズの正答で自然に戻る。
// つまり誤差は対称ではないので、|平均誤差| ではなく上振れの裾で選ぶ。
//
// 指標:
//
//	上振れ p90 … 誤差の 90 パーセンタイル。全世界（世界モデル 2 × 推測/slip 4）
//	              の最悪値を取る。「1 割の人がこれ以上ズレて上に出る」上限。
//	下振れ p10 … 同じく 10 パーセンタイルの最悪値。許容する側だが、青天井だと
//	              測る意味が無くなるので見る。
//	正直 p50  … 推測 0.25 / slip 0 の世界での中央値。まっとうな受験者の実感。

// downWorlds は掃き出しで回す世界の全組み合わせ。
type downWorld struct {
	pk          func(rank, truth int) float64
	guess, slip float64
}

func allDownWorlds() []downWorld {
	var out []downWorld
	for _, sw := range simWorlds {
		for _, p := range []struct{ guess, slip float64 }{
			{0.25, 0.00}, {0.45, 0.00}, {0.55, 0.00}, {0.45, 0.10}, {0.55, 0.10},
		} {
			out = append(out, downWorld{sw.pk, p.guess, p.slip})
		}
	}
	return out
}

func pct(errs []float64, q float64) float64 {
	if len(errs) == 0 {
		return 0
	}
	i := int(q * float64(len(errs)-1))
	return errs[i]
}

// downCfg は掃き出す 1 つの構成。ladder か irt のどちらかを持つ。
type downCfg struct {
	name   string
	ladder *simLadder
	irt    *irtCfg
	sub    int // 測定値から引く下駄（ScoreBias 相当）
}

// errs は 1 構成 1 世界ぶんの誤差列（昇順）と平均出題数。
func (d downCfg) errs(w downWorld, truth, trials int) ([]float64, float64) {
	rnd := rand.New(rand.NewSource(int64(truth)*7919 + int64(w.guess*1000) + int64(w.slip*100)))
	out := make([]float64, 0, trials)
	asked := 0
	prev := worldPK
	worldPK = w.pk
	defer func() { worldPK = prev }()
	for range trials {
		var got, n int
		if d.ladder != nil {
			simAsked = 0
			got, _ = d.ladder.take(rnd, truth, w.guess, w.slip)
			n = simAsked
		} else {
			got, n = d.irt.take(rnd, simWorld{"", w.pk}, truth, w.guess, w.slip)
		}
		asked += n
		out = append(out, float64(got-d.sub-truth))
	}
	sort.Float64s(out)
	return out, float64(asked) / float64(trials)
}

func TestSimDownward(t *testing.T) {
	if os.Getenv("SIM") == "" {
		t.Skip("SIM=1 で実行する")
	}
	const trials = 2000
	truths := []int{350, 1200, 2000}
	worlds := allDownWorlds()

	mk := func(chance float64) *simLadder {
		l := simLadder{TestStages, TestItemsPerStage, TestPassThreshold, 4, false, chance, false}
		return &l
	}
	strict := func(chance float64, confirm bool) *simLadder {
		l := simLadder{TestStages, TestItemsPerStage, TestItemsPerStage, 4, confirm, chance, false}
		return &l
	}
	conf := func(chance float64, pass int) *simLadder {
		l := simLadder{TestStages, TestItemsPerStage, pass, 4, true, chance, false}
		return &l
	}
	mkIRT := func(c float64, maxItems int) *irtCfg {
		g := irtCfg{"", 2.5, c, maxItems / 2, maxItems, 0.12, true}
		return &g
	}

	cfgs := []downCfg{
		{"階段 5通過 内挿0.35（現行）", mk(0.35), nil, 0},
		{"階段 5通過 内挿0.55", mk(0.55), nil, 0},
		{"階段 6通過（全問）内挿0.55", strict(0.55, false), nil, 0},
		{"階段 5通過+確認段 内挿0.55", conf(0.55, 5), nil, 0},
		{"階段 6通過+確認段 内挿0.55", conf(0.55, 6), nil, 0},
		{"階段 5通過+確認段 -150", conf(0.55, 5), nil, 150},
		{"IRT30 c=.55", nil, mkIRT(0.55, 30), 0},
		{"IRT30 c=.65", nil, mkIRT(0.65, 30), 0},
		{"IRT30 c=.75", nil, mkIRT(0.75, 30), 0},
		{"IRT20 c=.65", nil, mkIRT(0.65, 20), 0},
	}

	for _, tr := range truths {
		fmt.Printf("\n=== 真値 %d ===\n", tr)
		fmt.Printf("%-24s %10s %10s %10s %8s\n",
			"", "上振れp90", "下振れp10", "正直p50", "出題数")
		for _, c := range cfgs {
			worstHi, worstLo := math.Inf(-1), math.Inf(1)
			honest, items := 0.0, 0.0
			for i, w := range worlds {
				e, n := c.errs(w, tr, trials)
				worstHi = math.Max(worstHi, pct(e, 0.90))
				worstLo = math.Min(worstLo, pct(e, 0.10))
				if i == 0 { // 線形60 / 推測0.25 / slip 0
					honest = pct(e, 0.50)
					items = n
				}
			}
			fmt.Printf("%-24s %+10.0f %+10.0f %+10.0f %7.0f問\n",
				c.name, worstHi, worstLo, honest, items)
		}
	}

	// 最終候補の世界ごとの内訳。最悪値がどの世界で出ているのかを見る。
	fmt.Printf("\n\n########## 世界ごとの内訳（真値2000） ##########\n")
	names := []string{"線形60", "logランク"}
	finals := []downCfg{
		{"階段 5通過 内挿0.35（現行）", mk(0.35), nil, 0},
		{"階段 6通過 内挿0.55", strict(0.55, false), nil, 0},
		{"IRT30 c=.65", nil, mkIRT(0.65, 30), 0},
	}
	for _, c := range finals {
		fmt.Printf("\n%s\n", c.name)
		fmt.Printf("  %-24s %8s %8s %8s\n", "世界", "p10", "p50", "p90")
		for i, w := range worlds {
			e, _ := c.errs(w, 2000, trials)
			label := fmt.Sprintf("%s 推測%.2f slip%.2f", names[i/5], w.guess, w.slip)
			fmt.Printf("  %-24s %+8.0f %+8.0f %+8.0f\n",
				label, pct(e, 0.10), pct(e, 0.50), pct(e, 0.90))
		}
	}
}

// TestSimLength は受験の長さ（出題数）を真値ごとに見る。
//
//	SIM=1 go test ./internal/uvm -run TestSimLength -v
//
// オンボーディングの末尾に置いてあるので、初級者が短く終わることが要件。
// 階段は最初に落ちた段で止まるので自然に短いが、IRT は SE で止めるため
// 短く終わるとは限らない。
func TestSimLength(t *testing.T) {
	if os.Getenv("SIM") == "" {
		t.Skip("SIM=1 で実行する")
	}
	const trials = 2000
	truths := []int{5, 20, 50, 80, 150, 350, 700, 1200, 2000}
	worlds := allDownWorlds()

	l := simLadder{TestStages, TestItemsPerStage, TestPassThreshold, 4, false, TestChanceRate, false}
	irt := irtCfg{"", 2.5, 0.65, 12, 30, 0.12, true}
	irtShort := irtCfg{"", 2.5, 0.65, 6, 30, 0.25, true}
	irtLoose := irtCfg{"", 2.5, 0.65, 6, 30, 0.40, true}
	irtC25 := irtCfg{"", 2.5, 0.25, 6, 30, 0.25, true}

	run := func(name string, ws []downWorld, f func(*rand.Rand, downWorld, int) int) {
		fmt.Printf("%-18s", name)
		for _, tr := range truths {
			maxMean, maxP90 := 0.0, 0.0
			for _, w := range ws {
				rnd := rand.New(rand.NewSource(int64(tr)*7919 + int64(w.guess*1000)))
				prev := worldPK
				worldPK = w.pk
				counts := make([]float64, 0, trials)
				sum := 0.0
				for range trials {
					n := float64(f(rnd, w, tr))
					counts = append(counts, n)
					sum += n
				}
				worldPK = prev
				sort.Float64s(counts)
				maxMean = math.Max(maxMean, sum/float64(trials))
				maxP90 = math.Max(maxP90, pct(counts, 0.90))
			}
			fmt.Printf("%5.0f/%-4.0f", maxMean, maxP90)
		}
		fmt.Println()
	}

	fmt.Printf("\n%-18s", "真値 →")
	for _, tr := range truths {
		fmt.Printf("%10d", tr)
	}
	fmt.Println("   （平均/p90 出題数・全世界の最悪）")

	honest := worlds[:1] // 線形60 / 推測0.25 / slip 0

	fmt.Println("--- 正直な受験者（推測0.25・slip 0）---")
	for _, set := range []struct {
		label string
		ws    []downWorld
	}{{"正直", honest}, {"最悪", worlds}} {
		if set.label == "最悪" {
			fmt.Println("--- 全世界の最悪 ---")
		}
		ws := set.ws
		run("階段 現行", ws, func(rnd *rand.Rand, w downWorld, tr int) int {
			simAsked = 0
			l.take(rnd, tr, w.guess, w.slip)
			return simAsked
		})
		run("階段 旧4問4通過", ws, func(rnd *rand.Rand, w downWorld, tr int) int {
			old := simLadder{simStagesNow, 4, 4, 4, false, 0.25, false}
			simAsked = 0
			old.take(rnd, tr, w.guess, w.slip)
			return simAsked
		})
		run("IRT SE0.12", ws, func(rnd *rand.Rand, w downWorld, tr int) int {
			_, n := irt.take(rnd, simWorld{"", w.pk}, tr, w.guess, w.slip)
			return n
		})
		run("IRT SE0.25", ws, func(rnd *rand.Rand, w downWorld, tr int) int {
			_, n := irtShort.take(rnd, simWorld{"", w.pk}, tr, w.guess, w.slip)
			return n
		})
		run("IRT SE0.40", ws, func(rnd *rand.Rand, w downWorld, tr int) int {
			_, n := irtLoose.take(rnd, simWorld{"", w.pk}, tr, w.guess, w.slip)
			return n
		})
		run("IRT c=.25 SE0.25", ws, func(rnd *rand.Rand, w downWorld, tr int) int {
			_, n := irtC25.take(rnd, simWorld{"", w.pk}, tr, w.guess, w.slip)
			return n
		})
	}
}
