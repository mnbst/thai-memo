package gemini

import "github.com/mnbst/thai-memo/functions/go/internal/lang"

// responseSchema は Gemini の responseSchema。
//
// JS 版は OpenAI 用スキーマから additionalProperties を落として渡していた
// （toGeminiSchema）。Go 版は最初から Gemini 用の形で持つ。
//
// 出力フィールドの言語はスキーマの description で決まる。Python 側の実測
// （functions/python/prompts.py の不採用コメント）で、プロンプト本文に言語指定を
// 足しても効果が無く、description だけで足りることを確認している。
// 構造・フィールド名は ja / en で同一。
func responseSchema(l lang.Lang, isMeaningChoice, hasFixedDummies bool) map[string]any {
	if isMeaningChoice {
		explanation := "Concise Japanese explanation of the target word itself, at most 140 Japanese characters; do not explain the source sentence, discuss wrong choices, or add examples"
		if l == lang.EN {
			explanation = "Concise English explanation of the target word itself, at most 80 words; do not explain the source sentence, discuss wrong choices, or add examples"
		}
		return map[string]any{
			"type": "object",
			"properties": map[string]any{
				"explanation": map[string]any{
					"type":        "string",
					"description": explanation,
				},
			},
			"required": []any{"explanation"},
		}
	}

	explanation := "Brief explanation in Japanese of why this word fits"
	dummyReasons := "不正解の3単語それぞれについて入らない理由を日本語で1行ずつ"
	dummies := "Exactly 3 Thai dummy choices that do not include the correct answer"
	if l == lang.EN {
		explanation = "Brief explanation in English of why this word fits"
		dummyReasons = "One line in English per wrong choice, explaining why it does not fit"
	}
	properties := map[string]any{
		"explanation": map[string]any{
			"type":        "string",
			"description": explanation,
		},
		"dummy_reasons": map[string]any{
			"type":        "array",
			"items":       map[string]any{"type": "string"},
			"description": dummyReasons,
		},
	}
	required := []any{"explanation", "dummy_reasons"}

	// ダミーが確定している問題では dummies を返させない。返させると、
	// 使わない語を考えるぶんの出力と、渡した語を書き換える余地が残る
	// （書き換えられると dummy_reasons が選択肢と対応しなくなる）。
	if !hasFixedDummies {
		properties["dummies"] = map[string]any{
			"type":        "array",
			"items":       map[string]any{"type": "string"},
			"description": dummies,
		}
		required = append([]any{"dummies"}, required...)
	}
	return map[string]any{
		"type":       "object",
		"properties": properties,
		"required":   required,
	}
}
