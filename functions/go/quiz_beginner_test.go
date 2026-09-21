package function

import (
	"strings"
	"testing"

	"github.com/mnbst/thai-memo/functions/go/internal/lang"
	"github.com/mnbst/thai-memo/functions/go/internal/quizgen"
	"github.com/mnbst/thai-memo/functions/go/internal/spellunit"
)

func TestBeginnerQuizEnabled(t *testing.T) {
	cases := []struct {
		name     string
		vocab    any
		expected bool
	}{
		{"未受験は対象", nil, true},
		{"99は対象", int64(99), true},
		{"100は対象外", int64(100), false},
	}
	for _, c := range cases {
		userData := map[string]any{}
		if c.vocab != nil {
			userData["vocab_test_vocab"] = c.vocab
		}
		if got := beginnerQuizEnabled(userData); got != c.expected {
			t.Errorf("%s: %v", c.name, got)
		}
	}
}

// TestBeginnerFormatsNeedClientSupport は宣言していない形式に差し替えないこと。
func TestBeginnerFormatsNeedClientSupport(t *testing.T) {
	sources := spellingTestSources(t)
	if got := applyBeginnerFormats(
		sources, []string{quizgen.FormatClozeChoice}, lang.JA, nil); got != 0 {
		t.Errorf("旧クライアントに %d 問差し替えた", got)
	}
}

// spellingTestSources は綴り4択にできる生成元を5件ぶん作る。
func spellingTestSources(t *testing.T) []quizSeedSource {
	t.Helper()
	ix, err := spellunit.LoadIndex()
	if err != nil {
		t.Fatal(err)
	}
	words := []string{"ออก", "กิน", "รัก", "หมา", "ดี"}
	var sources []quizSeedSource
	for _, word := range words {
		if _, ok := ix.Lookup(word); !ok {
			continue
		}
		sources = append(sources, quizSeedSource{
			SentenceID: word,
			Seed: quizgen.QuizSentenceSeed{
				QuizFormat:           quizgen.FormatClozeChoice,
				ThaiText:             "ฉัน" + word,
				Words:                []string{"ฉัน", word},
				Pronunciation:        "chan " + word,
				JapaneseTranslation:  "私は" + word,
				KeyWord:              word,
				KeyWordPronunciation: "aan",
				KeyWordMeaning:       "意味",
			},
		})
	}
	if len(sources) == 0 {
		t.Skip("単音節として引ける語が無い")
	}
	return sources
}

// TestApplyBeginnerFormats は出題できる語が全部差し替わること、
// 差し替えた問題がモデル無しで組み立てられることを確かめる。
func TestApplyBeginnerFormats(t *testing.T) {
	sources := spellingTestSources(t)
	formats := []string{quizgen.FormatClozeChoice, quizgen.FormatSpellingChoice}

	applied := applyBeginnerFormats(sources, formats, lang.JA, nil)
	if applied != len(sources) {
		t.Fatalf("%d 問中 %d 問しか差し替わらなかった", len(sources), applied)
	}

	converted := 0
	for _, source := range sources {
		if source.Seed.QuizFormat != quizgen.FormatSpellingChoice {
			continue
		}
		converted++
		if len(source.Seed.FixedDummies) != 3 {
			t.Fatalf("ダミーが %d 件", len(source.Seed.FixedDummies))
		}
		if !strings.Contains(source.Seed.FixedExplanation, source.Seed.KeyWord) {
			t.Errorf("解説に正解が入っていない: %q", source.Seed.FixedExplanation)
		}
		question, ok := quizgen.BuildSpellingQuestion(source.Seed)
		if !ok {
			t.Fatal("綴り4択を組み立てられない")
		}
		if len(question.Choices) != 4 {
			t.Fatalf("選択肢が %d 件", len(question.Choices))
		}
		if len(question.ChoicePronunciations) != 0 {
			t.Error("選択肢の発音を出してはいけない")
		}
		if question.CorrectAnswer != source.Seed.KeyWord {
			t.Errorf("正解が %q", question.CorrectAnswer)
		}
	}
	if converted != applied {
		t.Errorf("綴り4択が %d 問、差し替えたのは %d 問", converted, applied)
	}
}

// TestBeginnerFormatsSkipPassedWords は一度正解した語を綴り4択に戻さないこと。
func TestBeginnerFormatsSkipPassedWords(t *testing.T) {
	sources := spellingTestSources(t)
	formats := []string{quizgen.FormatClozeChoice, quizgen.FormatSpellingChoice}

	passed := map[string]map[string]bool{
		sources[0].Seed.KeyWord: {quizgen.FormatSpellingChoice: true},
	}
	applied := applyBeginnerFormats(sources, formats, lang.JA, passed)
	if applied != len(sources)-1 {
		t.Errorf("通過済みを除いて %d 問のはずが %d 問", len(sources)-1, applied)
	}
	if sources[0].Seed.QuizFormat != quizgen.FormatClozeChoice {
		t.Errorf("通過済みの語が %s になっている", sources[0].Seed.QuizFormat)
	}
}
