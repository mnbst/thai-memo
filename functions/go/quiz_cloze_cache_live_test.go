package function

import (
	"context"
	"os"
	"sort"
	"testing"

	"github.com/mnbst/thai-memo/functions/go/internal/fbapp"
	"github.com/mnbst/thai-memo/functions/go/internal/gemini"
	"github.com/mnbst/thai-memo/functions/go/internal/lang"
	"github.com/mnbst/thai-memo/functions/go/internal/quizgen"
	"github.com/mnbst/thai-memo/functions/go/internal/secrets"
)

// countingInner は Gemini 呼び出しの回数を数える薄いラッパー。
type countingInner struct {
	inner quizService
	calls int
}

func (s *countingInner) GenerateQuizQuestions(
	ctx context.Context, sentences []quizgen.QuizSentenceSeed,
) []quizgen.GeneratedQuizQuestion {
	s.calls++
	return s.inner.GenerateQuizQuestions(ctx, sentences)
}

// TestQuizClozeCacheLive は実 Firestore と実 Gemini でキャッシュの往復を見る。
// 1回目は生成して保存し、2回目はモデルを呼ばずに同じ問題が戻ること。
//
//	GOOGLE_CLOUD_PROJECT=thai-memo-dev QUIZ_DISTRACTOR_LIVE=1 \
//	  go test ./ -run TestQuizClozeCacheLive -v
func TestQuizClozeCacheLive(t *testing.T) {
	if os.Getenv("QUIZ_DISTRACTOR_LIVE") == "" {
		t.Skip("QUIZ_DISTRACTOR_LIVE=1 で実行する")
	}
	ctx := context.Background()
	key, err := secrets.Get(ctx, "gemini-api-key")
	if err != nil {
		t.Skipf("gemini-api-key が要る: %v", err)
	}
	db, err := fbapp.Firestore(ctx)
	if err != nil {
		t.Skipf("Firestore に繋げない: %v", err)
	}

	freqRank := loadLocalFreqRank(t)
	sorted := make([]rankedWord, 0, len(freqRank))
	for word, rank := range freqRank {
		sorted = append(sorted, rankedWord{word: word, rank: rank})
	}
	sort.Slice(sorted, func(i, j int) bool { return sorted[i].rank < sorted[j].rank })
	vocab := &quizVocab{freqRank: freqRank, sorted: sorted, pos: map[string]string{}}

	row := loadCorpusSample(t, 1)[0]
	seed := quizgen.QuizSentenceSeed{
		QuizFormat:           quizgen.FormatClozeChoice,
		ThaiText:             row.thai,
		Words:                row.words,
		KeyWord:              row.target,
		KeyWordPronunciation: row.targetPron,
		JapaneseTranslation:  "（省略）",
	}
	if len(quizgen.PickDistractors(vocab, row.target, row.words, nil)) == 0 {
		t.Skip("ダミーを選べない例文だった")
	}

	// 前回の実行が残っていると1回目からヒットしてしまう。
	cacheKey := quizClozeKey(lang.JA, seed.ThaiText)
	if _, err := db.Collection(quizClozeCollection).Doc(cacheKey).Delete(ctx); err != nil {
		t.Fatalf("前回分の掃除に失敗: %v", err)
	}

	inner := &countingInner{inner: &gemini.QuizService{
		APIKey: key, UID: "live-test", Tier: "premium", Lang: lang.JA,
	}}
	service := withQuizClozeCache(inner, db, lang.JA)

	first := service.GenerateQuizQuestions(ctx, []quizgen.QuizSentenceSeed{seed})
	if len(first) != 1 {
		t.Fatal("1回目が作れない")
	}
	if inner.calls != 1 {
		t.Fatalf("1回目のモデル呼び出し %d回, want 1", inner.calls)
	}

	second := service.GenerateQuizQuestions(ctx, []quizgen.QuizSentenceSeed{seed})
	if len(second) != 1 {
		t.Fatalf("2回目が作れない")
	}
	if inner.calls != 1 {
		t.Errorf("2回目でモデルを呼んでいる（計 %d回）", inner.calls)
	}
	if second[0].Explanation != first[0].Explanation {
		t.Errorf("解説が変わっている:\n 1回目 %q\n 2回目 %q",
			first[0].Explanation, second[0].Explanation)
	}
	if len(second[0].DummyReasons) != quizgen.DistractorCount {
		t.Errorf("理由が %d件", len(second[0].DummyReasons))
	}
	if sortedCopy(second[0].Choices) == nil ||
		len(sortedCopy(second[0].Choices)) != 4 {
		t.Errorf("選択肢 %v", second[0].Choices)
	}
	t.Logf("問題 %s / 正解 %s / 選択肢 %v", second[0].BlankText, second[0].CorrectAnswer,
		second[0].Choices)
	t.Logf("理由 %v", second[0].DummyReasons)
	t.Logf("モデル呼び出し 計%d回（2回出題）", inner.calls)
}
