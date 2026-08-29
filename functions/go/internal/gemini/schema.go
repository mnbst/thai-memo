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
func responseSchema(l lang.Lang) map[string]any {
	explanation := "Brief explanation in Japanese of why this word fits"
	dummyReasons := "不正解の3単語それぞれについて入らない理由を日本語で1行ずつ"
	if l == lang.EN {
		explanation = "Brief explanation in English of why this word fits"
		dummyReasons = "One line in English per wrong choice, explaining why it does not fit"
	}

	return map[string]any{
		"type": "object",
		"properties": map[string]any{
			"dummies": map[string]any{
				"type":        "array",
				"items":       map[string]any{"type": "string"},
				"description": "Exactly 3 Thai dummy choices that do not include the correct answer",
			},
			"explanation": map[string]any{
				"type":        "string",
				"description": explanation,
			},
			"dummy_reasons": map[string]any{
				"type":        "array",
				"items":       map[string]any{"type": "string"},
				"description": dummyReasons,
			},
		},
		"required": []any{"dummies", "explanation", "dummy_reasons"},
	}
}
