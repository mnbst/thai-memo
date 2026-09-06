package uvm

import (
	"fmt"
	"math"
	"math/rand"
	"os"
	"testing"
)

// IRT（項目反応理論）で測った場合の精度を、いまの階段と同じ条件で比べる
// （SIM=1 で実行）。
//
//	SIM=1 go test ./internal/uvm -run TestSimIRT -v
//
// 本番コードは何も使わない。「情報を捨てない・SE で止める・適応出題」の 3 つが
// 実際に効くのかを見るための検証だけのファイル。

// --- 世界側 ------------------------------------------------------------

// simWorld は「真値 truth の人が rank の語を知っている確率」。
// 階段の sim（scoresim_test.go）は matrixsim_test.go の pKnow を使ってきたが、
// あれは線形ランク上のロジスティック（スケール 60）で、rank 2000 付近では
// ±120 語で 0→1 に切り替わる。実態より鋭すぎる疑いがあるので、log ランク上の
// 曲線も並べて回す。
type simWorld struct {
	name string
	pk   func(rank, truth int) float64
}

// worldPK は階段 sim が使う世界（差し替えて比べるための間接参照）。
var worldPK = pKnow

// logWorld は log ランク上のロジスティック。slope が大きいほど境界が鋭い。
// slope 3.0 で「真値の 1/2 倍のランクなら 9 割知っている／2 倍なら 1 割」。
func logWorld(slope float64) func(rank, truth int) float64 {
	return func(rank, truth int) float64 {
		if rank < 1 {
			rank = 1
		}
		return 1 / (1 + math.Exp(-slope*(math.Log(float64(truth))-math.Log(float64(rank)))))
	}
}

var simWorlds = []simWorld{
	{"線形60（従来の仮定）", pKnow},
	{"logランク slope3.0", logWorld(3.0)},
}

// --- 推定側 ------------------------------------------------------------

// irtCfg は 3PL の推定器。θ は log ランク上に置く。
//
//	P(正答|θ) = c + (1-c) / (1 + exp(-a(θ - b))),  b = log(rank)
//
// a・c は語ごとに較正する余地があるが、ここでは較正前（コールドスタート）の
// 想定で全語共通の 1 個に固定する。
type irtCfg struct {
	name     string
	a        float64 // 識別力（log ランク上の傾き）
	c        float64 // 当て推量。4 択なら 0.25
	minItems int
	maxItems int
	seTarget float64 // 事後分布の SD がこれを切ったら止める（log 尺度）
	adaptive bool    // false なら θ を見ずにランクを一様に散らす
}

const (
	irtGridN   = 240
	irtMinRank = 3.0
	irtMaxRank = 4000.0
)

// irtGrid は θ の格子（log ランク）。
var irtGrid = func() []float64 {
	g := make([]float64, irtGridN)
	lo, hi := math.Log(irtMinRank), math.Log(irtMaxRank)
	for i := range g {
		g[i] = lo + (hi-lo)*float64(i)/float64(irtGridN-1)
	}
	return g
}()

func (cfg irtCfg) p(theta, b float64) float64 {
	return cfg.c + (1-cfg.c)/(1+math.Exp(-cfg.a*(theta-b)))
}

// posterior は事後分布の平均と SD（log 尺度）。事前分布は格子上で一様
// （＝ [3, 4000] で打ち切った無情報事前）。
func (cfg irtCfg) posterior(post []float64) (mean, sd float64) {
	sum := 0.0
	for _, w := range post {
		sum += w
	}
	if sum <= 0 {
		return math.Log(1), 0
	}
	for i, w := range post {
		mean += irtGrid[i] * w / sum
	}
	for i, w := range post {
		d := irtGrid[i] - mean
		sd += d * d * w / sum
	}
	return mean, math.Sqrt(sd)
}

// take は 1 人ぶんの受験。返り値は測定値（ランク）と出題数。
func (cfg irtCfg) take(rnd *rand.Rand, w simWorld, truth int, guess, slip float64) (int, int) {
	post := make([]float64, irtGridN)
	for i := range post {
		post[i] = 1
	}
	used := map[int]bool{}
	asked := 0

	for asked < cfg.maxItems {
		mean, sd := cfg.posterior(post)
		if asked >= cfg.minItems && sd < cfg.seTarget {
			break
		}

		// 出題語のランクを決める。適応なら θ の近く（2PL の情報量が最大に
		// なるのは b≈θ）、そうでなければ全域に散らす。
		var rank int
		if cfg.adaptive {
			rank = int(math.Round(math.Exp(mean)))
		} else {
			rank = int(math.Round(math.Exp(irtGrid[rnd.Intn(irtGridN)])))
		}
		// 同じ語を 2 度出さない。近傍にずらす（帯の中の別の語に相当）。
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

		// 回答（階段 sim と同じ生成規則）。
		known := rnd.Float64() < w.pk(rank, truth)*(1-slip)
		ok := known || rnd.Float64() < guess

		// 事後分布の更新。
		b := math.Log(float64(rank))
		for i := range post {
			p := cfg.p(irtGrid[i], b)
			if ok {
				post[i] *= p
			} else {
				post[i] *= 1 - p
			}
		}
		// 桁溢れ防止に正規化。
		s := 0.0
		for _, v := range post {
			s += v
		}
		if s > 0 {
			for i := range post {
				post[i] /= s
			}
		}
	}

	mean, _ := cfg.posterior(post)
	return int(math.Round(math.Exp(mean))), asked
}

func (cfg irtCfg) eval(w simWorld, truth int, guess, slip float64, trials int) simStat {
	rnd := rand.New(rand.NewSource(int64(truth)*7919 + int64(guess*1000) + int64(slip*100)))
	sum, sumSq, asked := 0.0, 0.0, 0
	for range trials {
		got, n := cfg.take(rnd, w, truth, guess, slip)
		asked += n
		d := float64(got - truth)
		sum += d
		sumSq += d * d
	}
	n := float64(trials)
	mean := sum / n
	return simStat{
		bias:  mean,
		sd:    math.Sqrt(math.Max(0, sumSq/n-mean*mean)),
		items: float64(asked) / n,
	}
}

// --- 実行 --------------------------------------------------------------

func TestSimIRT(t *testing.T) {
	if os.Getenv("SIM") == "" {
		t.Skip("SIM=1 で実行する")
	}
	const trials = 2000
	truths := []int{80, 350, 1200, 2000}
	worlds := []struct{ guess, slip float64 }{
		{0.25, 0.00}, {0.55, 0.00}, {0.45, 0.10}, {0.55, 0.10},
	}

	ladder := simLadder{TestStages, TestItemsPerStage, TestPassThreshold, 4, false, TestChanceRate, false}
	irts := []irtCfg{
		{"IRT 適応 a=2.5 c=.25 30問", 2.5, 0.25, 12, 30, 0.12, true},
		{"IRT 適応 a=2.5 c=.35 30問", 2.5, 0.35, 12, 30, 0.12, true},
		{"IRT 適応 a=2.5 c=.45 30問", 2.5, 0.45, 12, 30, 0.12, true},
		{"IRT 適応 a=2.5 c=.45 20問", 2.5, 0.45, 10, 20, 0.12, true},
		{"IRT 適応 a=4.0 c=.45 30問", 4.0, 0.45, 12, 30, 0.12, true},
	}

	for _, sw := range simWorlds {
		fmt.Printf("\n########## 世界: %s ##########\n", sw.name)
		worldPK = sw.pk
		for _, wp := range worlds {
			fmt.Printf("\n=== 実効推測率 %.2f / slip %.2f ===\n", wp.guess, wp.slip)
			fmt.Printf("%-30s", "真値 →")
			for _, tr := range truths {
				fmt.Printf("%18d", tr)
			}
			fmt.Println("   （誤差±SD / 出題数）")

			fmt.Printf("%-30s", "いまの階段 11段6問5通過")
			for _, tr := range truths {
				s := ladder.eval(tr, wp.guess, wp.slip, trials)
				fmt.Printf("%+7.0f±%-5.0f/%3.0f問", s.bias, s.sd, s.items)
			}
			fmt.Println()

			for _, cfg := range irts {
				fmt.Printf("%-30s", cfg.name)
				for _, tr := range truths {
					s := cfg.eval(sw, tr, wp.guess, wp.slip, trials)
					fmt.Printf("%+7.0f±%-5.0f/%3.0f問", s.bias, s.sd, s.items)
				}
				fmt.Println()
			}
		}
	}
	worldPK = pKnow
}
