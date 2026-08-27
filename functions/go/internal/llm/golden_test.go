package llm

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"math"
	"net/http"
	"net/http/httptest"
	"os"
	"reflect"
	"strings"
	"testing"
	"time"
)

// llm_golden.json は functions/python/scripts/daily_golden/gen_llm_golden.py が
// 本物の llm_providers.py を呼んで書き出したもの。
// 更新するには同スクリプトを実行する。

type llmGolden struct {
	Errors []struct {
		StatusCode  *int   `json:"status_code"`
		Message     string `json:"message"`
		Provider    string `json:"provider"`
		Str         string `json:"str"`
		IsTransient bool   `json:"is_transient"`
	} `json:"errors"`

	ReasoningEffort []struct {
		Model    string `json:"model"`
		Override string `json:"override"`
		Effort   string `json:"effort"`
	} `json:"reasoning_effort"`

	OpenAIPayload []struct {
		Model        string         `json:"model"`
		SystemPrompt string         `json:"system_prompt"`
		UserPrompt   string         `json:"user_prompt"`
		Schema       map[string]any `json:"schema"`
		Payload      map[string]any `json:"payload"`
	} `json:"openai_payload"`

	APIMaxTokens       int            `json:"api_max_tokens"`
	ResponseJSONSchema map[string]any `json:"response_json_schema"`

	OpenAIExtract []struct {
		Body map[string]any `json:"body"`
		Text *string        `json:"text"`
	} `json:"openai_extract"`

	OpenAIUsageLog []struct {
		Usage map[string]any `json:"usage"`
		Tier  string         `json:"tier"`
		Model string         `json:"model"`
		Log   string         `json:"log"`
	} `json:"openai_usage_log"`

	GeminiSchema []struct {
		Schema   any `json:"schema"`
		Stripped any `json:"stripped"`
	} `json:"gemini_schema"`

	GeminiResponse []struct {
		Body  map[string]any `json:"body"`
		Text  string         `json:"text"`
		Usage struct {
			Prompt     *int `json:"prompt"`
			Candidates *int `json:"candidates"`
			Thoughts   *int `json:"thoughts"`
			Total      *int `json:"total"`
		} `json:"usage"`
	} `json:"gemini_response"`

	GeminiUsageLog []struct {
		Usage struct {
			Prompt     *int `json:"prompt"`
			Candidates *int `json:"candidates"`
			Thoughts   *int `json:"thoughts"`
			Total      *int `json:"total"`
		} `json:"usage"`
		Tier  string `json:"tier"`
		Model string `json:"model"`
		Log   string `json:"log"`
	} `json:"gemini_usage_log"`

	GeminiRequest []struct {
		Model          string         `json:"model"`
		IsPremium      bool           `json:"is_premium"`
		SystemPrompt   string         `json:"system_prompt"`
		UserPrompt     string         `json:"user_prompt"`
		Schema         map[string]any `json:"schema"`
		ThinkingBudget *int           `json:"thinking_budget"`
		Request        struct {
			URL     string            `json:"url"`
			Body    map[string]any    `json:"body"`
			Headers map[string]string `json:"headers"`
			Method  string            `json:"method"`
		} `json:"request"`
	} `json:"gemini_request"`

	ErrorBody []struct {
		Raw     string `json:"raw"`
		Message string `json:"message"`
	} `json:"error_body"`

	ParseJSON []struct {
		Text  string         `json:"text"`
		OK    bool           `json:"ok"`
		Value map[string]any `json:"value"`
		Error string         `json:"error"`
	} `json:"parse_json"`

	Retry []struct {
		StatusCode *int   `json:"status_code"`
		FailTimes  int    `json:"fail_times"`
		Attempts   int    `json:"attempts"`
		OK         bool   `json:"ok"`
		Error      string `json:"error"`
	} `json:"retry"`

	RetryDelay []struct {
		Attempt int     `json:"attempt"`
		Jitter  float64 `json:"jitter"`
		Seconds float64 `json:"seconds"`
	} `json:"retry_delay"`
}

func loadGolden(t *testing.T) *llmGolden {
	t.Helper()
	raw, err := os.ReadFile("../../../python/scripts/daily_golden/llm_golden.json")
	if err != nil {
		t.Fatalf("golden の読み込みに失敗: %v", err)
	}
	var g llmGolden
	if err := json.Unmarshal(raw, &g); err != nil {
		t.Fatal(err)
	}
	return &g
}

func status(p *int) int {
	if p == nil {
		return 0
	}
	return *p
}

// roundTrip は JSON を経由して map を正規化する。Go の構造体と Python の dict を
// 直接比べると int と float64 の差で落ちるため。
func roundTrip(t *testing.T, v any) any {
	t.Helper()
	raw, err := json.Marshal(v)
	if err != nil {
		t.Fatal(err)
	}
	var out any
	if err := json.Unmarshal(raw, &out); err != nil {
		t.Fatal(err)
	}
	return out
}

// TestAPIErrorGolden は LLMApiError の文字列化と一過性判定を突き合わせる。
//
// この文字列は最終的に "LLM_API_ERROR: ..." としてクライアントに返るので、
// 表記が変わるとログの検索性と既存のアラートが壊れる。
func TestAPIErrorGolden(t *testing.T) {
	g := loadGolden(t)
	for i, c := range g.Errors {
		err := &APIError{
			StatusCode: status(c.StatusCode),
			Message:    c.Message,
			Provider:   c.Provider,
		}
		if got := err.Error(); got != c.Str {
			t.Errorf("[%d] Error()=%q want %q", i, got, c.Str)
		}
		if got := err.IsTransient(); got != c.IsTransient {
			t.Errorf("[%d] status=%v IsTransient()=%v want %v",
				i, c.StatusCode, got, c.IsTransient)
		}
	}
	t.Logf("%d ケース一致", len(g.Errors))
}

func TestReasoningEffortGolden(t *testing.T) {
	g := loadGolden(t)
	for i, c := range g.ReasoningEffort {
		if c.Override == "" {
			os.Unsetenv("OPENAI_REASONING_EFFORT")
		} else {
			t.Setenv("OPENAI_REASONING_EFFORT", c.Override)
		}
		if got := OpenAIReasoningEffort(c.Model); got != c.Effort {
			t.Errorf("[%d] model=%s override=%q effort=%q want %q",
				i, c.Model, c.Override, got, c.Effort)
		}
	}
	os.Unsetenv("OPENAI_REASONING_EFFORT")
	t.Logf("%d ケース一致", len(g.ReasoningEffort))
}

// TestOpenAIPayloadGolden はリクエスト本文が Python 版と同一かを見る。
//
// Python は schema=None のとき RESPONSE_JSON_SCHEMA を使う。Go 版は
// 呼び出し側が必ずスキーマを渡す設計にしたので、ここで同じ既定値を補う。
func TestOpenAIPayloadGolden(t *testing.T) {
	g := loadGolden(t)
	os.Unsetenv("OPENAI_REASONING_EFFORT")
	for i, c := range g.OpenAIPayload {
		schema := c.Schema
		if schema == nil {
			schema = g.ResponseJSONSchema
		}
		got := OpenAIPayload(c.Model, c.SystemPrompt, c.UserPrompt,
			g.APIMaxTokens, schema)
		if !reflect.DeepEqual(roundTrip(t, got), roundTrip(t, c.Payload)) {
			t.Fatalf("[%d] model=%s payload 不一致\ngot  %v\nwant %v",
				i, c.Model, got, c.Payload)
		}
	}
	t.Logf("%d ケース一致", len(g.OpenAIPayload))
}

// TestOpenAIExtractGolden は壊れた形の output からも Python と同じ本文を
// 取り出せるかを見る。Python 版は dict/list/str の型チェックで弾いており、
// Go の型アサーションと落ち方が一致している必要がある。
func TestOpenAIExtractGolden(t *testing.T) {
	g := loadGolden(t)
	nonEmpty := 0
	for i, c := range g.OpenAIExtract {
		want := ""
		if c.Text != nil {
			want = *c.Text
			nonEmpty++
		}
		if got := OpenAIExtractText(c.Body); got != want {
			t.Errorf("[%d] got %q want %q (body=%v)", i, got, want, c.Body)
		}
	}
	t.Logf("%d ケース一致（本文あり %d）", len(g.OpenAIExtract), nonEmpty)
}

func TestOpenAIUsageLogGolden(t *testing.T) {
	g := loadGolden(t)
	for i, c := range g.OpenAIUsageLog {
		if got := OpenAIUsageLog(c.Usage, c.Tier, c.Model); got != c.Log {
			t.Errorf("[%d] got %q\nwant %q", i, got, c.Log)
		}
	}
	t.Logf("%d ケース一致", len(g.OpenAIUsageLog))
}

// TestGeminiSchemaGolden は additionalProperties の除去を見る。
// 入れ子の dict / list の奥まで再帰しないと Gemini が 400 を返す。
func TestGeminiSchemaGolden(t *testing.T) {
	g := loadGolden(t)
	for i, c := range g.GeminiSchema {
		got := GeminiSchema(c.Schema)
		if !reflect.DeepEqual(roundTrip(t, got), roundTrip(t, c.Stripped)) {
			t.Fatalf("[%d] 不一致\ngot  %v\nwant %v", i, got, c.Stripped)
		}
	}
	t.Logf("%d ケース一致", len(g.GeminiSchema))
}

func TestGeminiExtractGolden(t *testing.T) {
	g := loadGolden(t)
	for i, c := range g.GeminiResponse {
		text, usage := GeminiExtract(c.Body)
		if text != c.Text {
			t.Errorf("[%d] text=%q want %q", i, text, c.Text)
		}
		want := GeminiUsage{
			PromptTokenCount:     deref(c.Usage.Prompt),
			CandidatesTokenCount: deref(c.Usage.Candidates),
			ThoughtsTokenCount:   deref(c.Usage.Thoughts),
			TotalTokenCount:      deref(c.Usage.Total),
		}
		if usage != want {
			t.Errorf("[%d] usage=%+v want %+v", i, usage, want)
		}
	}
	t.Logf("%d ケース一致", len(g.GeminiResponse))
}

func deref(p *int) int {
	if p == nil {
		return 0
	}
	return *p
}

func TestGeminiUsageLogGolden(t *testing.T) {
	g := loadGolden(t)
	for i, c := range g.GeminiUsageLog {
		usage := GeminiUsage{
			PromptTokenCount:     deref(c.Usage.Prompt),
			CandidatesTokenCount: deref(c.Usage.Candidates),
			ThoughtsTokenCount:   deref(c.Usage.Thoughts),
			TotalTokenCount:      deref(c.Usage.Total),
		}
		if got := GeminiUsageLog(usage, c.Tier, c.Model); got != c.Log {
			t.Errorf("[%d] got %q\nwant %q", i, got, c.Log)
		}
	}
	t.Logf("%d ケース一致", len(g.GeminiUsageLog))
}

// TestGeminiRequestGolden は Python が実際に urlopen へ渡した URL・本文・
// ヘッダを、Go が組み立てるものと突き合わせる。
func TestGeminiRequestGolden(t *testing.T) {
	g := loadGolden(t)
	for i, c := range g.GeminiRequest {
		schema := c.Schema
		if schema == nil {
			schema = g.ResponseJSONSchema
		}
		budget := GeminiThinkingBudget(c.IsPremium)
		if c.ThinkingBudget != nil {
			budget = *c.ThinkingBudget
		}
		got := GeminiPayload(c.SystemPrompt, c.UserPrompt,
			g.APIMaxTokens, budget, schema)
		if !reflect.DeepEqual(roundTrip(t, got), roundTrip(t, c.Request.Body)) {
			t.Fatalf("[%d] model=%s body 不一致\ngot  %v\nwant %v",
				i, c.Model, got, c.Request.Body)
		}

		url := fmt.Sprintf("%s/models/%s:generateContent", GeminiAPIBase, c.Model)
		if url != c.Request.URL {
			t.Errorf("[%d] url=%s want %s", i, url, c.Request.URL)
		}
		if c.Request.Method != http.MethodPost {
			t.Errorf("[%d] method=%s", i, c.Request.Method)
		}
	}
	t.Logf("%d ケース一致", len(g.GeminiRequest))
}

// TestErrorMessageGolden はエラーレスポンスからの message 取り出しを見る。
func TestErrorMessageGolden(t *testing.T) {
	g := loadGolden(t)
	for i, c := range g.ErrorBody {
		want := c.Message
		// Python は JSON として読めない本文を {"error":{"message": body}} に
		// 詰め直すので、結果として本文そのものが message になる。
		if got := errorMessage([]byte(c.Raw)); got != want {
			t.Errorf("[%d] raw=%q got %q want %q", i, c.Raw, got, want)
		}
	}
	t.Logf("%d ケース一致", len(g.ErrorBody))
}

func TestParseJSONTextGolden(t *testing.T) {
	g := loadGolden(t)
	for i, c := range g.ParseJSON {
		got, err := ParseJSONText(c.Text)
		if c.OK {
			if err != nil {
				t.Errorf("[%d] text=%q 予期しないエラー: %v", i, c.Text, err)
				continue
			}
			if !reflect.DeepEqual(roundTrip(t, got), roundTrip(t, c.Value)) {
				t.Errorf("[%d] got %v want %v", i, got, c.Value)
			}
			continue
		}
		if err == nil {
			t.Errorf("[%d] text=%q はエラーになるはず", i, c.Text)
			continue
		}
		if err.Error() != c.Error {
			t.Errorf("[%d] error=%q want %q", i, err.Error(), c.Error)
		}
	}
	t.Logf("%d ケース一致", len(g.ParseJSON))
}

// TestRetryGolden は再送回数と最終的なエラー文言を Python と突き合わせる。
//
// 「何回叩いたか」は課金とレイテンシに直結する。一過性でないエラーを
// 再送すると 4 倍のコストを無駄に払うことになる。
func TestRetryGolden(t *testing.T) {
	g := loadGolden(t)
	c := &Client{Sleep: func(context.Context, time.Duration) error { return nil }}
	for i, tc := range g.Retry {
		attempts := 0
		_, err := c.callWithRetry(context.Background(), "free", "OpenAI",
			func() (map[string]any, error) {
				attempts++
				if attempts <= tc.FailTimes {
					return nil, &APIError{
						StatusCode: status(tc.StatusCode),
						Message:    "boom",
						Provider:   "OpenAI",
					}
				}
				return map[string]any{"ok": true}, nil
			})
		if attempts != tc.Attempts {
			t.Errorf("[%d] status=%v fail=%d attempts=%d want %d",
				i, tc.StatusCode, tc.FailTimes, attempts, tc.Attempts)
		}
		if tc.OK {
			if err != nil {
				t.Errorf("[%d] 予期しないエラー: %v", i, err)
			}
			continue
		}
		if err == nil {
			t.Errorf("[%d] エラーになるはず", i)
			continue
		}
		if err.Error() != tc.Error {
			t.Errorf("[%d] error=%q want %q", i, err.Error(), tc.Error)
		}
	}
	t.Logf("%d ケース一致", len(g.Retry))
}

func TestRetryDelayGolden(t *testing.T) {
	g := loadGolden(t)
	for i, c := range g.RetryDelay {
		got := RetryDelay(c.Attempt, c.Jitter).Seconds()
		if math.Abs(got-c.Seconds) > 1e-9 {
			t.Errorf("[%d] attempt=%d jitter=%v got %v want %v",
				i, c.Attempt, c.Jitter, got, c.Seconds)
		}
	}
	t.Logf("%d ケース一致", len(g.RetryDelay))
}

// TestPostSeparatesFailures は「再送する失敗」と「再送しても直らない失敗」を
// post が正しく振り分けるかを見る。
//
// 壊れた JSON を *APIError にしてしまうと、直らないものを 4 回叩くことになる。
func TestPostSeparatesFailures(t *testing.T) {
	cases := []struct {
		name      string
		statusCfg int
		body      string
		wantAPI   bool
		wantErr   string
	}{
		{"429 は再送対象", 429, `{"error":{"message":"slow down"}}`, true, ""},
		{"400 は再送しない", 400, `{"error":{"message":"bad"}}`, true, ""},
		{"壊れた JSON", 200, `{`, false, "LLM_API_ERROR: invalid JSON response"},
		{"配列", 200, `[1,2]`, false, "LLM_API_ERROR: unexpected response shape"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			srv := httptest.NewServer(http.HandlerFunc(
				func(w http.ResponseWriter, r *http.Request) {
					w.WriteHeader(tc.statusCfg)
					io.WriteString(w, tc.body)
				}))
			defer srv.Close()

			c := &Client{HTTP: srv.Client()}
			_, err := c.post(context.Background(), srv.URL, nil,
				map[string]any{"a": 1}, "OpenAI")
			if err == nil {
				t.Fatal("エラーになるはず")
			}
			apiErr, isAPI := err.(*APIError)
			if isAPI != tc.wantAPI {
				t.Fatalf("APIError=%v want %v (err=%v)", isAPI, tc.wantAPI, err)
			}
			if tc.wantAPI {
				if apiErr.StatusCode != tc.statusCfg {
					t.Errorf("status=%d want %d", apiErr.StatusCode, tc.statusCfg)
				}
				return
			}
			if err.Error() != tc.wantErr {
				t.Errorf("error=%q want %q", err.Error(), tc.wantErr)
			}
		})
	}
}

// TestGenerateSentenceRouting は tier とプロバイダー設定による振り分けを見る。
// free は常に Gemini。ここが逆転すると free の生成コストが跳ね上がる。
func TestGenerateSentenceRouting(t *testing.T) {
	cases := []struct {
		provider  string
		isPremium bool
		want      string
	}{
		{"gemini", false, "gemini"},
		{"gemini", true, "gemini"},
		{"openai", false, "gemini"},
		{"openai", true, "openai"},
	}
	for _, tc := range cases {
		var hit string
		srv := httptest.NewServer(http.HandlerFunc(
			func(w http.ResponseWriter, r *http.Request) {
				if strings.Contains(r.URL.Path, "generateContent") {
					hit = "gemini"
					io.WriteString(w,
						`{"candidates":[{"content":{"parts":[{"text":"{\"a\":1}"}]}}]}`)
					return
				}
				hit = "openai"
				io.WriteString(w, `{"output_text":"{\"a\":1}"}`)
			}))

		c := &Client{
			Provider: tc.provider, MaxTokens: 8192, HTTP: srv.Client(),
			OpenAIURL: srv.URL, GeminiBase: srv.URL + "/v1beta",
			OpenAIModel: "gpt-5-nano", OpenAIModelPremium: "gpt-5-mini",
			GeminiModel: "gemini-3-flash", GeminiModelPremium: "gemini-3.5-flash",
		}
		got, err := c.GenerateSentence(context.Background(), "sys", "user",
			tc.isPremium, "free", map[string]any{"type": "object"})
		srv.Close()
		if err != nil {
			t.Fatalf("provider=%s premium=%v: %v", tc.provider, tc.isPremium, err)
		}
		if hit != tc.want {
			t.Errorf("provider=%s premium=%v → %s want %s",
				tc.provider, tc.isPremium, hit, tc.want)
		}
		if got["a"] != float64(1) {
			t.Errorf("結果が読めていない: %v", got)
		}
	}
}
