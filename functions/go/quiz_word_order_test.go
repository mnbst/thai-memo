package function

import (
	"math/rand"
	"testing"

	"github.com/mnbst/thai-memo/functions/go/internal/lang"
	"github.com/mnbst/thai-memo/functions/go/internal/quizgen"
)

func wordOrderTestSource(keyWord string, words ...string) quizSeedSource {
	breakdown := make([]any, 0, len(words))
	text := ""
	for _, w := range words {
		text += w
		breakdown = append(breakdown, map[string]any{"word": w, "pronunciation": "p-" + w})
	}
	return quizSeedSource{
		Seed: quizgen.QuizSentenceSeed{
			QuizFormat: quizgen.FormatClozeChoice, ThaiText: text, KeyWord: keyWord,
		},
		SentenceID:     "s-" + keyWord,
		SentenceDetail: map[string]any{"word_breakdown": breakdown},
	}
}

func TestApplyWordOrderConvertsOneClozeOnly(t *testing.T) {
	spelling := wordOrderTestSource("ไป", "ผม", "อยาก", "ไป", "ทะเล", "ครับ")
	spelling.Seed.QuizFormat = quizgen.FormatSpellingChoice
	sources := []quizSeedSource{
		wordOrderTestSource("ทะเล", "ผม", "อยาก", "ไป", "ทะเล", "ครับ"),
		wordOrderTestSource("กิน", "ผม", "กิน", "ข้าว"), // 短くて作れない
		spelling,
		wordOrderTestSource("เพื่อน", "เขา", "เป็น", "เพื่อน", "ของ", "ฉัน"),
	}
	applied := applyWordOrder(sources, lang.JA, true, rand.New(rand.NewSource(1)))
	if applied != 1 {
		t.Fatalf("applied=%d", applied)
	}
	n := 0
	for _, s := range sources {
		if s.Seed.QuizFormat == quizgen.FormatWordOrder {
			n++
			if s.WordOrder == nil || !s.WordOrderShowPronunciation {
				t.Fatalf("並び替えの中身が無い %+v", s)
			}
		}
	}
	if n != 1 || sources[1].Seed.QuizFormat != quizgen.FormatClozeChoice ||
		sources[2].Seed.QuizFormat != quizgen.FormatSpellingChoice {
		t.Fatalf("変えてはいけない問題が変わった")
	}
}

func TestWordOrderQuestionSkipsModel(t *testing.T) {
	source, ok := toWordOrderSource(
		wordOrderTestSource("ทะเล", "ผม", "อยาก", "ไป", "ทะเล", "ครับ"),
		lang.JA, false, rand.New(rand.NewSource(1)))
	if !ok {
		t.Fatal("作れなかった")
	}
	// service が nil でも作れる＝モデルを呼ばない
	q := generateSingleQuizQuestion(t.Context(), nil, source, 0)
	if q == nil || q.QuizFormat != quizgen.FormatWordOrder ||
		len(q.Choices) != 4 || len(q.WordOrderAnswer) != 4 || q.CorrectAnswer != "ทะเล" {
		t.Fatalf("question=%+v", q)
	}
}
