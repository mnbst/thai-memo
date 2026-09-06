package uvm

import (
	"fmt"
	"math/rand"
	"testing"
)

// runTest は開始段から NextStage を回し、正答数を answers で与えて履歴を作る。
// answers は出題順の正答数。足りなくなったら 0 とみなす。
func runTest(start int, answers []int) []StageResult {
	var history []StageResult
	stage := start
	for i := 0; ; i++ {
		correct := 0
		if i < len(answers) {
			correct = answers[i]
		}
		history = append(history, StageResult{Stage: stage, Correct: correct})
		next, done := NextStage(history)
		if done {
			return history
		}
		stage = next
	}
}

// 初心者は 1 段目で落ちて 1 段ぶんで終わる（テストを入れる目的そのもの）。
func TestNextStageBeginnerStopsAfterOneStage(t *testing.T) {
	history := runTest(0, []int{0})
	if len(history) != 1 {
		t.Fatalf("段数 = %d, want 1 (履歴=%v)", len(history), history)
	}
	if items := len(history) * TestItemsPerStage; items != TestItemsPerStage {
		t.Errorf("出題数 = %d, want %d", items, TestItemsPerStage)
	}
}

func TestNextStageClimbsToCeiling(t *testing.T) {
	history := runTest(0, fill(len(TestStages), TestItemsPerStage))
	if len(history) != len(TestStages) {
		t.Fatalf("段数 = %d, want %d", len(history), len(TestStages))
	}
	last := history[len(history)-1]
	if last.Stage != len(TestStages)-1 {
		t.Errorf("最終段 = %d, want %d", last.Stage, len(TestStages)-1)
	}
}

// 落ちたらそこで終わる。下へ戻る経路は無い（開始段が常に 0 なので不要）。
func TestNextStageStopsOnFailure(t *testing.T) {
	history := runTest(0, []int{TestItemsPerStage, 0})
	if len(history) != 2 {
		t.Fatalf("履歴 = %v, want 2 段", history)
	}
	if history[1].Stage != 1 {
		t.Errorf("2 段目 = %d, want 1", history[1].Stage)
	}
	if _, done := NextStage(history); !done {
		t.Error("不通過なのに続行になった")
	}
}

func TestScoreVocab(t *testing.T) {
	cases := []struct {
		name    string
		history []StageResult
		want    int
	}{
		// 期待値は内挿の結果そのもの（ScoreBias は 0）。出題は 1 段 6 問、
		// 通過は 5 問（TestItemsPerStage / TestPassThreshold）。
		//
		// 1 段目 [1,50] で 0/6 → 推測補正後 0 → 下限に張り付く
		{"完全初心者", []StageResult{{0, 0}}, 0},
		// 1 段目 3/6 → c=(0.5-0.35)/0.65=0.2308 → 0 + round(50*0.2308)=12
		{"1段目で半分", []StageResult{{0, 3}}, 12},
		// 1 段目通過、2 段目 [51,150] で 1/6 → c=0 → 50（1 段目の上限）
		{"1段目のみ通過", []StageResult{{0, 6}, {1, 1}}, 50},
		// 3 段目 [151,300] で 3/6 → 150 + round(150*0.2308)=185
		{"3段目で半分", []StageResult{{0, 6}, {1, 6}, {2, 3}}, 185},
		// 全段通過 → 最上段の上限
		{"天井", allPassed(), 3000},
		// 1 段落としても通過（6 問中 5 問）
		{"1問落として通過", []StageResult{{0, 5}, {1, 1}}, 50},
		{"下降して通過", []StageResult{{2, 1}, {1, 6}}, 150},
	}
	for _, c := range cases {
		if got := ScoreVocab(c.history); got != c.want {
			t.Errorf("%s: ScoreVocab(%v) = %d, want %d", c.name, c.history, got, c.want)
		}
	}
}

// スコアは段を上がるほど単調に増える（下がる帯があるとレベルが逆転する）。
func TestScoreVocabMonotonic(t *testing.T) {
	prev := -1
	for stage := range TestStages {
		history := runTest(0, append(fill(stage, TestItemsPerStage), 0))
		got := ScoreVocab(history)
		if got < prev {
			t.Errorf("段 %d で %d に下がった（前段 %d）", stage, got, prev)
		}
		prev = got
	}
}

// allPassed は全段を通過した履歴。
func allPassed() []StageResult {
	out := make([]StageResult, 0, len(TestStages))
	for i := range TestStages {
		out = append(out, StageResult{i, TestItemsPerStage})
	}
	return out
}

func fill(n, v int) []int {
	out := make([]int, n)
	for i := range out {
		out[i] = v
	}
	return out
}

func testItems(n int) []TestItem {
	out := make([]TestItem, 0, n)
	for i := 1; i <= n; i++ {
		out = append(out, TestItem{
			Word:  fmt.Sprintf("คำ%d", i),
			Rank:  i,
			Gloss: fmt.Sprintf("訳%d", i),
		})
	}
	return out
}

func TestBuildStageQuestions(t *testing.T) {
	items := testItems(3000)
	rnd := rand.New(rand.NewSource(1))
	qs := BuildStageQuestions(items, TestStages[2], TestItemsPerStage, rnd)

	if len(qs) != TestItemsPerStage {
		t.Fatalf("問題数 = %d, want %d", len(qs), TestItemsPerStage)
	}
	seen := map[string]bool{}
	for _, q := range qs {
		if len(q.Choices) != 4 {
			t.Errorf("%s の選択肢 = %d, want 4", q.Word, len(q.Choices))
		}
		if q.AnswerIndex < 0 || q.AnswerIndex >= len(q.Choices) {
			t.Errorf("%s の正解位置 = %d", q.Word, q.AnswerIndex)
		}
		if seen[q.Word] {
			t.Errorf("%s が重複した", q.Word)
		}
		seen[q.Word] = true

		dup := map[string]bool{}
		for _, c := range q.Choices {
			if dup[c] {
				t.Errorf("%s の選択肢が重複した: %v", q.Word, q.Choices)
			}
			dup[c] = true
		}
	}
}

// 正解の位置が偏ると、位置だけで当てられる。
func TestBuildStageQuestionsAnswerPositionSpread(t *testing.T) {
	items := testItems(3000)
	counts := map[int]int{}
	for seed := range 100 {
		rnd := rand.New(rand.NewSource(int64(seed)))
		for _, q := range BuildStageQuestions(items, TestStages[0], TestItemsPerStage, rnd) {
			counts[q.AnswerIndex]++
		}
	}
	for i := range 4 {
		if counts[i] == 0 {
			t.Errorf("正解が位置 %d に一度も来なかった: %v", i, counts)
		}
	}
}

// 訳が重複した語が混ざっても、n 問そろえて返す。
//
// 先頭 n 語だけを見ていた頃は、重複を 1 つ引いた段が 3 問になり、
// buildVocabTestStage がテスト全体を Internal で落としていた。
func TestBuildStageQuestionsFillsAroundDuplicateGlosses(t *testing.T) {
	stage := TestStage{Low: 1, High: 20}
	var items []TestItem
	for r := 1; r <= 20; r++ {
		gloss := fmt.Sprintf("g%02d", r)
		if r%2 == 0 {
			gloss = "かぶった訳" // 半分を潰す。残り 10 語で 4 問は組める
		}
		items = append(items, TestItem{
			Word: fmt.Sprintf("w%02d", r), Rank: r, Gloss: gloss,
		})
	}

	for seed := int64(0); seed < 50; seed++ {
		qs := BuildStageQuestions(items, stage, TestItemsPerStage,
			rand.New(rand.NewSource(seed)))
		if len(qs) != TestItemsPerStage {
			t.Fatalf("seed=%d: 出題数 = %d, want %d", seed, len(qs), TestItemsPerStage)
		}
		seen := map[string]bool{}
		for _, q := range qs {
			if seen[q.Word] {
				t.Fatalf("seed=%d: %s が重複して出た", seed, q.Word)
			}
			seen[q.Word] = true
			if len(q.Choices) != 4 {
				t.Fatalf("seed=%d: %s の選択肢が %d 個", seed, q.Word, len(q.Choices))
			}
		}
	}
}

// 出題語は必ずその段のランク帯に入る（帯がずれると測定値がずれる）。
func TestBuildStageQuestionsStaysInBand(t *testing.T) {
	items := testItems(3000)
	rankOf := map[string]int{}
	for _, it := range items {
		rankOf[it.Word] = it.Rank
	}
	for si, stage := range TestStages {
		rnd := rand.New(rand.NewSource(int64(si)))
		for _, q := range BuildStageQuestions(items, stage, TestItemsPerStage, rnd) {
			if r := rankOf[q.Word]; r < stage.Low || r > stage.High {
				t.Errorf("段 %d: %s の rank=%d が帯 [%d,%d] の外",
					si, q.Word, r, stage.Low, stage.High)
			}
		}
	}
}

func TestSeedPWritesOnlyKnownWordMisses(t *testing.T) {
	// 正解は書かない。既知語を置くと knownMaxRank の床になり、再受験で
	// 測定値を下げても前回の測定値まで登り直してしまう。
	if _, write := TestSeedP(0, false, true); write {
		t.Error("未登録語の正解を書こうとした")
	}
	if _, write := TestSeedP(0.9, true, true); write {
		t.Error("既存語の正解を書こうとした")
	}

	// 未登録語の誤答も書かない。書くと GetSessionWords の「未登録 or P=0」に
	// 引っかからなくなり、知らないと分かった語が key_word に選ばれなくなる。
	if _, write := TestSeedP(0, false, false); write {
		t.Error("未登録語の誤答を書こうとした")
	}

	// 書くのは既存語の誤答だけ。履歴のほうが4択1問より信頼できるので半減に留める。
	p, write := TestSeedP(0.6, true, false)
	if !write || p != 0.3 {
		t.Errorf("既存語の誤答 = (%v, %v), want (0.3, true)", p, write)
	}
	if p, _ := TestSeedP(0, true, false); p != PMin {
		t.Errorf("P=0 の既存語の誤答 = %v, want %v", p, PMin)
	}
}
