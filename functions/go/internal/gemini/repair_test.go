package gemini

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/mnbst/thai-memo/functions/go/internal/lang"
	"github.com/mnbst/thai-memo/functions/go/internal/quizgen"
)

// 韓国語で返ってきた解説。dummy_reasons は日本語のまま。
func driftedDraft() quizgen.Draft {
	return quizgen.Draft{
		Explanation: "주어 자리에 오는 지시 대명사입니다",
		DummyReasons: []string{
			"แกง（kɛɛng / カレー）：動詞の位置に名詞が入り不自然",
			"เบื่อ（bʉ̀a / 飽きる）：目的語に動詞が入り不自然",
			"เสื้อ（sʉ̂a / 服）：移動動詞の目的語に衣類名詞が入り不自然",
		},
	}
}

// replyWith は generateContent の応答を返すだけのサーバー。
// 受け取ったリクエスト本文を requests に積む。
func replyWith(t *testing.T, payload any, requests *[]map[string]any) *httptest.Server {
	t.Helper()
	text, err := json.Marshal(payload)
	if err != nil {
		t.Fatal(err)
	}
	response, err := json.Marshal(map[string]any{
		"candidates": []any{map[string]any{
			"content": map[string]any{
				"parts": []any{map[string]any{"text": string(text)}},
			},
		}},
	})
	if err != nil {
		t.Fatal(err)
	}
	return httptest.NewServer(http.HandlerFunc(
		func(w http.ResponseWriter, r *http.Request) {
			raw, _ := io.ReadAll(r.Body)
			var parsed map[string]any
			_ = json.Unmarshal(raw, &parsed)
			*requests = append(*requests, parsed)

			w.Header().Set("Content-Type", "application/json")
			_, _ = w.Write(response)
		}))
}

func TestRepairLanguageRewritesOnlyDriftedField(t *testing.T) {
	var requests []map[string]any
	server := replyWith(t, map[string]any{
		"explanation": "主語の位置に指示代名詞を置いて「これは〜だ」を作る",
	}, &requests)
	defer server.Close()

	service := &QuizService{BaseURL: server.URL, Lang: lang.JA}
	draft := driftedDraft()
	reasons := append([]string(nil), draft.DummyReasons...)

	service.repairLanguage(context.Background(), nil, &draft)
	if lang.IsWrongLanguage(draft.Explanation, lang.JA) {
		t.Errorf("explanation が直っていない: %q", draft.Explanation)
	}
	for i, reason := range draft.DummyReasons {
		if reason != reasons[i] {
			t.Errorf("ずれていない dummy_reasons を書き換えた: %q", reason)
		}
	}

	if len(requests) != 1 {
		t.Fatalf("リクエスト %d 回, want 1", len(requests))
	}
	// 書き直しを求めるのは explanation だけ。
	schema := requests[0]["generationConfig"].(map[string]any)["responseSchema"].(map[string]any)
	properties := schema["properties"].(map[string]any)
	if len(properties) != 1 {
		t.Fatalf("responseSchema の項目 = %v, want explanation だけ", properties)
	}
	if _, ok := properties[quizgen.FieldExplanation]; !ok {
		t.Fatalf("responseSchema に explanation が無い: %v", properties)
	}
}

func TestRepairLanguageBlanksWhenStillDrifted(t *testing.T) {
	var requests []map[string]any
	server := replyWith(t, map[string]any{
		"explanation": "이것은 지시 대명사입니다",
	}, &requests)
	defer server.Close()

	service := &QuizService{BaseURL: server.URL, Lang: lang.JA}
	draft := driftedDraft()
	reasons := append([]string(nil), draft.DummyReasons...)

	service.repairLanguage(context.Background(), nil, &draft)

	// 直らない解説は空にする。出題そのものは残す。
	if draft.Explanation != "" {
		t.Errorf("explanation = %q, want 空", draft.Explanation)
	}
	for i, reason := range draft.DummyReasons {
		if reason != reasons[i] {
			t.Errorf("ずれていない dummy_reasons を消した: %q", reason)
		}
	}
	// 書き直しは1回だけ。何度も投げない。
	if len(requests) != 1 {
		t.Fatalf("リクエスト %d 回, want 1", len(requests))
	}
}

func TestRepairLanguageSkipsWhenClean(t *testing.T) {
	var requests []map[string]any
	server := replyWith(t, map[string]any{"explanation": "呼ばれないはず"}, &requests)
	defer server.Close()

	service := &QuizService{BaseURL: server.URL, Lang: lang.JA}
	draft := driftedDraft()
	draft.Explanation = "主語の位置に置く指示代名詞"

	service.repairLanguage(context.Background(), nil, &draft)
	if len(requests) != 0 {
		t.Fatalf("ずれていないのに %d 回投げた", len(requests))
	}
}
