package quizgen

import (
	"reflect"
	"testing"
)

// 意味4択は選択肢・正解をルールベースで確定させ、モデルには触らせない。
func TestApplyRuleBasedFieldsKeepsMeaningChoices(t *testing.T) {
	seed := QuizSentenceSeed{
		QuizFormat:           FormatMeaningChoice,
		ThaiText:             "ฉันชอบภาษาไทย",
		Words:                []string{"ฉัน", "ชอบ", "ภาษาไทย"},
		Pronunciation:        "chan chop phasa thai",
		JapaneseTranslation:  "私はタイ語が好きです",
		KeyWord:              "ภาษาไทย",
		KeyWordPronunciation: "phasa thai",
		KeyWordMeaning:       "タイ語",
		MeaningChoices:       []string{"タイ語", "私", "好き", "勉強する"},
	}
	if !IsSeedReady(seed) {
		t.Fatal("意味4択の seed が未準備と判定された")
	}

	applied := ApplyRuleBasedFields(
		[]Draft{{Explanation: "ภาษาไทย は言語名を表す名詞。"}},
		[]QuizSentenceSeed{seed},
	)
	if len(applied) != 1 || applied[0].QuizFormat != FormatMeaningChoice {
		t.Fatalf("applied = %#v", applied)
	}
	if want := seed.MeaningChoices; !reflect.DeepEqual(applied[0].Choices, want) {
		t.Fatalf("choices = %v, want %v", applied[0].Choices, want)
	}
	if applied[0].CorrectAnswer != "ภาษาไทย" ||
		applied[0].CorrectAnswerMeaning != "タイ語" {
		t.Fatalf("correct = %q / %q",
			applied[0].CorrectAnswer, applied[0].CorrectAnswerMeaning)
	}
}

// 4件揃わない、正解が選択肢に無いものは意味問題として使えない。
func TestIsSeedReadyRejectsBrokenMeaningChoices(t *testing.T) {
	base := QuizSentenceSeed{
		QuizFormat:           FormatMeaningChoice,
		ThaiText:             "ฉันชอบภาษาไทย",
		Words:                []string{"ฉัน", "ชอบ", "ภาษาไทย"},
		KeyWord:              "ภาษาไทย",
		KeyWordPronunciation: "phasa thai",
		KeyWordMeaning:       "タイ語",
	}

	short := base
	short.MeaningChoices = []string{"タイ語", "私", "好き"}
	if IsSeedReady(short) {
		t.Fatal("選択肢3件を通してしまった")
	}

	missing := base
	missing.MeaningChoices = []string{"私", "好き", "勉強する", "本"}
	if IsSeedReady(missing) {
		t.Fatal("正解を含まない選択肢を通してしまった")
	}
}

// Sanitizer は意味4択の誤答理由・選択肢発音を出さない。
func TestSanitizerMeaningQuestionDropsDummyReasons(t *testing.T) {
	s := &Sanitizer{Shuffle: func(c []string) []string { return c }}
	out, ok := s.Question(GeneratedQuizQuestion{
		QuizFormat:           FormatMeaningChoice,
		ThaiText:             "ฉันชอบภาษาไทย",
		CorrectAnswer:        "ภาษาไทย",
		CorrectAnswerMeaning: "タイ語",
		Choices:              []string{"タイ語", "私", "好き", "勉強する"},
		DummyReasons:         []string{"a", "b", "c"},
	})
	if !ok {
		t.Fatal("意味4択が落とされた")
	}
	if len(out.DummyReasons) != 0 || len(out.ChoicePronunciations) != 0 {
		t.Fatalf("out = %#v", out)
	}
	if len(out.Choices) != 4 {
		t.Fatalf("choices = %v", out.Choices)
	}
}

// 正解が選択肢に無い、非タイ語の正解は落とす。
func TestSanitizerMeaningQuestionRejectsInvalid(t *testing.T) {
	s := &Sanitizer{Shuffle: func(c []string) []string { return c }}
	if _, ok := s.Question(GeneratedQuizQuestion{
		QuizFormat:           FormatMeaningChoice,
		CorrectAnswer:        "ภาษาไทย",
		CorrectAnswerMeaning: "タイ語",
		Choices:              []string{"私", "好き", "勉強する", "本"},
	}); ok {
		t.Fatal("正解を含まない選択肢を通してしまった")
	}
	if _, ok := s.Question(GeneratedQuizQuestion{
		QuizFormat:           FormatMeaningChoice,
		CorrectAnswer:        "thai",
		CorrectAnswerMeaning: "タイ語",
		Choices:              []string{"タイ語", "私", "好き", "勉強する"},
	}); ok {
		t.Fatal("非タイ語の正解を通してしまった")
	}
}
