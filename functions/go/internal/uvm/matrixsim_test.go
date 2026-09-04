package uvm

import (
	"fmt"
	"math"
	"math/rand"
	"testing"
)

const simMaxRank = 3000

func pKnow(rank, trueVocab int) float64 {
	return 1.0 / (1.0 + math.Exp(float64(rank-trueVocab)/60.0))
}

type simWord struct {
	p        float64
	attempts int
	graded   bool // 等倍で採点されたクイズ（まとめクイズ）に1回でも答えたか
}

type simUser struct {
	rnd    *rand.Rand
	truth  int
	words  map[int]*simWord // rank -> doc
	est    int
	floor  int // vocab_test_vocab
	sel    *SessionSelector
	seen   []int // 出題済み key_word（まとめクイズの母集団）
	srsIdx int

	// --- 実験用のつまみ（0/false は現行実装どおり） ---
	aheadOverride  int  // >0 なら前方幅をこの値に固定する
	answeredOnly   bool // 推定の母数を回答済み（quiz_attempts>0）の語だけにする
	legacyUngraded bool // graded 導入前の挙動（採点区分を見ずに全部を母数に入れる）
	drops          int  // 例文生成で est が下がった回数
	dropSum        int  // その合計幅
}

func (u *simUser) answers(rank int) bool {
	return u.rnd.Float64() < pKnow(rank, u.truth) || u.rnd.Float64() < 0.25
}

// sync は SyncEstimatedVocab の計算部分を再現する（premium・上限なし）。
func (u *simUser) sync() {
	low := max(u.floor, u.est-50)
	high := u.est + 51
	var entries []RankedP
	for r, w := range u.words {
		if r >= low && r < high {
			if u.answeredOnly && w.attempts == 0 {
				continue
			}
			// 実装は等倍採点の語だけを母数にする（IsGradedResult）。
			if !u.legacyUngraded && !w.graded {
				continue
			}
			entries = append(entries, RankedP{Rank: r, P: w.p})
		}
	}
	u.est = max(0, EstimateVocab(entries, u.est, u.floor))
}

// generate は例文生成 1 回（key_word 選定 → 露出登録 → 確認クイズ → sync）。
func (u *simUser) generate(learningQuiz bool) {
	tested := u.floor
	lo, hi := ScanBand(max(u.est-tested, 0))
	if u.aheadOverride > 0 {
		hi = max(u.est-tested, 0) + u.aheadOverride
	}
	lo, hi = lo+tested, hi+tested
	var cands []Candidate
	for r := lo; r <= min(hi, simMaxRank); r++ {
		cands = append(cands, Candidate{Word: fmt.Sprintf("w%d", r), Rank: r})
	}
	if len(cands) == 0 {
		return
	}
	var zero []Candidate
	for _, c := range cands {
		if _, ok := u.words[c.Rank]; !ok {
			zero = append(zero, c)
		}
	}
	var picked []Candidate
	if len(zero) > 0 {
		picked = u.sel.SelectWeighted(zero, ZeroPWeights(zero), 1)
	} else {
		pMap := map[string]float64{}
		for _, c := range cands {
			pMap[c.Word] = u.words[c.Rank].p
		}
		picked = u.sel.selectUnknown(cands, pMap, 1)
	}
	if len(picked) == 0 {
		return
	}
	rank := picked[0].Rank
	if _, ok := u.words[rank]; !ok {
		u.words[rank] = &simWord{p: NewWordP}
		u.seen = append(u.seen, rank)
	}
	if learningQuiz {
		u.answer(rank, true)
	}
	before := u.est
	u.sync()
	if u.est < before {
		u.drops++
		u.dropSum += before - u.est
	}
}

// answer は 1 問ぶんの P 更新。learning は正解時 α ×0.1。
func (u *simUser) answer(rank int, learning bool) {
	w := u.words[rank]
	correct := u.answers(rank)
	mult := 1.0
	if learning && correct {
		mult *= LearningCorrectMultiplier
	}
	r := rank
	w.p = UpdateP(w.p, correct, w.attempts, &r, mult)
	w.attempts++
	if !learning {
		w.graded = true
	}
}

// summaryQuiz はまとめクイズ n 問（SRS ＝ 出題済みを古い順に巡回）。
func (u *simUser) summaryQuiz(n int) {
	var pool []int
	for _, r := range u.seen {
		if u.floor > 0 && r < u.floor { // premium × 受験者のフィルタ
			continue
		}
		pool = append(pool, r)
	}
	if len(pool) == 0 {
		return
	}
	for range n {
		u.answer(pool[u.srsIdx%len(pool)], false)
		u.srsIdx++
	}
	u.sync()
}

// takeVocabTest は語彙テストを 1 回受ける（4択・推測25%）。
func takeVocabTest(rnd *rand.Rand, truth int) int {
	var history []StageResult
	stage := 0
	for {
		st := TestStages[stage]
		correct := 0
		for range TestItemsPerStage {
			rank := st.Low + rnd.Intn(st.High-st.Low+1)
			if rnd.Float64() < pKnow(rank, truth) || rnd.Float64() < 0.25 {
				correct++
			}
		}
		history = append(history, StageResult{Stage: stage, Correct: correct})
		next, done := NextStage(history)
		if done {
			break
		}
		stage = next
	}
	return ScoreVocab(history)
}

func runCell(seed, truth int, tested, summary bool) map[int]int {
	return runCellUntil(seed, truth, tested, summary, 90)
}

func runCellUntil(seed, truth int, tested, summary bool, stopDay int) map[int]int {
	rnd := rand.New(rand.NewSource(int64(seed)))
	u := &simUser{rnd: rnd, truth: truth, words: map[int]*simWord{},
		sel: &SessionSelector{Rand: rnd}}
	if tested {
		u.floor = takeVocabTest(rnd, truth)
		u.est = u.floor
	}
	out := map[int]int{0: u.est}
	for day := 1; day <= 90; day++ {
		for range 5 { // 1日5例文（確認クイズつき）
			u.generate(true)
		}
		if summary && day <= stopDay {
			u.summaryQuiz(5)
		}
		u.sync() // 毎日配信ぶん
		switch day {
		case 1, 7, 30, 90:
			out[day] = u.est
		}
	}
	return out
}

// 途中でまとめクイズをやめた場合。
func TestVocabStopMidway(t *testing.T) {
	trials := 20
	for _, truth := range []int{150, 350, 700} {
		for _, tested := range []bool{true, false} {
			sum := map[int]int{}
			for s := range trials {
				r := runCellUntil(s+1, truth, tested, true, 30)
				for _, d := range []int{30, 90} {
					sum[d] += r[d]
				}
			}
			label := "受験"
			if !tested {
				label = "未受験"
			}
			t.Logf("真値%d %s: d30(停止時)=%d d90=%d", truth, label, sum[30]/trials, sum[90]/trials)
		}
	}
}

func TestVocabMatrix(t *testing.T) {
	trials := 20
	days := []int{0, 1, 7, 30, 90}
	for _, truth := range []int{150, 350, 700} {
		t.Logf("=== 真値 %d ===", truth)
		t.Logf("%-26s %6s %6s %6s %6s %6s", "ケース", "測定", "d1", "d7", "d30", "d90")
		for _, c := range []struct {
			name            string
			tested, summary bool
		}{
			{"受験 + まとめクイズ", true, true},
			{"受験 + 放置", true, false},
			{"未受験 + まとめクイズ", false, true},
			{"未受験 + 放置", false, false},
		} {
			sum := map[int]int{}
			for s := range trials {
				r := runCell(s+1, truth, c.tested, c.summary)
				for _, d := range days {
					sum[d] += r[d]
				}
			}
			t.Logf("%-24s %6d %6d %6d %6d %6d", c.name,
				sum[0]/trials, sum[1]/trials, sum[7]/trials, sum[30]/trials, sum[90]/trials)
		}
	}
}
