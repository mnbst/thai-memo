package uvm

import (
	"fmt"
	"math"
	"math/rand"
	"os"
	"sort"
	"testing"
)

// 階段と IRT のハイブリッド（SIM=1 で実行）。
//
//	SIM=1 go test ./internal/uvm -run TestSimHybrid -v
//
// 狙い: 初級者の速さ（階段の打ち切り）と上級者の精度（IRT）の両取り。
//
//   - 最初の gate 段だけ階段で回す。落ちたらそこで採点して終了
//     （＝初級者は 6〜12 問で終わる。いまと同じ）
//   - gate 段を通過した人だけ IRT に切り替える
//
// 階段で出した問題も rank と正誤が分かっているので、そのまま IRT の尤度に
// 入れる（情報を捨てない）。IRT 側の事前分布は「gate 段を通過した」ことを
// 反映して、通過した段の上端より下を落とす。
type hybridCfg struct {
	name   string
	gate   int // 階段で回す段数
	ladder simLadder
	irt    irtCfg
}

// take は 1 人ぶんの受験。返り値は測定値と出題数。
func (h hybridCfg) take(rnd *rand.Rand, w simWorld, truth int, guess, slip float64) (int, int) {
	asked := 0
	var history []StageResult

	// 事後分布。階段の回答もここへ入れていく。
	post := make([]float64, irtGridN)
	for i := range post {
		post[i] = 1
	}
	used := map[int]bool{}

	obs := func(rank int, ok bool) {
		b := math.Log(float64(rank))
		s := 0.0
		for i := range post {
			p := h.irt.p(irtGrid[i], b)
			if ok {
				post[i] *= p
			} else {
				post[i] *= 1 - p
			}
			s += post[i]
		}
		if s > 0 {
			for i := range post {
				post[i] /= s
			}
		}
	}

	// --- 階段パート ---
	for stage := 0; stage < h.gate && stage < len(h.ladder.stages); stage++ {
		st := h.ladder.stages[stage]
		correct := 0
		for range h.ladder.items {
			rank := st.Low + rnd.Intn(st.High-st.Low+1)
			for used[rank] {
				rank = st.Low + rnd.Intn(st.High-st.Low+1)
			}
			used[rank] = true
			asked++
			ok := rnd.Float64() < w.pk(rank, truth)*(1-slip) ||
				rnd.Float64() < h.ladder.guessAt(guess)
			if ok {
				correct++
			}
			obs(rank, ok)
		}
		history = append(history, StageResult{stage, correct})
		if !h.ladder.passed(correct) {
			// 落ちた。階段の採点式で締めて終了（初級者の速い出口）。
			return h.ladder.score(history), asked
		}
	}

	// --- IRT パート ---
	// 通過した段の上端より下は落とす（通過した以上そこには居ない）。
	floor := math.Log(float64(h.ladder.stages[h.gate-1].High))
	for i := range post {
		if irtGrid[i] < floor {
			post[i] = 0
		}
	}

	for asked < h.irt.maxItems {
		mean, sd := h.irt.posterior(post)
		if asked >= h.irt.minItems && sd < h.irt.seTarget {
			break
		}
		rank := int(math.Round(math.Exp(mean)))
		for span := 0; ; span++ {
			r := rank + rnd.Intn(2*span+1) - span
			if r >= 1 && r <= int(irtMaxRank) && !used[r] {
				rank = r
				break
			}
			if span > 200 {
				break
			}
		}
		used[rank] = true
		asked++
		ok := rnd.Float64() < w.pk(rank, truth)*(1-slip) || rnd.Float64() < guess
		obs(rank, ok)
	}

	mean, _ := h.irt.posterior(post)
	return int(math.Round(math.Exp(mean))), asked
}

func TestSimHybrid(t *testing.T) {
	if os.Getenv("SIM") == "" {
		t.Skip("SIM=1 で実行する")
	}
	const trials = 2000
	worlds := allDownWorlds()
	names := []string{"線形60", "logランク"}

	ladder := simLadder{TestStages, TestItemsPerStage, TestPassThreshold, 4, false, TestChanceRate, false}
	irtOf := func(c float64, maxItems int) irtCfg {
		return irtCfg{"", 2.5, c, 12, maxItems, 0.12, true}
	}

	type cand struct {
		name string
		take func(*rand.Rand, simWorld, int, float64, float64) (int, int)
	}
	mkH := func(name string, gate int, c float64, maxItems int) cand {
		h := hybridCfg{name, gate, ladder, irtOf(c, maxItems)}
		return cand{name, h.take}
	}
	cands := []cand{
		{"階段 現行", func(rnd *rand.Rand, w simWorld, tr int, g, s float64) (int, int) {
			prev := worldPK
			worldPK = w.pk
			simAsked = 0
			v, _ := ladder.take(rnd, tr, g, s)
			worldPK = prev
			return v, simAsked
		}},
		mkH("gate3 c=.55 30問", 3, 0.55, 30),
		mkH("gate3 c=.65 24問", 3, 0.65, 24),
		mkH("gate3 c=.65 30問", 3, 0.65, 30),
		mkH("gate3 c=.65 36問", 3, 0.65, 36),
		mkH("gate3 c=.75 30問", 3, 0.75, 30),
		mkH("gate4 c=.65 30問", 4, 0.65, 30),
	}

	// --- 長さ ---
	fmt.Printf("\n########## 出題数（平均/p90） ##########\n")
	lenTruths := []int{5, 50, 80, 150, 350, 1200, 2000}
	fmt.Printf("%-28s", "真値 →")
	for _, tr := range lenTruths {
		fmt.Printf("%10d", tr)
	}
	fmt.Println("   （正直な受験者）")
	for _, c := range cands {
		fmt.Printf("%-28s", c.name)
		for _, tr := range lenTruths {
			w := worlds[0]
			rnd := rand.New(rand.NewSource(int64(tr) * 7919))
			counts := make([]float64, 0, trials)
			sum := 0.0
			for range trials {
				_, n := c.take(rnd, simWorld{"", w.pk}, tr, w.guess, w.slip)
				counts = append(counts, float64(n))
				sum += float64(n)
			}
			sort.Float64s(counts)
			fmt.Printf("%6.0f/%-3.0f", sum/float64(trials), pct(counts, 0.90))
		}
		fmt.Println()
	}

	// --- 精度 ---
	for _, tr := range []int{350, 1200, 2000} {
		fmt.Printf("\n########## 真値 %d ##########\n", tr)
		fmt.Printf("%-28s %10s %10s %10s\n", "", "上振れp90", "中央値最悪", "正直p50")
		for _, c := range cands {
			worstHi, worstMed, honest := math.Inf(-1), math.Inf(1), 0.0
			for i, w := range worlds {
				rnd := rand.New(rand.NewSource(int64(tr)*7919 + int64(w.guess*1000) + int64(w.slip*100)))
				errs := make([]float64, 0, trials)
				for range trials {
					v, _ := c.take(rnd, simWorld{names[i/5], w.pk}, tr, w.guess, w.slip)
					errs = append(errs, float64(v-tr))
				}
				sort.Float64s(errs)
				worstHi = math.Max(worstHi, pct(errs, 0.90))
				worstMed = math.Min(worstMed, pct(errs, 0.50))
				if i == 0 {
					honest = pct(errs, 0.50)
				}
			}
			fmt.Printf("%-28s %+10.0f %+10.0f %+10.0f\n", c.name, worstHi, worstMed, honest)
		}
	}
}
