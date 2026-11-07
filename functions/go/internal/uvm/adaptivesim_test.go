package uvm

import (
	"math"
	"math/rand"
	"os"
	"sort"
	"sync"
	"testing"
	"time"
)

var simNow = time.Date(2026, 11, 7, 0, 0, 0, 0, time.UTC)

// 語彙スコア・key_word 帯・まとめクイズの範囲を学習状況で動かす案の比較。
// 実行: ADAPTIVE_SIM=1 go test ./internal/uvm -run TestAdaptiveBand -v
//
// 指標: 誤差=スコア-実力（覚えた語を含む実際の境界）/ 素通り=帯の下端より下で
// 一度も key_word にならなかった語数 / 漏未知=スコア以下の未出語のうち実際は
// 知らない語の期待数 / 難%=新語のうち知っている確率が 0.1 未満の割合 /
// Q再3=まとめクイズで 3 日以内に答えた語をまた出した割合。

type adaptPersona struct {
	name        string
	truth       int
	learn       float64
	gens        int  // 1日の例文数
	startSize   int  // >0 なら SetSizeFor の入門ランプ（none=2, words=3）
	capVocab    int  // >0 なら free の語彙上限
	linkQuiz    bool // 本数が 5 に戻るまで問題数を実際の例文本数に連動させる（ヒアリングで初心者）
	breakDay    int  // >0 ならこの日にコツを掴む（真値が breakTruth になり learn が breakLearn になる）
	breakTruth  int
	breakLearn  float64
	tested      bool
	guess, slip float64
}

type adaptCfg struct {
	name         string
	forward      bool // 帯に未出が無ければ既出より先に前方の未出を出す
	quizCooldown int  // スコア枠でこの日数以内に答えた語を後回しにする
	oldEst       bool // 2026-11 までの推定式で回す
	// スコアに触らず新語を足す案
	scaffold   bool    // 帯の未出が尽きたら下の段へ。前方の語はスコア枠に入るまでクイズに出さない
	previewGap int     // 帯の外で見せてよい前方の距離（est から）
	floorDown  int     // 受験者は測定値の下のこの深さの未出も使う（スコアに効かない）
	quizOldest bool    // スコア枠を P の低い順でなく最後に答えた日の古い順にする
	accel      float64 // >0 なら skill がこれ以上のとき前方へ飛ばして測る
	accelGap   int     // 飛ばすときの前方の距離
	// 未出語だけを例文にする案。尽きたら P<=reuseX の語の既出例文を1本だけ出す
	sparse bool
}

type adaptState struct {
	cfg      adaptCfg
	capVocab int
	recent   []bool // 直近のまとめクイズの正誤（新しい順ではなく追記）
	answerD  map[int]int
	// 指標
	newPicks, hardPicks, repeat7, picks int
	reuses, emptySets, sets             int
	quizN, quizRepeat3, quizCorrect     int
}

// skill は直近20問の正答率を推測・うっかりで補正した 0〜1。証拠が少ないうちは 0.5。
func (a *adaptState) skill() float64 {
	if len(a.recent) < 5 {
		return 0.5
	}
	c := 0
	for _, ok := range a.recent {
		if ok {
			c++
		}
	}
	acc := float64(c) / float64(len(a.recent))
	return math.Max(0, math.Min(1, (acc-BayesGuessTop)/(1-BayesGuessTop-BayesSlip)))
}

func knownProb(u *simUser, rank int) float64 {
	if u.learned[rank] {
		return 1
	}
	return pKnow(rank, u.truth)
}

// trueBoundary は今の実力の境界（前後10語の平均知識が 0.5 以上の最大 rank）。
func trueBoundary(u *simUser) int {
	for r := simMaxRank - 10; r >= 1; r-- {
		sum := 0.0
		for q := max(1, r-10); q <= r+10; q++ {
			sum += knownProb(u, q)
		}
		if sum/float64(r+10-max(1, r-10)+1) >= 0.5 {
			return r
		}
	}
	return 0
}

func unseenIn(u *simUser, lo, hi int) []Candidate {
	var out []Candidate
	for r := max(lo, 1); r <= min(hi, simMaxRank); r++ {
		if _, ok := u.words[r]; !ok {
			out = append(out, Candidate{Word: "", Rank: r})
		}
	}
	return out
}

func (a *adaptState) pickOldest(u *simUser, lo, hi int) (int, bool) {
	best, bestSeen := -1, math.Inf(1)
	for r := max(lo, 1); r <= hi; r++ {
		if _, ok := u.words[r]; ok && u.lastSeen[r] < bestSeen {
			best, bestSeen = r, u.lastSeen[r]
		}
	}
	return best, best >= 0
}

// band は key_word の帯（free は上限で切る。本番の sessionBand）。
func (a *adaptState) band(u *simUser) (int, int) {
	var m *int
	if a.capVocab > 0 {
		m = &a.capVocab
	}
	return sessionBand(u.est, u.floor, m)
}

// sync は推定の再計算（free は上限で切る）。
func (a *adaptState) sync(u *simUser) {
	u.sync()
	if a.capVocab > 0 {
		u.est = min(u.est, a.capVocab)
	}
}

func (a *adaptState) accelerating() bool {
	return a.cfg.accel > 0 && len(a.recent) >= 10 && a.skill() >= a.cfg.accel
}

func (a *adaptState) pickKeyWord(u *simUser) (int, bool) {
	lo, hi := a.band(u)
	first := func(c []Candidate) int { return c[0].Rank }
	weighted := func(c []Candidate) int { return u.sel.SelectWeighted(c, ZeroPWeights(c), 1)[0].Rank }

	if a.cfg.scaffold {
		if a.accelerating() {
			if back := unseenIn(u, max(lo, u.floor+1), u.est); len(back) > 0 && u.rnd.Float64() < 0.25 {
				return first(back), true
			}
			if f := unseenIn(u, u.est+1, u.est+a.cfg.accelGap); len(f) > 0 {
				return f[u.rnd.Intn(len(f))].Rank, true
			}
		}
		if zero := unseenIn(u, lo, hi); len(zero) > 0 {
			return weighted(zero), true
		}
		if a.cfg.floorDown > 0 && u.floor > 0 {
			if d := unseenIn(u, u.floor-a.cfg.floorDown, u.floor); len(d) > 0 {
				return d[len(d)-1].Rank, true
			}
		}
		if f := unseenIn(u, hi+1, u.est+a.cfg.previewGap); len(f) > 0 {
			return first(f), true
		}
		return a.pickOldest(u, lo, hi)
	}

	if zero := unseenIn(u, lo, hi); len(zero) > 0 {
		return weighted(zero), true
	}
	if a.cfg.forward {
		if f := unseenIn(u, hi+1, hi+ForwardTopUpDepth); len(f) > 0 {
			return first(f), true
		}
	}
	return a.pickOldest(u, lo, hi)
}

// pickQuiz は本番のまとめクイズ（SRS 2 + 苦手 1 + スコア枠 + 低P）の写し。
func (a *adaptState) pickQuiz(u *simUser, n int) []int {
	used := map[int]bool{}
	var out []int
	lo, hi := QuizScoreBand(map[string]any{
		"tier": "premium", "estimated_vocab": u.est, "vocab_test_vocab": u.floor,
	}, simNow)
	if a.accelerating() {
		hi = max(hi, u.est+a.cfg.accelGap)
	}
	allowed := func(r int) bool {
		if a.cfg.scaffold && r > hi {
			return false
		}
		return u.floor <= 0 || r >= u.floor
	}
	ivs := []int{1, 3, 7, 14, 30}
	u.rnd.Shuffle(len(ivs), func(i, j int) { ivs[i], ivs[j] = ivs[j], ivs[i] })
	for _, iv := range ivs {
		if len(out) >= min(2, n/2) {
			break
		}
		best, bestP := -1, math.Inf(1)
		for r, d := range u.bornDay {
			if d == u.day-iv && allowed(r) && (u.words[r].p < bestP || (u.words[r].p == bestP && r < best)) {
				best, bestP = r, u.words[r].p
			}
		}
		if best >= 0 {
			out = append(out, best)
			used[best] = true
		}
	}

	var all []int
	for r := range u.words {
		all = append(all, r)
	}
	sort.Ints(all)
	u.rnd.Shuffle(len(all), func(i, j int) { all[i], all[j] = all[j], all[i] })
	cooled := func(r int) bool {
		d, ok := a.answerD[r]
		return a.cfg.quizCooldown > 0 && ok && u.day-d < a.cfg.quizCooldown
	}
	sort.SliceStable(all, func(i, j int) bool {
		if ci, cj := cooled(all[i]), cooled(all[j]); ci != cj {
			return cj
		}
		if a.cfg.quizOldest {
			if di, dj := a.answerD[all[i]], a.answerD[all[j]]; di != dj {
				return di < dj
			}
		}
		return u.words[all[i]].p < u.words[all[j]].p
	})
	take := func(cond func(int) bool, limit int) {
		for _, r := range all {
			if len(out) >= limit {
				return
			}
			if !used[r] && allowed(r) && cond(r) {
				out = append(out, r)
				used[r] = true
			}
		}
	}
	inBand := func(r int) bool { return r >= lo && r <= hi }
	take(func(r int) bool {
		w := u.words[r]
		return !inBand(r) && w.attempts >= 2 && w.p < 0.3
	}, min(n, len(out)+1))
	take(inBand, n)
	take(func(int) bool { return true }, n)
	return out
}

type adaptResult struct {
	est, truth, missed, skipped, tooHard, repeat, newPerDay, quizRepeat, acc float64
	sentPerDay, reusePerDay, emptyPct, quizPerDay                            float64
}

func runAdaptive(seed int, p adaptPersona, cfg adaptCfg, days int) adaptResult {
	u, a := newAdaptiveUser(seed, p, cfg)
	for day := 1; day <= days; day++ {
		u.day = day
		if p.breakDay > 0 && day == p.breakDay {
			u.truth, u.learnRate = p.breakTruth, p.breakLearn
		}
		if cfg.sparse {
			for range max(1, p.gens/5) {
				a.sparseSet(u, p)
			}
			continue
		}
		for range dailyGens(p, u.est) {
			r, ok := a.pickKeyWord(u)
			if !ok {
				continue
			}
			a.picks++
			if last, seen := u.lastSeen[r]; seen && float64(day)-last <= 7 {
				a.repeat7++
			}
			if _, seen := u.words[r]; !seen {
				a.newPicks++
				if knownProb(u, r) < 0.1 {
					a.hardPicks++
				}
				u.words[r] = &simWord{p: NewWordP}
				u.bornDay[r] = day
			}
			u.touch(r)
			// 確認クイズは読んだ直後で答えが見えているので正解扱い（P は動かない）。
			// 本番は正解でも evidence が付いて母数に入る。
			u.words[r].evidence += LearningEvidenceScale
			a.sync(u)
		}
		for range max(1, p.gens/5) {
			for _, r := range a.pickQuiz(u, setSize(p, u.est)) {
				a.quizN++
				if d, ok := a.answerD[r]; ok && day-d <= 3 {
					a.quizRepeat3++
				}
				u.answer(r, false)
				a.answerD[r] = day
				if u.lastAnswer {
					a.quizCorrect++
				}
				a.recent = append(a.recent, u.lastAnswer)
				if len(a.recent) > 20 {
					a.recent = a.recent[1:]
				}
			}
			a.sync(u)
		}
	}
	missed := 0.0
	for _, c := range unseenIn(u, u.floor+1, u.est) {
		missed += 1 - knownProb(u, c.Rank)
	}
	low, _ := KeyWordBand(u.est, u.floor)
	sentTotal := a.picks
	if !cfg.sparse {
		a.sets = days * max(1, p.gens/5)
	}
	return adaptResult{
		sentPerDay:  float64(sentTotal) / float64(days),
		reusePerDay: float64(a.reuses) / float64(days),
		emptyPct:    100 * float64(a.emptySets) / float64(max(a.sets, 1)),
		quizPerDay:  float64(a.quizN) / float64(days),
		est:         float64(u.est), truth: float64(trueBoundary(u)), missed: missed,
		skipped:    float64(len(unseenIn(u, u.floor+1, low-1))),
		tooHard:    100 * float64(a.hardPicks) / float64(max(a.newPicks, 1)),
		repeat:     100 * float64(a.repeat7) / float64(max(a.picks, 1)),
		newPerDay:  float64(a.newPicks) / float64(days),
		quizRepeat: 100 * float64(a.quizRepeat3) / float64(max(a.quizN, 1)),
		acc:        100 * float64(a.quizCorrect) / float64(max(a.quizN, 1)),
	}
}

func newAdaptiveUser(seed int, p adaptPersona, cfg adaptCfg) (*simUser, *adaptState) {
	rnd := rand.New(rand.NewSource(int64(seed)))
	u := &simUser{
		rnd: rnd, truth: p.truth, words: map[int]*simWord{},
		sel: &SessionSelector{Rand: rnd}, bornDay: map[int]int{},
		learnRate: p.learn, worldGuess: p.guess, worldSlip: p.slip,
		learningInPool: true,
	}
	if p.tested {
		u.floor = takeVocabTest(rnd, p.truth)
		u.est = u.floor
	}
	if cfg.oldEst {
		u.cutoff, u.knownP = 0.42, 0.5
	}
	return u, &adaptState{cfg: cfg, capVocab: p.capVocab, answerD: map[int]int{}}
}

var adaptPersonas = []adaptPersona{
	{name: "入門・伸びる 初心者", truth: 30, learn: 0.10, gens: 5, startSize: 2, linkQuiz: true},
	{name: "入門・詰まる 初心者", truth: 30, learn: 0.02, gens: 5, startSize: 2, linkQuiz: true},
	{name: "入門→d30にコツ 初心者", truth: 30, learn: 0.02, gens: 5, startSize: 2, linkQuiz: true, breakDay: 30, breakTruth: 200, breakLearn: 0.15},
	{name: "free 詰まる", truth: 60, learn: 0.02, gens: 5, capVocab: FreeTierMaxVocab},
	{name: "free 上限到達", truth: 150, learn: 0.10, gens: 5, capVocab: FreeTierMaxVocab},
	{name: "初級・詰まる 受験", truth: 150, learn: 0.02, gens: 5, tested: true},
	{name: "初級→d30にコツ 受験", truth: 150, learn: 0.02, gens: 5, tested: true, breakDay: 30, breakTruth: 400, breakLearn: 0.15},
	{name: "中級・詰まる 受験", truth: 350, learn: 0.02, gens: 5, tested: true},
	{name: "中級・伸びる 未受験", truth: 350, learn: 0.10, gens: 5},
	{name: "上級・伸びる 未受験", truth: 700, learn: 0.10, gens: 5},
}

var adaptCfgs = []adaptCfg{
	{name: "現行"},
	{name: "決定案", sparse: true},
}

func TestAdaptiveBand(t *testing.T) {
	if os.Getenv("ADAPTIVE_SIM") == "" {
		t.Skip("ADAPTIVE_SIM=1 で実行")
	}
	if lo, hi := QuizScoreBand(map[string]any{"tier": "premium", "estimated_vocab": 500}, simNow); lo != 470 || hi != 508 {
		t.Fatalf("QuizScoreBand = %d,%d", lo, hi)
	}
	const trials, days = 20.0, 90
	worlds := []struct {
		name        string
		guess, slip float64
	}{{"推測.25 slip0", 0.25, 0}, {"推測.45 slip.10", 0.45, 0.10}}
	for _, w := range worlds {
		t.Logf("##### 世界 %s", w.name)
		for _, base := range adaptPersonas {
			p := base
			p.guess, p.slip = w.guess, w.slip
			rows := make([]adaptResult, len(adaptCfgs))
			var wg sync.WaitGroup
			for i, cfg := range adaptCfgs {
				wg.Add(1)
				go func() {
					defer wg.Done()
					var m adaptResult
					for s := range int(trials) {
						r := runAdaptive(s+1, p, cfg, days)
						m.est += r.est / trials
						m.truth += r.truth / trials
						m.missed += r.missed / trials
						m.skipped += r.skipped / trials
						m.tooHard += r.tooHard / trials
						m.repeat += r.repeat / trials
						m.newPerDay += r.newPerDay / trials
						m.quizRepeat += r.quizRepeat / trials
						m.acc += r.acc / trials
						m.sentPerDay += r.sentPerDay / trials
						m.reusePerDay += r.reusePerDay / trials
						m.emptyPct += r.emptyPct / trials
						m.quizPerDay += r.quizPerDay / trials
					}
					rows[i] = m
				}()
			}
			wg.Wait()
			t.Logf("=== %s", p.name)
			t.Logf("%-18s %5s %5s %5s %5s %5s %5s %5s %5s %5s %5s", "案", "スコア", "実力", "誤差", "例文/日", "新語/日", "既出/日", "空%", "Q/日", "Q再3", "正答")
			for i, cfg := range adaptCfgs {
				m := rows[i]
				t.Logf("%-18s %5.0f %5.0f %+5.0f %5.1f %5.1f %5.1f %5.0f %5.1f %5.0f %5.0f", cfg.name,
					m.est, m.truth, m.est-m.truth, m.sentPerDay, m.newPerDay, m.reusePerDay, m.emptyPct, m.quizPerDay, m.quizRepeat, m.acc)
			}
		}
	}
}

// setSize は sentence.SetSizeFor の写し（uvm から sentence を呼べないため）。
func setSize(p adaptPersona, est int) int {
	if p.startSize == 0 || est >= 50 {
		return 5
	}
	return p.startSize + max(est, 0)*(5-p.startSize)/50
}

func dailyGens(p adaptPersona, est int) int {
	return p.gens * setSize(p, est) / 5
}

// nextUnseen は次に例文にする未出語。帯 → （足場があれば）測定値の下 → 前方の順。
func (a *adaptState) nextUnseen(u *simUser) (int, bool) {
	lo, hi := a.band(u)
	if zero := unseenIn(u, lo, hi); len(zero) > 0 {
		return u.sel.SelectWeighted(zero, ZeroPWeights(zero), 1)[0].Rank, true
	}
	if !a.cfg.scaffold {
		return 0, false
	}
	if u.floor > 0 {
		if d := unseenIn(u, u.floor-a.cfg.floorDown, u.floor); len(d) > 0 {
			return d[len(d)-1].Rank, true
		}
	}
	if f := unseenIn(u, hi+1, u.est+a.cfg.previewGap); len(f) > 0 {
		return f[0].Rank, true
	}
	return 0, false
}

// MinSetSizeSim はセットの最低本数（sentence.MinSetSize の写し）。
const MinSetSizeSim = 2

// reusePick は既出例文を出す語。P<=ReuseMaxP をランダムに、無ければ最も古く見た語。
func (a *adaptState) reusePick(u *simUser, used map[int]bool) (int, bool) {
	lo, hi := a.band(u)
	var weak []int
	best, bestSeen := -1, math.Inf(1)
	for r := max(lo, 1); r <= hi; r++ {
		w, ok := u.words[r]
		if !ok || used[r] {
			continue
		}
		if w.p <= ReuseMaxP {
			weak = append(weak, r)
		}
		if u.lastSeen[r] < bestSeen {
			best, bestSeen = r, u.lastSeen[r]
		}
	}
	if len(weak) > 0 {
		return weak[u.rnd.Intn(len(weak))], true
	}
	return best, best >= 0
}

// sparseSet はセット 1 回ぶん。未出語だけを最大 5 本、最低本数に足りなければ既出例文で埋める。
func (a *adaptState) sparseSet(u *simUser, p adaptPersona) {
	a.sets++
	sent := 0
	for range setSize(p, u.est) {
		r, ok := a.nextUnseen(u)
		if !ok {
			break
		}
		a.newPicks++
		if knownProb(u, r) < 0.1 {
			a.hardPicks++
		}
		u.words[r] = &simWord{p: NewWordP}
		u.bornDay[r] = u.day
		u.touch(r)
		u.words[r].evidence += LearningEvidenceScale
		a.sync(u)
		a.picks++
		sent++
	}
	used := map[int]bool{}
	for sent < min(MinSetSizeSim, setSize(p, u.est)) {
		r, ok := a.reusePick(u, used)
		if !ok {
			a.emptySets++
			break
		}
		if last, seen := u.lastSeen[r]; seen && float64(u.day)-last <= 7 {
			a.repeat7++
		}
		used[r] = true
		u.touch(r)
		a.sync(u)
		a.picks++
		a.reuses++
		sent++
	}
	// 入門者は本数が 5 に戻るまで問題数を例文に連動させる。
	n := setSize(p, u.est)
	if p.linkQuiz && n < 5 {
		n = sent
	}
	if n == 0 {
		return
	}
	for _, r := range a.pickQuiz(u, n) {
		a.quizN++
		if d, ok := a.answerD[r]; ok && u.day-d <= 3 {
			a.quizRepeat3++
		}
		u.answer(r, false)
		a.answerD[r] = u.day
		if u.lastAnswer {
			a.quizCorrect++
		}
		a.recent = append(a.recent, u.lastAnswer)
		if len(a.recent) > 20 {
			a.recent = a.recent[1:]
		}
	}
	a.sync(u)
}
