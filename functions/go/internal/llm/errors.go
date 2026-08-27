// Package llm は LLM プロバイダー（OpenAI / Gemini）の抽象レイヤ。
// functions/python/llm_providers.py の移植。
//
// 公開するのは GenerateSentence だけ。呼び出し側はどちらのプロバイダーを
// 使うか意識せず、RESPONSE_JSON_SCHEMA 準拠の map を受け取る。
// NLP の後処理は呼び出し側（internal/sentence）の担当。
package llm

import "fmt"

// transientStatus は再送する HTTP ステータス。
var transientStatus = map[int]bool{
	408: true, 429: true, 500: true, 502: true, 503: true, 504: true,
}

// APIError は LLM API が返したエラー。Python の LLMApiError。
//
// StatusCode が 0 はネットワーク層の失敗（タイムアウト・接続不能）を表す。
// Python では None。どちらも一過性として再送する。
type APIError struct {
	StatusCode int
	Message    string
	Provider   string
}

// IsTransient は再送する価値があるか。
func (e *APIError) IsTransient() bool {
	return e.StatusCode == 0 || transientStatus[e.StatusCode]
}

func (e *APIError) Error() string {
	status := "network"
	if e.StatusCode != 0 {
		status = fmt.Sprintf("%d", e.StatusCode)
	}
	return fmt.Sprintf("%s API error status=%s: %s", e.Provider, status, e.Message)
}
