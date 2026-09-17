package gemini

import (
	"context"
	"encoding/json"
	"log"

	"github.com/mnbst/thai-memo/functions/go/internal/lang"
	"github.com/mnbst/thai-memo/functions/go/internal/quizgen"
)

// repairLanguage は言語がずれたフィールドだけ書き直させる。
//
// ずれていなければ何もしない。書き直しても直らなければそのフィールドを空にする。
// 解説が空でも出題は成り立つ（クイズ画面は解説が空なら正解語の情報に差し替える）。
// dummy_reasons が空のままなら Sanitizer が従来どおりその問題を落とす。
func (s *QuizService) repairLanguage(
	ctx context.Context, sentences []quizgen.QuizSentenceSeed,
	draft *quizgen.Draft,
) {
	fields := quizgen.DriftedFields(*draft, s.Lang)
	if len(fields) == 0 {
		return
	}
	log.Printf("gemini_quiz_language_drift model=%s lang=%s fields=%v", Model, s.Lang, fields)

	isMeaningChoice := len(sentences) == 1 &&
		sentences[0].QuizFormat == quizgen.FormatMeaningChoice
	body := buildRepairRequestBody(*draft, fields, s.Lang, isMeaningChoice)
	if text := s.post(ctx, body, sentences); text != "" {
		var repaired quizgen.Draft
		if err := json.Unmarshal([]byte(text), &repaired); err != nil {
			log.Printf("gemini_quiz_language_repair_failed model=%s error=%v", Model, err)
		} else {
			applyRepaired(draft, repaired, fields)
		}
	}

	remaining := quizgen.DriftedFields(*draft, s.Lang)
	if len(remaining) == 0 {
		return
	}
	log.Printf("gemini_quiz_language_repair_gave_up model=%s lang=%s fields=%v",
		Model, s.Lang, remaining)
	for _, field := range remaining {
		switch field {
		case quizgen.FieldExplanation:
			draft.Explanation = ""
		case quizgen.FieldDummyReasons:
			draft.DummyReasons = nil
		}
	}
}

// applyRepaired は書き直しを求めたフィールドだけ差し替える。
// dummy_reasons は行数が変わると選択肢と対応しなくなるので、揃うときだけ採る。
func applyRepaired(draft *quizgen.Draft, repaired quizgen.Draft, fields []string) {
	for _, field := range fields {
		switch field {
		case quizgen.FieldExplanation:
			if repaired.Explanation != "" {
				draft.Explanation = repaired.Explanation
			}
		case quizgen.FieldDummyReasons:
			if len(repaired.DummyReasons) == len(draft.DummyReasons) {
				draft.DummyReasons = repaired.DummyReasons
			}
		}
	}
}

// buildRepairRequestBody は書き直し用のリクエスト本文。
// レスポンススキーマは書き直させるフィールドだけに絞る。
func buildRepairRequestBody(
	draft quizgen.Draft, fields []string, l lang.Lang, isMeaningChoice bool,
) map[string]any {
	return map[string]any{
		"systemInstruction": map[string]any{
			"parts": []any{map[string]any{
				"text": quizgen.RepairSystemPrompt(fields, l),
			}},
		},
		"contents": []any{map[string]any{
			"role":  "user",
			"parts": []any{map[string]any{"text": quizgen.BuildRepairPrompt(draft, fields)}},
		}},
		"generationConfig": map[string]any{
			"responseMimeType": "application/json",
			"responseSchema":   repairSchema(l, fields, isMeaningChoice),
			"maxOutputTokens":  maxOutputTokens,
			"thinkingConfig": map[string]any{
				"thinkingBudget": thinkingBudget,
			},
		},
	}
}

// repairSchema は通常のスキーマから、書き直させるフィールドだけ抜き出す。
// description（＝出力言語の指定）を本番と同じものに保つため、組み直さない。
func repairSchema(l lang.Lang, fields []string, isMeaningChoice bool) map[string]any {
	full := responseSchema(l, isMeaningChoice, true)
	properties, _ := full["properties"].(map[string]any)

	picked := map[string]any{}
	required := make([]any, 0, len(fields))
	for _, field := range fields {
		if property, ok := properties[field]; ok {
			picked[field] = property
			required = append(required, field)
		}
	}
	return map[string]any{
		"type":       "object",
		"properties": picked,
		"required":   required,
	}
}
