package llm

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"math"
	"math/rand"
	"net/http"
	"time"

	"github.com/mnbst/thai-memo/functions/go/internal/pystr"
)

// requestTimeout は 1 回の API 呼び出しの上限。
const requestTimeout = 90 * time.Second

const (
	maxRetries = 3
	baseDelay  = 2 * time.Second
)

// Client は LLM を呼び出す。ゼロ値でも使えるが、キーの取得元だけは必須。
type Client struct {
	// OpenAIKey / GeminiKey は呼び出し側が Secret Manager から解決して渡す。
	OpenAIKey string
	GeminiKey string

	// Provider は "openai" か "gemini"。premium のときだけ効く。
	Provider string
	// MaxTokens は max_output_tokens。
	MaxTokens int

	// Models はモデル名。
	OpenAIModel        string
	OpenAIModelPremium string
	GeminiModel        string
	GeminiModelPremium string

	// HTTP は差し替え用。nil なら requestTimeout 付きのクライアント。
	HTTP *http.Client
	// OpenAIURL / GeminiBase は差し替え用。空なら本番エンドポイント。
	OpenAIURL  string
	GeminiBase string
	// Sleep は差し替え用。nil なら ctx を尊重した実時間の待機。
	Sleep func(ctx context.Context, d time.Duration) error
}

func (c *Client) httpClient() *http.Client {
	if c.HTTP != nil {
		return c.HTTP
	}
	return &http.Client{Timeout: requestTimeout}
}

func (c *Client) openAIURL() string {
	if c.OpenAIURL != "" {
		return c.OpenAIURL
	}
	return OpenAIResponsesURL
}

func (c *Client) geminiBase() string {
	if c.GeminiBase != "" {
		return c.GeminiBase
	}
	return GeminiAPIBase
}

// GenerateSentence は設定されたプロバイダーで例文を生成し、構造化 map を返す。
//
// free ティアは常に Gemini。premium は Provider に従う。
// 2026-08-05 に free も OpenAI へ寄せたが、同日この形へ差し戻した。
func (c *Client) GenerateSentence(
	ctx context.Context, systemPrompt, userPrompt string,
	isPremium bool, tierLabel string, schema map[string]any,
) (map[string]any, error) {
	if !isPremium || c.Provider == "gemini" {
		return c.geminiGenerate(ctx, systemPrompt, userPrompt, isPremium, tierLabel, schema)
	}
	return c.openAIGenerate(ctx, systemPrompt, userPrompt, isPremium, tierLabel, schema)
}

func (c *Client) openAIGenerate(
	ctx context.Context, systemPrompt, userPrompt string,
	isPremium bool, tierLabel string, schema map[string]any,
) (map[string]any, error) {
	model := c.OpenAIModel
	if isPremium {
		model = c.OpenAIModelPremium
	}
	payload := OpenAIPayload(model, systemPrompt, userPrompt, c.MaxTokens, schema)

	body, err := c.callWithRetry(ctx, tierLabel, "OpenAI", func() (map[string]any, error) {
		return c.post(ctx, c.openAIURL(), map[string]string{
			"Authorization": "Bearer " + c.OpenAIKey,
		}, payload, "OpenAI")
	})
	if err != nil {
		return nil, err
	}

	if line := OpenAIUsageLog(mapOf(body["usage"]), tierLabel, model); line != "" {
		log.Print(line)
	}
	text := OpenAIExtractText(body)
	if text == "" {
		return nil, errors.New("LLM_API_ERROR: empty output")
	}
	return ParseJSONText(text)
}

func (c *Client) geminiGenerate(
	ctx context.Context, systemPrompt, userPrompt string,
	isPremium bool, tierLabel string, schema map[string]any,
) (map[string]any, error) {
	model := c.GeminiModel
	if isPremium {
		model = c.GeminiModelPremium
	}
	payload := GeminiPayload(systemPrompt, userPrompt, c.MaxTokens,
		GeminiThinkingBudget(isPremium), schema)
	url := fmt.Sprintf("%s/models/%s:generateContent", c.geminiBase(), model)

	body, err := c.callWithRetry(ctx, tierLabel, "Gemini", func() (map[string]any, error) {
		return c.post(ctx, url, map[string]string{
			"x-goog-api-key": c.GeminiKey,
		}, payload, "Gemini")
	})
	if err != nil {
		return nil, err
	}

	text, usage := GeminiExtract(body)
	log.Print(GeminiUsageLog(usage, tierLabel, model))
	if pystr.TrimSpace(text) == "" {
		return nil, errors.New("LLM_API_ERROR: empty output")
	}
	return ParseJSONText(text)
}

// post は JSON を POST してレスポンスを map で返す。
//
// HTTP エラーとネットワーク障害は *APIError（再送対象になりうる）、
// 壊れたレスポンスは通常の error（再送しても直らない）に分ける。
func (c *Client) post(
	ctx context.Context, url string, headers map[string]string,
	payload map[string]any, provider string,
) (map[string]any, error) {
	data, err := json.Marshal(payload)
	if err != nil {
		return nil, fmt.Errorf("LLM_API_ERROR: リクエストを組み立てられない: %w", err)
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(data))
	if err != nil {
		return nil, &APIError{Message: err.Error(), Provider: provider}
	}
	req.Header.Set("Content-Type", "application/json")
	for k, v := range headers {
		req.Header.Set(k, v)
	}

	res, err := c.httpClient().Do(req)
	if err != nil {
		return nil, &APIError{Message: err.Error(), Provider: provider}
	}
	defer res.Body.Close()

	raw, err := io.ReadAll(res.Body)
	if err != nil {
		return nil, &APIError{Message: err.Error(), Provider: provider}
	}

	if res.StatusCode < 200 || res.StatusCode >= 300 {
		return nil, &APIError{
			StatusCode: res.StatusCode,
			Message:    errorMessage(raw),
			Provider:   provider,
		}
	}

	var parsed any
	if err := json.Unmarshal(raw, &parsed); err != nil {
		return nil, errors.New("LLM_API_ERROR: invalid JSON response")
	}
	obj, ok := parsed.(map[string]any)
	if !ok {
		return nil, errors.New("LLM_API_ERROR: unexpected response shape")
	}
	return obj, nil
}

// errorMessage はエラーレスポンスから message を取り出す。
// 取れなければ "Request failed"。JSON として読めない本文はそのまま使う。
//
// Python 版は message が文字列以外（例: 数値のエラーコード）でも str() で
// 文字列化するが、ここでは文字列以外を「無い」とみなして既定文言にする。
// 実際に非文字列の message を返すプロバイダーは確認していない。
func errorMessage(raw []byte) string {
	msg := ""
	var parsed any
	if err := json.Unmarshal(raw, &parsed); err != nil {
		msg = string(raw)
	} else if obj, ok := parsed.(map[string]any); ok {
		if inner, ok := obj["error"].(map[string]any); ok {
			msg, _ = inner["message"].(string)
		}
	}
	if msg == "" {
		return "Request failed"
	}
	return msg
}

// callWithRetry は一過性のエラーを指数バックオフで再送する。
func (c *Client) callWithRetry(
	ctx context.Context, tierLabel, provider string,
	call func() (map[string]any, error),
) (map[string]any, error) {
	for attempt := 0; ; attempt++ {
		body, err := call()
		if err == nil {
			return body, nil
		}

		var apiErr *APIError
		if !errors.As(err, &apiErr) {
			// レスポンスが壊れているなど、再送しても直らない失敗。
			return nil, err
		}
		if !apiErr.IsTransient() || attempt == maxRetries {
			return nil, fmt.Errorf("LLM_API_ERROR: %s", apiErr)
		}

		delay := RetryDelay(attempt, rand.Float64())
		log.Printf("%s API transient error (%s, attempt %d/%d): %s. Retrying in %.1fs...",
			provider, tierLabel, attempt+1, maxRetries, apiErr, delay.Seconds())
		if err := c.sleep(ctx, delay); err != nil {
			return nil, err
		}
	}
}

// RetryDelay は attempt 回目（0 始まり）の待ち時間。
// 指数バックオフに 0〜1 秒のジッタを足して、同時に失敗した呼び出しが
// 揃って再送するのを防ぐ。
func RetryDelay(attempt int, jitter float64) time.Duration {
	seconds := baseDelay.Seconds()*math.Pow(2, float64(attempt)) + jitter
	// 切り捨てだと 16.999 秒が 16.998999999 秒になるので丸める。
	return time.Duration(math.Round(seconds * float64(time.Second)))
}

func (c *Client) sleep(ctx context.Context, d time.Duration) error {
	if c.Sleep != nil {
		return c.Sleep(ctx, d)
	}
	timer := time.NewTimer(d)
	defer timer.Stop()
	select {
	case <-ctx.Done():
		return ctx.Err()
	case <-timer.C:
		return nil
	}
}

// ParseJSONText は構造化出力の JSON テキストを map にする。
func ParseJSONText(text string) (map[string]any, error) {
	var parsed any
	if err := json.Unmarshal([]byte(text), &parsed); err != nil {
		return nil, errors.New("LLM_API_ERROR: invalid structured output")
	}
	obj, ok := parsed.(map[string]any)
	if !ok {
		return nil, errors.New("LLM_API_ERROR: unexpected structured output")
	}
	return obj, nil
}

func mapOf(v any) map[string]any {
	m, _ := v.(map[string]any)
	return m
}

// pyInt は Python の int(value or 0)。JSON の数値は float64 で来るので
// 0 方向へ切り捨てる。
func pyInt(v any) int {
	switch n := v.(type) {
	case float64:
		return int(n)
	case int:
		return n
	case json.Number:
		f, err := n.Float64()
		if err != nil {
			return 0
		}
		return int(f)
	default:
		return 0
	}
}

func trimSpace(s string) string { return pystr.TrimSpace(s) }
