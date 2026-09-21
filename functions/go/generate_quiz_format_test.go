package function

import (
	"reflect"
	"testing"

	"github.com/mnbst/thai-memo/functions/go/internal/quizgen"
	"github.com/mnbst/thai-memo/functions/go/internal/uvm"
)

func learningQuizPayload() map[string]any {
	return map[string]any{
		"sentence_id":            "sentence-1",
		"thai_text":              "ฉันชอบเรียนภาษาไทย",
		"pronunciation":          "chan chop rian phasa thai",
		"japanese_translation":   "私はタイ語を勉強するのが好きです",
		"key_word":               "เรียน",
		"key_word_pronunciation": "rian",
		"key_word_meaning":       "勉強する",
		"word_breakdown": []any{
			map[string]any{"word": "ฉัน", "meaning": "私"},
			map[string]any{"word": "ชอบ", "meaning": "好き"},
			map[string]any{"word": "เรียน", "meaning": "勉強する"},
			map[string]any{"word": "ภาษาไทย", "meaning": "タイ語"},
		},
	}
}

// 対応を宣言したクライアントの確認クイズだけが意味4択になる。
func TestBuildLearningQuizSourceForClientMeaningChoice(t *testing.T) {
	meaning, ok := buildLearningQuizSourceForClient(learningQuizPayload(), true, nil)
	if !ok {
		t.Fatal("意味4択の生成元を作れなかった")
	}
	if meaning.Seed.QuizFormat != quizgen.FormatMeaningChoice {
		t.Fatalf("format = %q", meaning.Seed.QuizFormat)
	}
	if len(meaning.Seed.MeaningChoices) != 4 {
		t.Fatalf("choices = %v", meaning.Seed.MeaningChoices)
	}
	if meaning.Seed.MeaningChoices[0] != "勉強する" {
		t.Fatalf("正解が先頭にない: %v", meaning.Seed.MeaningChoices)
	}
	if !quizgen.IsSeedReady(meaning.Seed) {
		t.Fatalf("seed が未準備: %#v", meaning.Seed)
	}

	// 未宣言（1.4.8以前）は従来の穴埋めのまま。
	oldClient, ok := buildLearningQuizSourceForClient(learningQuizPayload(), false, nil)
	if !ok {
		t.Fatal("穴埋めの生成元を作れなかった")
	}
	if oldClient.Seed.QuizFormat != quizgen.FormatClozeChoice ||
		len(oldClient.Seed.MeaningChoices) != 0 {
		t.Fatalf("old client seed = %#v", oldClient.Seed)
	}
}

// 意味の重複・欠落で4件揃わない例文は穴埋めへ落とす。
// 例文が短くて選択肢が埋まらないときは、語彙テストの出題語の訳で4件に足す。
func TestBuildLearningQuizSourceForClientTopsUpChoices(t *testing.T) {
	payload := learningQuizPayload()
	payload["word_breakdown"] = []any{
		map[string]any{"word": "ไม่", "meaning": "〜ない（否定）"},
		map[string]any{"word": "เรียน", "meaning": "勉強する"},
	}
	payload["key_word"] = "เรียน"
	payload["key_word_meaning"] = "勉強する"
	payload["thai_text"] = "ไม่เรียน"

	pool := []uvm.TestItem{
		{Word: "ไม่", Rank: 2, Gloss: "いいえ"},   // 例文に出る語なので使わない
		{Word: "เรียน", Rank: 50, Gloss: "学ぶ"}, // 出題語そのものも使わない
		{Word: "คุณ", Rank: 4, Gloss: "あなた"},
		{Word: "ที่", Rank: 5, Gloss: "場所"},
		{Word: "มัน", Rank: 8, Gloss: "それ"},
	}
	source, ok := buildLearningQuizSourceForClient(
		payload, true, func() []uvm.TestItem { return pool })
	if !ok {
		t.Fatal("生成元を作れなかった")
	}
	if source.Seed.QuizFormat != quizgen.FormatMeaningChoice {
		t.Fatalf("format = %q", source.Seed.QuizFormat)
	}
	choices := source.Seed.MeaningChoices
	if len(choices) != 4 {
		t.Fatalf("choices = %v, want 4件", choices)
	}
	if choices[0] != "勉強する" {
		t.Fatalf("正解が先頭にない: %v", choices)
	}
	for _, banned := range []string{"いいえ", "学ぶ"} {
		for _, c := range choices {
			if c == banned {
				t.Errorf("例文の語・出題語と同じ語の訳を混ぜた: %q in %v", banned, choices)
			}
		}
	}
}

// 選択肢が4件揃わない例文は、穴埋めに落とさず択を減らして意味当てにする。
func TestBuildLearningQuizSourceForClientReducesChoices(t *testing.T) {
	payload := learningQuizPayload()
	payload["word_breakdown"] = []any{
		map[string]any{"word": "ฉัน", "meaning": "私"},
		map[string]any{"word": "ชอบ", "meaning": "私"},
		map[string]any{"word": "เรียน", "meaning": "勉強する"},
	}

	// 補充元が無ければ択を減らす。
	source, ok := buildLearningQuizSourceForClient(payload, true, nil)
	if !ok {
		t.Fatal("生成元を作れなかった")
	}
	if source.Seed.QuizFormat != quizgen.FormatMeaningChoice {
		t.Fatalf("format = %q, want meaning", source.Seed.QuizFormat)
	}
	if len(source.Seed.MeaningChoices) != 2 {
		t.Fatalf("choices = %v, want 2件", source.Seed.MeaningChoices)
	}
	if source.Seed.MeaningChoices[0] != "勉強する" {
		t.Fatalf("正解が先頭にない: %v", source.Seed.MeaningChoices)
	}
}

// ダミーを1件も作れない例文だけは穴埋めに戻す。
func TestBuildLearningQuizSourceForClientFallsBackToCloze(t *testing.T) {
	payload := learningQuizPayload()
	payload["word_breakdown"] = []any{
		map[string]any{"word": "ฉัน", "meaning": "勉強する"},
		map[string]any{"word": "เรียน", "meaning": "勉強する"},
	}

	source, ok := buildLearningQuizSourceForClient(payload, true, nil)
	if !ok {
		t.Fatal("生成元を作れなかった")
	}
	if source.Seed.QuizFormat != quizgen.FormatClozeChoice {
		t.Fatalf("format = %q, want cloze", source.Seed.QuizFormat)
	}
}

// まとめクイズは対応宣言に関係なく全問穴埋め。
func TestSelectedSentenceSeedStaysCloze(t *testing.T) {
	source := toQuizSeedSourceFromSelected(selectedSentence{
		ID:   "sentence-1",
		Data: learningQuizPayload(),
	})
	if source.Seed.QuizFormat != quizgen.FormatClozeChoice {
		t.Fatalf("format = %q, want cloze", source.Seed.QuizFormat)
	}
}

func TestSupportsQuizFormat(t *testing.T) {
	if supportsQuizFormat(nil, quizgen.FormatMeaningChoice) {
		t.Fatal("未宣言を対応扱いにした")
	}
	if !supportsQuizFormat(
		[]string{quizgen.FormatClozeChoice, quizgen.FormatMeaningChoice},
		quizgen.FormatMeaningChoice,
	) {
		t.Fatal("meaning_choice 宣言を認識しなかった")
	}
}

// 意味4択の問題は選択肢をそのままクライアントへ渡す。
func TestToQuizQuestionKeepsMeaningFormat(t *testing.T) {
	source, _ := buildLearningQuizSourceForClient(learningQuizPayload(), true, nil)
	choices := append([]string(nil), source.Seed.MeaningChoices...)
	q := toQuizQuestion(quizgen.GeneratedQuizQuestion{
		QuizFormat:           quizgen.FormatMeaningChoice,
		ThaiText:             source.Seed.ThaiText,
		CorrectAnswer:        source.Seed.KeyWord,
		CorrectAnswerMeaning: source.Seed.KeyWordMeaning,
		Choices:              choices,
	}, source)
	if q.QuizFormat != quizgen.FormatMeaningChoice {
		t.Fatalf("quiz_format = %q", q.QuizFormat)
	}
	if !reflect.DeepEqual(q.Choices, choices) {
		t.Fatalf("choices = %v, want %v", q.Choices, choices)
	}
}
