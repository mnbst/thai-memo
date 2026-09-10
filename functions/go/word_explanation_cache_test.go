package function

import (
	"context"
	"testing"

	"github.com/mnbst/thai-memo/functions/go/internal/lang"
	"github.com/mnbst/thai-memo/functions/go/internal/quizgen"
)

type fakeExplanationStore struct {
	entries map[string]wordExplanationEntry
	loads   int
	saves   int
}

func newFakeExplanationStore() *fakeExplanationStore {
	return &fakeExplanationStore{entries: map[string]wordExplanationEntry{}}
}

func (s *fakeExplanationStore) Load(_ context.Context, key string) (string, bool) {
	s.loads++
	entry, ok := s.entries[key]
	return entry.Explanation, ok
}

func (s *fakeExplanationStore) Save(_ context.Context, key string, entry wordExplanationEntry) {
	s.saves++
	s.entries[key] = entry
}

// countingQuizService は呼ばれた回数を数えるだけのモデル代わり。
type countingQuizService struct {
	calls       int
	explanation string
}

func (s *countingQuizService) GenerateQuizQuestions(
	_ context.Context, sentences []quizgen.QuizSentenceSeed,
) []quizgen.GeneratedQuizQuestion {
	s.calls++
	merged := quizgen.ApplyRuleBasedFields(
		[]quizgen.Draft{{Explanation: s.explanation}}, sentences)
	return quizgen.DefaultSanitizer.Questions(merged)
}

func meaningSeed() quizgen.QuizSentenceSeed {
	source, _ := buildLearningQuizSourceForClient(learningQuizPayload(), true)
	return source.Seed
}

// 2回目以降はモデルを呼ばずキャッシュから解説を返す。
func TestWordExplanationCacheHitSkipsModel(t *testing.T) {
	store := newFakeExplanationStore()
	inner := &countingQuizService{explanation: "「勉強する」という意味の動詞。"}
	service := &cachedQuizService{inner: inner, store: store, lang: lang.JA}

	seeds := []quizgen.QuizSentenceSeed{meaningSeed()}
	first := service.GenerateQuizQuestions(context.Background(), seeds)
	if len(first) != 1 || first[0].Explanation != inner.explanation {
		t.Fatalf("初回の生成に失敗した: %+v", first)
	}
	if inner.calls != 1 || store.saves != 1 {
		t.Fatalf("calls=%d saves=%d", inner.calls, store.saves)
	}

	second := service.GenerateQuizQuestions(context.Background(), seeds)
	if len(second) != 1 || second[0].Explanation != inner.explanation {
		t.Fatalf("キャッシュから作れなかった: %+v", second)
	}
	if inner.calls != 1 {
		t.Fatalf("キャッシュヒット時にモデルを呼んでいる: calls=%d", inner.calls)
	}
	if second[0].QuizFormat != quizgen.FormatMeaningChoice ||
		len(second[0].Choices) != 4 {
		t.Fatalf("キャッシュ経由の1問が壊れている: %+v", second[0])
	}
}

// 穴埋めはダミーと理由もモデルに作らせるのでキャッシュ対象外。
func TestWordExplanationCacheSkipsClozeQuiz(t *testing.T) {
	store := newFakeExplanationStore()
	inner := &countingQuizService{explanation: "解説"}
	service := &cachedQuizService{inner: inner, store: store, lang: lang.JA}

	source, _ := buildLearningQuizSourceForClient(learningQuizPayload(), false)
	seeds := []quizgen.QuizSentenceSeed{source.Seed}
	service.GenerateQuizQuestions(context.Background(), seeds)
	service.GenerateQuizQuestions(context.Background(), seeds)

	if inner.calls != 2 {
		t.Fatalf("穴埋めでキャッシュが効いている: calls=%d", inner.calls)
	}
	if store.loads != 0 || store.saves != 0 {
		t.Fatalf("穴埋めでキャッシュを触っている: loads=%d saves=%d", store.loads, store.saves)
	}
}

// 同じ語でも意味が違えば別のキャッシュになる。
func TestWordExplanationKeySeparatesMeanings(t *testing.T) {
	a := wordExplanationKey(lang.JA, "เรียน", "勉強する")
	b := wordExplanationKey(lang.JA, "เรียน", "学ぶ")
	en := wordExplanationKey(lang.EN, "เรียน", "勉強する")
	if a == "" || a == b || a == en {
		t.Fatalf("キーが分かれていない: a=%s b=%s en=%s", a, b, en)
	}
	if wordExplanationKey(lang.JA, "เรียน", "") != "" {
		t.Fatal("意味が空でもキーを作っている")
	}
}

// 解説が空のときは保存しない（次回また作り直す）。
func TestWordExplanationCacheSkipsEmptyExplanation(t *testing.T) {
	store := newFakeExplanationStore()
	inner := &countingQuizService{explanation: ""}
	service := &cachedQuizService{inner: inner, store: store, lang: lang.JA}

	service.GenerateQuizQuestions(
		context.Background(), []quizgen.QuizSentenceSeed{meaningSeed()})
	if store.saves != 0 {
		t.Fatalf("空の解説を保存している: saves=%d", store.saves)
	}
}
