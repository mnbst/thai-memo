package function

import (
	"context"
	"sort"
	"testing"

	"github.com/mnbst/thai-memo/functions/go/internal/lang"
	"github.com/mnbst/thai-memo/functions/go/internal/quizgen"
)

// fakeClozeStore は保存内容をメモリに持つ。
type fakeClozeStore struct {
	entries map[string]quizClozeEntry
	loads   int
	saves   int
}

func (s *fakeClozeStore) Load(_ context.Context, key string) (quizClozeEntry, bool) {
	s.loads++
	entry, ok := s.entries[key]
	return entry, ok
}

func (s *fakeClozeStore) Save(_ context.Context, key string, entry quizClozeEntry) {
	s.saves++
	if s.entries == nil {
		s.entries = map[string]quizClozeEntry{}
	}
	s.entries[key] = entry
}

// countingClozeService は呼ばれた回数を数え、固定の1問を返す。
// 意味4択側の countingQuizService はルールベース合成を通すので別物。
type countingClozeService struct {
	calls     int
	questions []quizgen.GeneratedQuizQuestion
}

func (s *countingClozeService) GenerateQuizQuestions(
	_ context.Context, _ []quizgen.QuizSentenceSeed,
) []quizgen.GeneratedQuizQuestion {
	s.calls++
	return s.questions
}

func clozeSeed() quizgen.QuizSentenceSeed {
	return quizgen.QuizSentenceSeed{
		QuizFormat:           quizgen.FormatClozeChoice,
		ThaiText:             "ผมไม่ค่อยซ้อมมวยไทยครับ",
		Words:                []string{"ผม", "ไม่", "ค่อย", "ซ้อม", "มวยไทย", "ครับ"},
		KeyWord:              "ไม่",
		KeyWordPronunciation: "mâi",
		JapaneseTranslation:  "私はあまりムエタイの練習をしません。",
		FixedDummies:         []string{"คน", "เป็น", "ลง"},
	}
}

func clozeQuestion() quizgen.GeneratedQuizQuestion {
	return quizgen.GeneratedQuizQuestion{
		ThaiText:      "ผมไม่ค่อยซ้อมมวยไทยครับ",
		BlankText:     "ผม___ค่อยซ้อมมวยไทยครับ",
		CorrectAnswer: "ไม่",
		Choices:       []string{"ไม่", "คน", "เป็น", "ลง"},
		Explanation:   "否定の副詞が入る位置のため。",
		DummyReasons: []string{
			"คน (khon / 人)：否定副詞の位置に名詞が入り文法上不自然",
			"เป็น (pen / である)：否定副詞の位置に連結動詞が入り文法上不自然",
			"ลง (long / 下りる)：否定副詞の位置に移動動詞が入り文法上不自然",
		},
	}
}

// 1回目はモデルを呼んで保存し、2回目はモデルを呼ばずにキャッシュから作る。
func TestClozeCacheHitSkipsModel(t *testing.T) {
	store := &fakeClozeStore{}
	inner := &countingClozeService{questions: []quizgen.GeneratedQuizQuestion{clozeQuestion()}}
	service := &clozeCachedQuizService{inner: inner, store: store, lang: lang.JA}

	first := service.GenerateQuizQuestions(context.Background(),
		[]quizgen.QuizSentenceSeed{clozeSeed()})
	if len(first) != 1 {
		t.Fatalf("1回目の問題数 %d, want 1", len(first))
	}
	if inner.calls != 1 || store.saves != 1 {
		t.Fatalf("1回目: モデル %d回 / 保存 %d回, want 1/1", inner.calls, store.saves)
	}

	second := service.GenerateQuizQuestions(context.Background(),
		[]quizgen.QuizSentenceSeed{clozeSeed()})
	if len(second) != 1 {
		t.Fatalf("2回目の問題数 %d, want 1", len(second))
	}
	if inner.calls != 1 {
		t.Errorf("2回目でモデルを呼んでいる（計 %d回）", inner.calls)
	}
	if second[0].Explanation != first[0].Explanation {
		t.Errorf("解説が変わっている: %q → %q", first[0].Explanation, second[0].Explanation)
	}
	if len(second[0].Choices) != 4 {
		t.Errorf("選択肢 %v", second[0].Choices)
	}
}

// キーは例文1つにつき1つ。ダミーが違っても同じキーで、言語が違えば別。
func TestClozeCacheKeyIsPerSentence(t *testing.T) {
	seed := clozeSeed()
	if quizClozeKey(lang.JA, seed.ThaiText) == "" {
		t.Fatal("キーを作れていない")
	}
	if quizClozeKey(lang.JA, seed.ThaiText) != quizClozeKey(lang.JA, seed.ThaiText+" ") {
		t.Error("前後の空白でキーが変わっている")
	}
	if quizClozeKey(lang.JA, seed.ThaiText) == quizClozeKey(lang.EN, seed.ThaiText) {
		t.Error("言語違いが同じキーになっている")
	}
	if quizClozeKey(lang.JA, "") != "" {
		t.Error("本文が空でもキーを作っている")
	}
}

// 保存済みの正解が今回の出題語と違えば、当てずに作り直す
// （空欄の位置が違う問題を返さないため）。
func TestClozeCacheMissesOnDifferentKeyWord(t *testing.T) {
	store := &fakeClozeStore{}
	inner := &countingClozeService{questions: []quizgen.GeneratedQuizQuestion{clozeQuestion()}}
	service := &clozeCachedQuizService{inner: inner, store: store, lang: lang.JA}
	seed := clozeSeed()

	key := quizClozeKey(lang.JA, seed.ThaiText)
	store.Save(context.Background(), key, quizClozeEntry{
		Lang:          string(lang.JA),
		ThaiText:      seed.ThaiText,
		CorrectAnswer: "ผม", // 別の語で登録されている
		Dummies:       []string{"คน", "เป็น", "ลง"},
		Explanation:   "別の問題の解説",
		DummyReasons:  clozeQuestion().DummyReasons,
	})

	service.GenerateQuizQuestions(context.Background(), []quizgen.QuizSentenceSeed{seed})
	if inner.calls != 1 {
		t.Errorf("作り直していない（モデル呼び出し %d回）", inner.calls)
	}
}

// 同じ文・同じ正解なら毎回同じダミーが選ばれる（キーが安定する）。
func TestPickDistractorsIsDeterministic(t *testing.T) {
	vocab := &stubVocab{
		ranks: map[string]int{"ไม่": 2, "คน": 30, "เป็น": 13, "ลง": 40, "แม่": 55, "วัน": 60},
		pos: map[string]string{
			"ไม่": "否定詞", "คน": "名詞", "เป็น": "助動詞",
			"ลง": "動詞", "แม่": "名詞", "วัน": "名詞",
		},
	}
	words := []string{"ผม", "ไม่", "ค่อย"}
	first := quizgen.PickDistractors(vocab, "ไม่", words, nil)
	if len(first) != quizgen.DistractorCount {
		t.Fatalf("選べた数 %d, want %d", len(first), quizgen.DistractorCount)
	}
	// 語の集合が変わらないことを見る（並びは候補の取り出し順で変わりうるが、
	// キャッシュキーは並べ替えてから作るので同一性には影響しない）。
	want := sortedCopy(first)
	for range 5 {
		again := sortedCopy(quizgen.PickDistractors(vocab, "ไม่", words, nil))
		if len(again) != len(want) {
			t.Fatalf("件数が変わる: %v → %v", want, again)
		}
		for i := range want {
			if want[i] != again[i] {
				t.Fatalf("引き直すと語が変わる: %v → %v", want, again)
			}
		}
	}

}

func sortedCopy(in []string) []string {
	out := append([]string(nil), in...)
	sort.Strings(out)
	return out
}

// stubVocab はランクと品詞を固定で返す。
type stubVocab struct {
	ranks map[string]int
	pos   map[string]string
}

func (v *stubVocab) Rank(word string) (int, bool) {
	rank, ok := v.ranks[word]
	return rank, ok
}

func (v *stubVocab) WordsInRange(low, high int) []string {
	var out []string
	for word, rank := range v.ranks {
		if low <= rank && rank <= high {
			out = append(out, word)
		}
	}
	return out
}

func (v *stubVocab) POS(word string) (string, bool)  { return v.pos[word], true }
func (v *stubVocab) IsFunctionWord(word string) bool { return false }
