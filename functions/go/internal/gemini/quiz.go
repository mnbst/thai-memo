// Package gemini は Gemini API を使ったクイズ生成。
// functions/javascript/src/services/geminiQuizService.ts の移植。
package gemini

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"math"
	"net/http"
	"strings"

	"github.com/mnbst/thai-memo/functions/go/internal/lang"
	"github.com/mnbst/thai-memo/functions/go/internal/quizgen"
)

// Model は使用するモデル。
//
// gemini-2.5 系は 2026-08 時点で新規APIキーからは利用不可（404: no longer available
// to new users）。キーをローテートすると即座に生成が全停止するため 3.x 系を使う。
const Model = "gemini-3.1-flash-lite"

// 100万トークンあたりの単価（USD）。
var pricingPerMillion = struct{ Input, Output float64 }{Input: 0.25, Output: 1.50}

const maxOutputTokens = 4096
const thinkingBudget = 256

// QuizService は Gemini でクイズ1問ぶんのダミー・理由・解説を作る。
type QuizService struct {
	APIKey string
	UID    string
	// Tier は "free" か "premium"。ログの集計にだけ使う。
	Tier string
	Lang lang.Lang

	// HTTP は差し替え用。nil なら http.DefaultClient。
	HTTP *http.Client
	// BaseURL は差し替え用。nil なら Gemini の本番エンドポイント。
	BaseURL string
	// Sanitizer は nil なら quizgen.DefaultSanitizer。
	Sanitizer *quizgen.Sanitizer
}

func (s *QuizService) httpClient() *http.Client {
	if s.HTTP != nil {
		return s.HTTP
	}
	return http.DefaultClient
}

func (s *QuizService) baseURL() string {
	if s.BaseURL != "" {
		return s.BaseURL
	}
	return "https://generativelanguage.googleapis.com"
}

func (s *QuizService) sanitizer() *quizgen.Sanitizer {
	if s.Sanitizer != nil {
		return s.Sanitizer
	}
	return quizgen.DefaultSanitizer
}

// GenerateQuizQuestions は例文からクイズ問題を作る。
// モデルが応答しない・出力が使えない場合は空を返す（エラーにしない）。
func (s *QuizService) GenerateQuizQuestions(
	ctx context.Context, sentences []quizgen.QuizSentenceSeed,
) []quizgen.GeneratedQuizQuestion {
	draft := s.fetchStructuredResponse(ctx, sentences)
	if draft == nil {
		return nil
	}

	merged := quizgen.ApplyRuleBasedFields([]quizgen.Draft{*draft}, sentences)
	return s.sanitizer().Questions(merged)
}

// BuildRequestBody は Gemini へ送るリクエスト本文を組み立てる。
// 差分テストから直接呼べるように切り出している。
func BuildRequestBody(sentences []quizgen.QuizSentenceSeed, l lang.Lang) map[string]any {
	return map[string]any{
		"systemInstruction": map[string]any{
			"parts": []any{map[string]any{"text": quizgen.SystemPrompt(l)}},
		},
		"contents": []any{map[string]any{
			"role":  "user",
			"parts": []any{map[string]any{"text": quizgen.BuildPrompt(sentences, l)}},
		}},
		"generationConfig": map[string]any{
			"responseMimeType": "application/json",
			"responseSchema":   responseSchema(l),
			"maxOutputTokens":  maxOutputTokens,
			"thinkingConfig": map[string]any{
				"thinkingBudget": thinkingBudget,
			},
		},
	}
}

type usageMetadata struct {
	PromptTokenCount     int `json:"promptTokenCount"`
	CandidatesTokenCount int `json:"candidatesTokenCount"`
	TotalTokenCount      int `json:"totalTokenCount"`
	ThoughtsTokenCount   int `json:"thoughtsTokenCount"`
}

type geminiResponse struct {
	Candidates []struct {
		Content struct {
			Parts []struct {
				Text string `json:"text"`
			} `json:"parts"`
		} `json:"content"`
	} `json:"candidates"`
	UsageMetadata *usageMetadata `json:"usageMetadata"`
	Error         *struct {
		Message string `json:"message"`
		Code    int    `json:"code"`
	} `json:"error"`
}

func (s *QuizService) fetchStructuredResponse(
	ctx context.Context, sentences []quizgen.QuizSentenceSeed,
) *quizgen.Draft {
	body, err := json.Marshal(BuildRequestBody(sentences, s.Lang))
	if err != nil {
		log.Printf("gemini_quiz_generation_failed model=%s error=%v", Model, err)
		return nil
	}

	url := fmt.Sprintf("%s/v1beta/models/%s:generateContent?key=%s",
		s.baseURL(), Model, s.APIKey)
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(body))
	if err != nil {
		log.Printf("gemini_quiz_generation_failed model=%s error=%v", Model, err)
		return nil
	}
	req.Header.Set("Content-Type", "application/json")

	res, err := s.httpClient().Do(req)
	if err != nil {
		log.Printf("gemini_quiz_generation_failed model=%s error=%v", Model, err)
		return nil
	}
	defer res.Body.Close()

	raw, err := io.ReadAll(res.Body)
	if err != nil {
		log.Printf("gemini_quiz_generation_failed model=%s error=%v", Model, err)
		return nil
	}

	var parsed geminiResponse
	if err := json.Unmarshal(raw, &parsed); err != nil {
		log.Printf("gemini_quiz_generation_failed model=%s error=%v", Model, err)
		return nil
	}

	if res.StatusCode < 200 || res.StatusCode >= 300 {
		code, message := 0, ""
		if parsed.Error != nil {
			code, message = parsed.Error.Code, parsed.Error.Message
		}
		log.Printf("gemini_quiz_generation_failed status=%d model=%s errorCode=%d errorMessage=%s",
			res.StatusCode, Model, code, message)
		return nil
	}

	s.logUsage(sentences, parsed.UsageMetadata)

	text := ""
	if len(parsed.Candidates) > 0 && len(parsed.Candidates[0].Content.Parts) > 0 {
		text = strings.TrimSpace(parsed.Candidates[0].Content.Parts[0].Text)
	}
	if text == "" {
		log.Printf("gemini_quiz_generation_empty_output model=%s", Model)
		return nil
	}

	var draft quizgen.Draft
	if err := json.Unmarshal([]byte(text), &draft); err != nil {
		log.Printf("gemini_quiz_generation_failed model=%s error=%v", Model, err)
		return nil
	}
	return &draft
}

func (s *QuizService) logUsage(
	sentences []quizgen.QuizSentenceSeed, usage *usageMetadata,
) {
	if usage == nil {
		return
	}

	promptTokens := usage.PromptTokenCount
	candidatesTokens := usage.CandidatesTokenCount
	thoughtsTokens := usage.ThoughtsTokenCount
	billedOutputTokens := candidatesTokens + thoughtsTokens
	totalTokens := usage.TotalTokenCount
	if totalTokens == 0 {
		totalTokens = promptTokens + billedOutputTokens
	}
	costUSD := (float64(promptTokens)*pricingPerMillion.Input +
		float64(billedOutputTokens)*pricingPerMillion.Output) / 1_000_000

	requestMode := "single"
	if len(sentences) > 1 {
		requestMode = "batch"
	}

	log.Printf("gemini_quiz_token_usage uid=%s tier=%s requestMode=%s sentenceCount=%d "+
		"model=%s promptTokens=%d candidatesTokens=%d thoughtsTokens=%d "+
		"billedOutputTokens=%d totalTokens=%d costUsdMicros=%d",
		s.UID, s.Tier, requestMode, len(sentences), Model,
		promptTokens, candidatesTokens, thoughtsTokens,
		billedOutputTokens, totalTokens, int64(math.Round(costUSD*1_000_000)))
}
