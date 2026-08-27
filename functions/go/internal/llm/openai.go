package llm

import (
	"fmt"
	"os"
	"strings"
)

// OpenAIResponsesURL は Responses API のエンドポイント。
const OpenAIResponsesURL = "https://api.openai.com/v1/responses"

// Pricing は 100万トークンあたりの単価（USD）。
type Pricing struct {
	Input       float64
	CachedInput float64
	Output      float64
}

// OpenAIPricing はモデルごとの単価。
var OpenAIPricing = map[string]Pricing{
	"gpt-5.6-luna": {Input: 0.20, CachedInput: 0.02, Output: 1.20},
	"gpt-5.4-mini": {Input: 0.75, CachedInput: 0.075, Output: 4.50},
	"gpt-5.4-nano": {Input: 0.20, CachedInput: 0.02, Output: 1.25},
	"gpt-5-mini":   {Input: 0.25, CachedInput: 0.025, Output: 2.00},
	"gpt-5-nano":   {Input: 0.05, CachedInput: 0.005, Output: 0.40},
}

// defaultOpenAIPricing は表に無いモデルの単価。
var defaultOpenAIPricing = OpenAIPricing["gpt-5.4-nano"]

// OpenAIReasoningEffort は reasoning.effort の値を決める。
//
// free/premium とも medium。high はレイテンシが暴れる（2026-08-05 実測、
// gpt-5.6-luna・20文並列: high 中央値10.5秒/p90 37秒/最大77秒、
// medium 中央値6.0秒/p90 9.3秒/最大16.4秒）。high は 28件中1件が74秒かけて
// empty output になり、リトライでさらに倍のレイテンシになる。
// 品質は medium でも文体遵守・訳文・多義語の使い分けが維持されることを確認済み
// （落ちるのは none。none では ถูก が全て「安い」になる）。
//
// 検証時に効きを比べられるよう環境変数で上書き可（none/low/medium/high）。
func OpenAIReasoningEffort(model string) string {
	if override := os.Getenv("OPENAI_REASONING_EFFORT"); override != "" {
		return override
	}
	if strings.HasPrefix(model, "gpt-5") {
		return "medium"
	}
	return "none"
}

// OpenAIPayload は Responses API へ送る本文を組み立てる。
//
// systemPrompt は呼び出しごとに変化しない固定テキストで、instructions として
// 渡すことで prefix キャッシュに乗る。
func OpenAIPayload(model, systemPrompt, userPrompt string, maxTokens int, schema map[string]any) map[string]any {
	return map[string]any{
		"model":             model,
		"instructions":      systemPrompt,
		"input":             []any{map[string]any{"role": "user", "content": userPrompt}},
		"max_output_tokens": maxTokens,
		"reasoning":         map[string]any{"effort": OpenAIReasoningEffort(model)},
		"text": map[string]any{
			"format": map[string]any{
				"type":   "json_schema",
				"name":   "thai_sentence_response",
				"strict": true,
				"schema": schema,
			},
		},
	}
}

// OpenAIExtractText はレスポンスから本文を取り出す。空なら "" を返す。
//
// output_text があればそれを使い、無ければ output[].content[].text を全て連結する。
func OpenAIExtractText(body map[string]any) string {
	if s, ok := body["output_text"].(string); ok && trimSpace(s) != "" {
		return trimSpace(s)
	}

	var parts []string
	output, _ := body["output"].([]any)
	for _, item := range output {
		obj, ok := item.(map[string]any)
		if !ok {
			continue
		}
		content, ok := obj["content"].([]any)
		if !ok {
			continue
		}
		for _, c := range content {
			cobj, ok := c.(map[string]any)
			if !ok {
				continue
			}
			if text, ok := cobj["text"].(string); ok {
				parts = append(parts, text)
			}
		}
	}
	return trimSpace(strings.Join(parts, ""))
}

// OpenAIUsageLog はトークン使用量のログ行を組み立てる。
// usage が無ければ "" を返す（Python 版はログを出さない）。
//
// キャッシュ済み入力トークンは別単価なので、入力から差し引いて計算する。
func OpenAIUsageLog(usage map[string]any, tierLabel, model string) string {
	if len(usage) == 0 {
		return ""
	}

	inputTokens := pyInt(usage["input_tokens"])
	outputTokens := pyInt(usage["output_tokens"])

	cachedTokens := 0
	if d, ok := usage["input_tokens_details"].(map[string]any); ok {
		cachedTokens = pyInt(d["cached_tokens"])
	}
	reasoningTokens := 0
	if d, ok := usage["output_tokens_details"].(map[string]any); ok {
		reasoningTokens = pyInt(d["reasoning_tokens"])
	}

	totalTokens := pyInt(usage["total_tokens"])
	if totalTokens == 0 {
		totalTokens = inputTokens + outputTokens
	}

	pricing, ok := OpenAIPricing[model]
	if !ok {
		pricing = defaultOpenAIPricing
	}
	uncachedInput := inputTokens - cachedTokens
	if uncachedInput < 0 {
		uncachedInput = 0
	}
	// 積を float64() で明示的に丸めてから足す。Go は a*b+c を FMA 1 命令に
	// 融合してよいことになっており、融合すると中間の丸めが消えて Python と
	// 単価の下 6 桁がずれる（実測: $0.021399 と $0.021400）。
	costUSD := (float64(float64(uncachedInput)*pricing.Input) +
		float64(float64(cachedTokens)*pricing.CachedInput) +
		float64(float64(outputTokens)*pricing.Output)) / 1_000_000

	return fmt.Sprintf(
		"OpenAI token usage (%s): model=%s, input=%d (cached=%d), "+
			"output=%d, reasoning=%d, total=%d, cost=$%.6f",
		tierLabel, model, inputTokens, cachedTokens,
		outputTokens, reasoningTokens, totalTokens, costUSD)
}
