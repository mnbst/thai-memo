package llm

import "fmt"

// GeminiAPIBase は Generative Language API のベース URL。
const GeminiAPIBase = "https://generativelanguage.googleapis.com/v1beta"

// GeminiPricing はモデルごとの単価（100万トークンあたり USD）。
// https://ai.google.dev/pricing
//
// Gemini はキャッシュ済み入力の区別をしないので CachedInput は使わない。
var GeminiPricing = map[string]Pricing{
	"gemini-2.5-flash":      {Input: 0.30, Output: 2.50},
	"gemini-2.5-flash-lite": {Input: 0.10, Output: 0.40},
	"gemini-2.5-pro":        {Input: 1.25, Output: 10.00},
	"gemini-3.1-flash-lite": {Input: 0.25, Output: 1.50},
	"gemini-3.5-flash-lite": {Input: 0.30, Output: 2.50},
	"gemini-3-flash":        {Input: 0.50, Output: 3.00},
	"gemini-3.5-flash":      {Input: 1.50, Output: 9.00},
}

var defaultGeminiPricing = GeminiPricing["gemini-3.1-flash-lite"]

// GeminiSchema は Gemini 用にレスポンススキーマを変換する。
// Gemini は additionalProperties を受け付けないため取り除く。
func GeminiSchema(schema any) any {
	switch node := schema.(type) {
	case map[string]any:
		out := make(map[string]any, len(node))
		for k, v := range node {
			if k == "additionalProperties" {
				continue
			}
			out[k] = GeminiSchema(v)
		}
		return out
	case []any:
		out := make([]any, len(node))
		for i, v := range node {
			out[i] = GeminiSchema(v)
		}
		return out
	default:
		return schema
	}
}

// GeminiThinkingBudget は tier ごとの thinkingBudget の既定値。
func GeminiThinkingBudget(isPremium bool) int {
	if isPremium {
		return 1024
	}
	return 256
}

// GeminiPayload は generateContent へ送る本文を組み立てる。
//
// google-genai SDK は使わない。SDK の import は aiohttp / pydantic まで
// 引き連れており、Cloud Run のイメージ遅延ロードと相まってコールドスタート時に
// 実測9秒かかっていた（2026-07-31 dev計測）。OpenAI 側と同じく素の HTTP で叩く。
func GeminiPayload(systemPrompt, userPrompt string, maxTokens, thinkingBudget int, schema map[string]any) map[string]any {
	return map[string]any{
		"contents": []any{map[string]any{
			"role":  "user",
			"parts": []any{map[string]any{"text": userPrompt}},
		}},
		"systemInstruction": map[string]any{
			"parts": []any{map[string]any{"text": systemPrompt}},
		},
		"generationConfig": map[string]any{
			"responseMimeType": "application/json",
			"responseSchema":   GeminiSchema(schema),
			"maxOutputTokens":  maxTokens,
			"thinkingConfig":   map[string]any{"thinkingBudget": thinkingBudget},
		},
	}
}

// GeminiUsage は usageMetadata。値が無ければ 0。
type GeminiUsage struct {
	PromptTokenCount     int
	CandidatesTokenCount int
	ThoughtsTokenCount   int
	TotalTokenCount      int
}

// GeminiExtract はレスポンス本文から出力テキストと使用量を取り出す。
// テキストは全 candidate の全 part を連結したもの。
func GeminiExtract(body map[string]any) (string, GeminiUsage) {
	var text string
	candidates, _ := body["candidates"].([]any)
	for _, c := range candidates {
		cobj, ok := c.(map[string]any)
		if !ok {
			continue
		}
		content, _ := cobj["content"].(map[string]any)
		parts, _ := content["parts"].([]any)
		for _, p := range parts {
			pobj, ok := p.(map[string]any)
			if !ok {
				continue
			}
			if s, ok := pobj["text"].(string); ok {
				text += s
			}
		}
	}

	raw, _ := body["usageMetadata"].(map[string]any)
	usage := GeminiUsage{
		PromptTokenCount:     pyInt(raw["promptTokenCount"]),
		CandidatesTokenCount: pyInt(raw["candidatesTokenCount"]),
		ThoughtsTokenCount:   pyInt(raw["thoughtsTokenCount"]),
		TotalTokenCount:      pyInt(raw["totalTokenCount"]),
	}
	return text, usage
}

// GeminiUsageLog はトークン使用量のログ行を組み立てる。
//
// 思考トークン（thoughts）は candidates とは別に返るが課金は出力扱いなので、
// 単価計算では合算する。
func GeminiUsageLog(usage GeminiUsage, tierLabel, model string) string {
	billedOutput := usage.CandidatesTokenCount + usage.ThoughtsTokenCount
	total := usage.TotalTokenCount
	if total == 0 {
		total = usage.PromptTokenCount + billedOutput
	}

	pricing, ok := GeminiPricing[model]
	if !ok {
		pricing = defaultGeminiPricing
	}
	// 積を float64() で明示的に丸めてから足す（FMA 融合を防ぐ）。openai.go を参照。
	costUSD := (float64(float64(usage.PromptTokenCount)*pricing.Input) +
		float64(float64(billedOutput)*pricing.Output)) / 1_000_000

	return fmt.Sprintf(
		"Gemini token usage (%s): model=%s, input=%d, "+
			"output=%d, thoughts=%d, billed_output=%d, total=%d, cost=$%.6f",
		tierLabel, model, usage.PromptTokenCount,
		usage.CandidatesTokenCount, usage.ThoughtsTokenCount,
		billedOutput, total, costUSD)
}
