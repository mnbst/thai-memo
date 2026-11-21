package quality

import (
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync/atomic"
	"testing"

	"github.com/mnbst/thai-memo/functions/go/internal/lang"
)

// geminiServer は thai_text ごとに決めた確率を返す Decisions API のスタブ。指定の無い観点は 0.1。
// drop が真なら1回目の応答から答えを1つ抜く。
type geminiServer struct {
	scores map[string]map[string]float64
	status int
	drop   bool
	calls  atomic.Int32
	last   atomic.Value
}

func (s *geminiServer) handler(w http.ResponseWriter, r *http.Request) {
	n := s.calls.Add(1)
	if s.status != 0 {
		w.WriteHeader(s.status)
		return
	}
	raw, _ := io.ReadAll(r.Body)
	s.last.Store(raw)
	var body struct {
		Input []struct {
			Text string `json:"text"`
		} `json:"input"`
		Questions map[string]any `json:"questions"`
	}
	_ = json.Unmarshal(raw, &body)
	var state map[string]any
	_ = json.Unmarshal([]byte(body.Input[0].Text), &state)
	thai, _ := state["thai_text"].(string)
	answers := map[string]any{}
	for id := range body.Questions {
		p := 0.1
		if v, ok := s.scores[thai][id]; ok {
			p = v
		}
		answers[id] = map[string]any{"type": "noul", "noul": p, "confidence": max(p, 1-p)}
	}
	if s.drop && n == 1 {
		for id := range answers {
			delete(answers, id)
			break
		}
	}
	_ = json.NewEncoder(w).Encode(map[string]any{"answers": answers})
}

func newGeminiJudge(t *testing.T, s *geminiServer) *Judge {
	t.Helper()
	srv := httptest.NewServer(http.HandlerFunc(s.handler))
	t.Cleanup(srv.Close)
	return &Judge{Gemini: &Gemini{APIKey: "g", Endpoint: srv.URL, HTTP: srv.Client()}}
}

func (s *geminiServer) sentQuestions(t *testing.T) map[string]map[string]string {
	t.Helper()
	var body struct {
		Questions map[string]map[string]string `json:"questions"`
	}
	_ = json.Unmarshal(s.last.Load().([]byte), &body)
	return body.Questions
}

func TestGeminiThresholdAndSkippedAspects(t *testing.T) {
	batch := sample(3)
	batch[1].ThaiText = "BAD"
	batch[2].ThaiText = "EDGE"
	s := &geminiServer{scores: map[string]map[string]float64{
		"BAD":       {"trans_wrong": 0.53, "collocation": 0.4},
		"EDGE":      {"trans_wrong": 0.52},
		"ผมกินข้าว": {"trans_add": 0.99},
	}}
	j := newGeminiJudge(t, s)
	res, err := j.ReviewAll(t.Context(), batch)
	if err != nil {
		t.Fatal(err)
	}
	if len(res.Flagged) != 1 || res.Flagged[0].ThaiText != "BAD" {
		t.Fatalf("0.52 を超えた BAD だけが落ちるはず: %+v", res.Verdicts)
	}
	if res.Verdicts[0].Reason != "誤訳 0.53" {
		t.Errorf("理由: %q", res.Verdicts[0].Reason)
	}
	if _, ok := s.sentQuestions(t)["trans_add"]; ok {
		t.Error("訳の加筆は Gemini に聞かない")
	}
	if j.Name() != GeminiModel {
		t.Errorf("judge_model: %q", j.Name())
	}
}

func TestGeminiVocativeKeepsOwnThreshold(t *testing.T) {
	batch := sample(1)
	batch[0].JapaneseTranslation = "マウィンさん、ご飯を食べた。"
	s := &geminiServer{scores: map[string]map[string]float64{"ผมกินข้าว": {"trans_vocative": 0.66}}}
	res, err := newGeminiJudge(t, s).ReviewAll(t.Context(), batch)
	if err != nil {
		t.Fatal(err)
	}
	if len(res.Flagged) != 0 {
		t.Fatalf("呼称の音写は 0.7 まで落とさない: %+v", res.Verdicts)
	}
}

// 英訳の意味のずれ（en_mean）は英訳の文にだけ聞く。
func TestGeminiEnglishMeaningOnlyForEnglish(t *testing.T) {
	en := sample(1)
	en[0].Lang = lang.EN
	en[0].JapaneseTranslation = "I ate rice."
	s := &geminiServer{scores: map[string]map[string]float64{"ผมกินข้าว": {"en_mean": 0.6}}}
	res, err := newGeminiJudge(t, s).ReviewAll(t.Context(), en)
	if err != nil {
		t.Fatal(err)
	}
	if len(res.Verdicts) != 1 || res.Verdicts[0].Reason != "英訳の意味のずれ 0.60" {
		t.Fatalf("en_mean で落ちるはず: %+v", res.Verdicts)
	}

	s = &geminiServer{scores: map[string]map[string]float64{"ผมกินข้าว": {"en_mean": 0.9}}}
	if res, err = newGeminiJudge(t, s).ReviewAll(t.Context(), sample(1)); err != nil {
		t.Fatal(err)
	}
	if _, ok := s.sentQuestions(t)["en_mean"]; ok || len(res.Flagged) != 0 {
		t.Fatalf("日本語訳の文に en_mean を聞いている: %+v", res.Verdicts)
	}
}

func TestGeminiRewordsQuestions(t *testing.T) {
	s := &geminiServer{}
	if _, err := newGeminiJudge(t, s).ReviewAll(t.Context(), sample(1)); err != nil {
		t.Fatal(err)
	}
	q := s.sentQuestions(t)["trans_drop"]
	if q["type"] != "noul" {
		t.Errorf("type: %q", q["type"])
	}
	if !strings.Contains(q["instructions"], "そうした語が `thai_text` に無い文も当てはまらない") {
		t.Error("訳の欠落は言い換えた問いにするはず")
	}
	if !strings.HasPrefix(q["instructions"], aspectPreamble) {
		t.Error("前置きは残すはず")
	}
}

func TestGeminiRetriesMissingAnswerOnce(t *testing.T) {
	s := &geminiServer{drop: true}
	res, err := newGeminiJudge(t, s).ReviewAll(t.Context(), sample(1))
	if err != nil || len(res.Accepted) != 1 {
		t.Fatalf("欠けた答えは聞き直す: %+v %v", res, err)
	}
	if s.calls.Load() != 2 {
		t.Errorf("呼び出し回数: %d", s.calls.Load())
	}
}

func TestGeminiErrorIsNotAccepted(t *testing.T) {
	res, err := newGeminiJudge(t, &geminiServer{status: http.StatusBadRequest}).ReviewAll(t.Context(), sample(1))
	if err == nil || len(res.Accepted) != 0 || len(res.Flagged) != 0 {
		t.Fatalf("Gemini の失敗は合格にしない: %+v %v", res, err)
	}
}
