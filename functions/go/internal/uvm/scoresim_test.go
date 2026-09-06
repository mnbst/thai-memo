package uvm

import (
	"fmt"
	"math"
	"math/rand"
	"os"
	"testing"
)

// 語彙テストの測定精度シミュレーション（SIM=1 で実行）。
//
//	SIM=1 go test ./internal/uvm -run TestSimVocabTestAccuracy -v
//
// 段の階段・1段あたりの問題数・通過本数・世界側の実効推測率を差し替えて、
// 真値に対する測定誤差と、実力どおり上の段まで届く確率を比べる。
// TestStages / TestItemsPerStage / TestPassThreshold を触る前にこれを回すこと。
//
// 世界側の推測率を TestChanceRate（0.25）より高く置けるのが要点。誤答の選択肢を
// 同じ段の語の訳から作る以上、消去法と部分再認で実効は 0.25 を上回る。採点式は
// 0.25 を前提に補正するので、そのずれが上振れになる。

// simLadder は測定の階段。本番の定数を差し替えて比べるためのもの。
// simAsked は直近の take で出した問題数（測定の長さを見るための素朴なカウンタ）。
var simAsked int

type simLadder struct {
	stages []TestStage
	items  int
	pass   int
	// choices は 1 問の選択肢数。0 なら 4。採点の推測補正には 1/choices を使う。
	choices int
	// confirm が真なら、最後に通過した段をもう 1 度だけ別の語で出し直す
	// （まぐれ通過の取り消し）。落ちたらその段の結果で採点し直す。
	confirm bool
	// scoreChance は落ちた段を内挿するときに差し引く推測率。0 なら 1/choices。
	// ゲート（通過本数）とは独立に動かせる。
	scoreChance float64
	// bisect が真なら、落ちた段をもう 1 度その下半分だけで出し直して
	// 内挿の幅を半分にする（追試 1 回ぶん）。
	bisect bool
}

// interp は帯 [lo,hi] を正答数 correct で内挿した値。
func (l simLadder) interp(lo, hi, correct int) int {
	chance := l.scoreChanceRate()
	rate := float64(correct) / float64(l.items)
	c := math.Max(0, math.Min(1, (rate-chance)/(1-chance)))
	return lo - 1 + int(math.Round(c*float64(hi-lo+1)))
}

// scoreChanceRate は内挿で差し引く推測率。
func (l simLadder) scoreChanceRate() float64 {
	if l.scoreChance > 0 {
		return l.scoreChance
	}
	return l.chanceRate()
}

func (l simLadder) chanceRate() float64 {
	k := l.choices
	if k == 0 {
		k = 4
	}
	return 1 / float64(k)
}

// guessAt は「4 択でこの実効推測率だった人」が k 択で当てる確率。
//
// 実効推測率 g は「消去法で残った選択肢数 n = 1/g」と読める（4 択の 0.55 なら
// 1.8 個まで絞れている）。同じ消去力なら、選択肢を増やしても捨てられる数は
// 変わらないとみて、残る数を (k-4) だけ増やす。
func (l simLadder) guessAt(g4 float64) float64 {
	k := l.choices
	if k == 0 {
		k = 4
	}
	n := 1/g4 + float64(k-4)
	return math.Max(l.chanceRate(), math.Min(1, 1/n))
}

func (l simLadder) passed(correct int) bool { return correct >= l.pass }

// score は ScoreVocab と同じ式（推測補正した内挿、通過済み上限を下回らせない）。
// 推測補正は選択肢数から決める（chanceRate）。ScoreBias は本番の値。
func (l simLadder) score(history []StageResult) int {
	passedHigh := 0
	failed := -1
	for _, r := range history {
		if l.passed(r.Correct) {
			if l.stages[r.Stage].High > passedHigh {
				passedHigh = l.stages[r.Stage].High
			}
			continue
		}
		if failed < 0 || r.Stage < failed {
			failed = r.Stage
		}
	}
	if failed < 0 {
		return applyScoreBias(passedHigh)
	}
	band := l.stages[failed]
	rate := 0.0
	for _, r := range history {
		if r.Stage == failed {
			rate = float64(r.Correct) / float64(l.items)
			break
		}
	}
	chance := l.scoreChanceRate()
	c := math.Max(0, math.Min(1, (rate-chance)/(1-chance)))
	width := band.High - band.Low + 1
	vocab := band.Low - 1 + int(math.Round(c*float64(width)))
	return applyScoreBias(max(vocab, passedHigh))
}

// take は 1 人ぶんの受験。guess は世界側の実効推測率、slip は「知っている語を
// うっかり落とす」確率。返り値は測定値と、到達した最上段（添字）。
func (l simLadder) take(rnd *rand.Rand, truth int, guess, slip float64) (int, int) {
	var history []StageResult
	stage := 0
	for {
		history = append(history, StageResult{stage, l.askStage(rnd, stage, truth, guess, slip)})
		if !l.passed(history[len(history)-1].Correct) || stage+1 >= len(l.stages) {
			break
		}
		stage++
	}

	// 確認段: 最後に通過した段をもう 1 度出す。落ちたら、その段で落ちたことに
	// して採点し直す（まぐれで 1 段抜けたぶんを取り消す）。
	if l.confirm {
		last := history[len(history)-1]
		top := last.Stage
		if !l.passed(last.Correct) {
			top--
		}
		if top >= 0 {
			c := l.askStage(rnd, top, truth, guess, slip)
			if !l.passed(c) {
				trimmed := make([]StageResult, 0, top+1)
				for _, r := range history {
					if r.Stage < top {
						trimmed = append(trimmed, r)
					}
				}
				history = append(trimmed, StageResult{top, c})
			}
		}
	}

	// 二分追試: 落ちた帯の下半分でもう 1 段出し、内挿の幅を半分にする。
	last := history[len(history)-1]
	if l.bisect && !l.passed(last.Correct) {
		band := l.stages[last.Stage]
		mid := (band.Low + band.High) / 2
		passedHigh := 0
		if last.Stage > 0 {
			passedHigh = l.stages[last.Stage-1].High
		}
		lower := TestStage{band.Low, mid}
		c := l.askLoHi(rnd, lower, truth, guess, slip)
		var vocab int
		if l.passed(c) {
			vocab = l.interp(mid+1, band.High, last.Correct)
		} else {
			vocab = l.interp(band.Low, mid, c)
		}
		return applyScoreBias(max(vocab, passedHigh)), last.Stage
	}

	return l.score(history), history[len(history)-1].Stage
}

// askStage は 1 段ぶん出題して正答数を返す。
func (l simLadder) askStage(rnd *rand.Rand, stage, truth int, guess, slip float64) int {
	return l.askLoHi(rnd, l.stages[stage], truth, guess, slip)
}

// askLoHi は任意の帯から 1 段ぶん出題して正答数を返す。
func (l simLadder) askLoHi(rnd *rand.Rand, st TestStage, truth int, guess, slip float64) int {
	simAsked += l.items
	correct := 0
	for range l.items {
		rank := st.Low + rnd.Intn(st.High-st.Low+1)
		if rnd.Float64() < worldPK(rank, truth)*(1-slip) || rnd.Float64() < l.guessAt(guess) {
			correct++
		}
	}
	return correct
}

type simStat struct {
	bias  float64 // 平均測定値 - 真値
	sd    float64
	reach float64 // 真値を含む段（またはその上）まで届いた割合
	items float64 // 平均出題数
}

func (l simLadder) eval(truth int, guess, slip float64, trials int) simStat {
	// 真値が属する段。ここへ届かずに終わると「実力より下で止まった」。
	want := len(l.stages) - 1
	for i, st := range l.stages {
		if truth <= st.High {
			want = i
			break
		}
	}
	rnd := rand.New(rand.NewSource(int64(truth)*7919 + int64(guess*1000) + int64(slip*100)))
	sum, sumSq, reached, asked := 0.0, 0.0, 0, 0
	for range trials {
		simAsked = 0
		got, top := l.take(rnd, truth, guess, slip)
		asked += simAsked
		d := float64(got - truth)
		sum += d
		sumSq += d * d
		if top >= want {
			reached++
		}
	}
	n := float64(trials)
	mean := sum / n
	return simStat{
		bias:  mean,
		sd:    math.Sqrt(math.Max(0, sumSq/n-mean*mean)),
		reach: float64(reached) / n,
		items: float64(asked) / n,
	}
}

var simStagesNow = []TestStage{
	{1, 50}, {51, 150}, {151, 300}, {301, 450}, {451, 600}, {601, 900},
}

// simStagesNow は 900 で止めていた頃の 6 段。
// simStagesWide は 3000 まで伸ばす際に最初に置いた粗い 3 段（500/700/900 幅）。
// 本番の階段は TestStages を直接使う。
var simStagesWide = []TestStage{
	{1, 50}, {51, 150}, {151, 300}, {301, 450}, {451, 600}, {601, 900},
	{901, 1400}, {1401, 2100}, {2101, 3000},
}

func TestSimVocabTestAccuracy(t *testing.T) {
	if os.Getenv("SIM") == "" {
		t.Skip("SIM=1 で実行する")
	}
	const trials = 4000
	truths := []int{20, 80, 150, 350, 700, 1200, 2000}

	// guess: 世界側の実効推測率（採点式の前提は TestChanceRate=0.25）。
	// slip:  知っている語をうっかり落とす確率。
	worlds := []struct {
		guess, slip float64
	}{
		{0.25, 0.00}, {0.45, 0.00}, {0.55, 0.00},
		{0.45, 0.10}, {0.55, 0.10},
	}

	configs := []struct {
		name   string
		ladder simLadder
	}{
		// 本番（TestStages / TestItemsPerStage / TestPassThreshold / TestChanceRate）
		{"本番 11段 6問5通過 内挿0.35", simLadder{TestStages, TestItemsPerStage, TestPassThreshold, 4, false, TestChanceRate, false}},
		// 比べる相手
		{"旧 6段900 4問4通過 内挿0.25", simLadder{simStagesNow, 4, 4, 4, false, 0.25, false}},
		{"粗い9段 6問5通過 内挿0.25", simLadder{simStagesWide, 6, 5, 4, false, 0.25, false}},
		{"粗い9段 6問5通過 内挿0.35", simLadder{simStagesWide, 6, 5, 4, false, 0.35, false}},
		{"本番+二分追試", simLadder{TestStages, TestItemsPerStage, TestPassThreshold, 4, false, TestChanceRate, true}},
		{"本番+確認段", simLadder{TestStages, TestItemsPerStage, TestPassThreshold, 4, true, TestChanceRate, false}},
	}

	for _, w := range worlds {
		fmt.Printf("\n=== 実効推測率 %.2f / slip %.2f ===\n", w.guess, w.slip)
		fmt.Printf("%-26s", "真値 →")
		for _, tr := range truths {
			fmt.Printf("%16d", tr)
		}
		fmt.Println("   （誤差±SD / 到達率）")
		for _, c := range configs {
			fmt.Printf("%-26s", c.name)
			for _, tr := range truths {
				s := c.ladder.eval(tr, w.guess, w.slip, trials)
				fmt.Printf("%+6.0f±%-4.0f/%3.0f%%/%3.0f問", s.bias, s.sd, s.reach*100, s.items)
			}
			fmt.Println()
		}
	}
}
