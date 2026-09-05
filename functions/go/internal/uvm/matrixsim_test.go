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
	evidence float64 // 累積証拠量（ResultEvidence の合計）
	graded   bool    // 等倍で採点されたクイズ（まとめクイズ）に1回でも答えたか
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
	aheadOverride  int     // >0 なら前方幅をこの値に固定する
	answeredOnly   bool    // 推定の母数を回答済み（quiz_attempts>0）の語だけにする
	legacyUngraded bool    // graded 導入前の挙動（採点区分を見ずに全部を母数に入れる）
	binaryGraded   bool    // evidence 導入前の挙動（graded の二値ゲート）
	evidenceK      float64 // >0 なら旧 ShrinkP を K=この値で掛ける
	summaryHint    int     // まとめクイズで常用するヒント段階

	// P 更新則の差し替え（どちらも 0 なら本番の UpdateP）。
	incorrectScale float64 // 不正解 α の上限に掛ける倍率
	bayesGuess     float64 // >0 でベイズ更新。ヒント無しの想定推測率 g
	bayesSlip      float64 // ベイズ更新のうっかり率 s
	alphaRule      bool    // 旧 α 則（UpdatePAlpha）で回す
	alphaUntilDay  int     // この日まで旧 α 則、翌日から新実装（移行の再現）
	totalDays      int     // 0 なら 90
	newP           float64 // >0 なら新語の初期 P をこの値にする（既定 NewWordP）

	// --- 世界側（ユーザーの実際の振る舞い）のつまみ ---
	worldSlip  float64 // 知っている語を落とす確率（誤タップ・読み違い）
	worldGuess float64 // >0 ならヒント無しの実際の推測率をこの値にする

	drops   int // 例文生成で est が下がった回数
	dropSum int // その合計幅
}

// answers は正誤を引く。guess は知らないときに当たる確率で、ヒントを出すほど
// 上がる（4択の素の当てずっぽうが 0.25、訳を表示すればほぼ当たる）。
func (u *simUser) answers(rank int, guess float64) bool {
	if u.worldGuess > 0 { // 素の 0.25 を worldGuess に置き換え、ヒントの比は保つ
		guess *= u.worldGuess / guessRate(0)
	}
	if u.rnd.Float64() < pKnow(rank, u.truth) {
		return u.rnd.Float64() >= u.worldSlip // 知っていてもうっかり落とす
	}
	return u.rnd.Float64() < guess
}

// guessRate はヒント段階ごとの「知らなくても当たる確率」。
func guessRate(hintLevel int) float64 {
	switch hintLevel {
	case 0:
		return 0.25
	case 1:
		return 0.45
	default:
		return 0.75
	}
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
			p := w.p
			switch {
			case u.legacyUngraded: // 生の P をそのまま母数に入れる
			case u.binaryGraded: // graded の二値ゲート
				if !w.graded {
					continue
				}
			default: // 実装は「一度でも答えた語」だけを母数にする
				if w.evidence <= 0 {
					continue
				}
				if u.evidenceK > 0 { // 旧 ShrinkP の比較用
					wt := math.Min(1, w.evidence/u.evidenceK)
					p = wt*p + (1-wt)*UnknownWordP
				}
			}
			entries = append(entries, RankedP{Rank: r, P: p})
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
		np := NewWordP
		if u.newP > 0 {
			np = u.newP
		}
		u.words[rank] = &simWord{p: np}
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
	quizType := ""
	hint := u.summaryHint // 確認クイズにヒントは無い
	if learning {
		quizType = "learning"
		hint = 0
	}
	res := Result{HintLevel: hint}

	correct := u.answers(rank, guessRate(hint))
	res.IsCorrect = correct

	mult := HintMultiplier(hint)
	if learning && correct {
		mult *= LearningCorrectMultiplier
	}
	w.p = u.updateP(w.p, correct, w.attempts, rank, hint, mult)
	w.attempts++
	w.evidence += ResultEvidence(quizType, res)
	if IsGradedResult(quizType, res) {
		w.graded = true
	}
}

// updateP は本番の UpdateP、またはつまみで差し替えた変種を呼ぶ。
// mult はヒント・学習クイズによる弱め係数（本番の UpdateP と同じ引数）。
func (u *simUser) updateP(p float64, correct bool, attempts, rank, hint int, mult float64) float64 {
	w := mult / HintMultiplier(hint) // 確認クイズの正解なら 0.1
	if u.alphaRule {
		if u.incorrectScale > 0 && !correct {
			return updatePIncorrect(p, attempts, rank, mult, u.incorrectScale)
		}
		r := rank
		return UpdatePAlpha(p, correct, attempts, &r, mult)
	}
	if u.bayesGuess > 0 { // g / s を振る比較用
		g := math.Min(MaxGuessRate, u.bayesGuess*guessRate(hint)/guessRate(0))
		return bayesUpdate(p, correct, g, u.bayesSlip, w)
	}
	return UpdateP(p, correct, hint, w) // 本番の実装
}

// updatePIncorrect は UpdateP の不正解側で alpha_max だけ scale 倍したもの。
func updatePIncorrect(p float64, attempts, rank int, mult, scale float64) float64 {
	s := RankScaleRef / (float64(rank) + RankScaleRef)
	alphaMax := (AlphaIncorrectMaxLow + (AlphaIncorrectMaxTop-AlphaIncorrectMaxLow)*s) * scale
	alpha := AlphaIncorrectMin + (alphaMax-AlphaIncorrectMin)*math.Exp(-AlphaDecayK*float64(attempts))
	return math.Max(PMin, math.Min(PMax, p-alpha*mult*p))
}

// bayesUpdate は 4 択の正誤を尤度比で反映する。
//
//	正解:   LR = (1-s)/g       不正解: LR = s/(1-g)
//	odds' = odds * LR^weight
//
// g は知らなくても当たる確率、s は知っていて落とす確率。weight は証拠の重み
// （確認クイズなど弱い経路で 1 未満）。rank も quiz_attempts も要らない
// （回数が増えれば odds が勝手に飽和する）。
func bayesUpdate(p float64, correct bool, g, s, weight float64) float64 {
	p = math.Max(1e-6, math.Min(1-1e-6, p))
	lr := s / (1 - g)
	if correct {
		lr = (1 - s) / g
	}
	odds := p / (1 - p) * math.Pow(lr, weight)
	return math.Max(PMin, math.Min(PMax, odds/(1+odds)))
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
	return runCellTuned(seed, truth, tested, summary, stopDay, nil)
}

// runCellTuned は tune で simUser のつまみを差し替えてから 90 日回す。
func runCellTuned(seed, truth int, tested, summary bool, stopDay int,
	tune func(*simUser)) map[int]int {
	out, _ := runCellUser(seed, truth, tested, summary, stopDay, tune)
	return out
}

// runCellUser は runCellTuned と同じだが、終了時のユーザーも返す
// （P の中身＝誤って既知にした語を数えるため）。
func runCellUser(seed, truth int, tested, summary bool, stopDay int,
	tune func(*simUser)) (map[int]int, *simUser) {
	rnd := rand.New(rand.NewSource(int64(seed)))
	u := &simUser{rnd: rnd, truth: truth, words: map[int]*simWord{},
		sel: &SessionSelector{Rand: rnd}}
	if tune != nil {
		tune(u)
	}
	if tested {
		u.floor = takeVocabTest(rnd, truth)
		u.est = u.floor
	}
	total := u.totalDays
	if total <= 0 {
		total = 90
	}
	out := map[int]int{0: u.est}
	for day := 1; day <= total; day++ {
		if u.alphaUntilDay > 0 {
			// 旧本番は α 則 + NewWordP=0.1 の組。切替日に両方まとめて変える。
			u.alphaRule = day <= u.alphaUntilDay
			u.newP = 0
			if u.alphaRule {
				u.newP = 0.1
			}
		}
		for range 5 { // 1日5例文（確認クイズつき）
			u.generate(true)
		}
		if summary && day <= stopDay {
			u.summaryQuiz(5)
		}
		u.sync() // 毎日配信ぶん
		switch day {
		case 1, 7, 30, 90, 91, 93, 97, 120, 180:
			out[day] = u.est
		}
	}
	return out, u
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

// EvidenceK と、ヒント常用ユーザーの見え方を比較する。
//
// 比較する母数の決め方:
//   - 実装(割引なし) : 一度でも答えた語の実測 P をそのまま使う。
//   - 二値graded : まとめクイズに1回答えたか否かで全か無か。
//   - K=… : 撤去した ShrinkP（証拠量で prior に寄せる）を K を振って再現。
//     UpdateP が尤度比になってからは二重の割引になり、ヒント常用ユーザーの
//     推定を下振れさせる（真値350・ヒント2段で K=1.0 が 129、割引なしが 167）。
//
// ヒント段は「まとめクイズで毎回そのヒントを使う」ユーザー。ヒントを出すほど
// 当てずっぽうが当たる（guessRate）ので、P が実力より上振れする側の圧力も入る。
func TestEvidenceKSweep(t *testing.T) {
	trials := 20
	modes := []struct {
		name string
		tune func(*simUser)
	}{
		{"実装(割引なし)", func(u *simUser) {}},
		{"二値graded", func(u *simUser) { u.binaryGraded = true }},
		{"K=1.0", func(u *simUser) { u.evidenceK = 1.0 }},
		{"K=1.5", func(u *simUser) { u.evidenceK = 1.5 }},
		{"K=0.5", func(u *simUser) { u.evidenceK = 0.5 }},
		{"K=0.01(実質無効)", func(u *simUser) { u.evidenceK = 0.01 }},
	}
	for _, hint := range []int{0, 1, 2} {
		t.Logf("=== まとめクイズのヒント段=%d ===", hint)
		t.Logf("%-12s %13s %13s %13s", "母数の決め方",
			"真150 d30/d90", "真350 d30/d90", "真700 d30/d90")
		for _, m := range modes {
			row := []any{m.name}
			for _, truth := range []int{150, 350, 700} {
				d30, d90 := 0, 0
				for s := range trials {
					r := runCellTuned(s+1, truth, false, true, 90, func(u *simUser) {
						u.summaryHint = hint
						m.tune(u)
					})
					d30 += r[30]
					d90 += r[90]
				}
				row = append(row, d30/trials, d90/trials)
			}
			t.Logf("%-12s %6d %6d %6d %6d %6d %6d", row...) // d30 d90 の3組
		}
	}
}
