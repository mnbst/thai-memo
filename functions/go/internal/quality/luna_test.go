package quality

import (
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync/atomic"
	"testing"
)

// lunaServer は thai_text ごとに決めた確率を返す Decisions API のスタブ。指定の無い観点は 0.1。
type lunaServer struct {
	scores map[string]map[string]float64
	status int
	calls  atomic.Int32
	last   atomic.Value
}

func (s *lunaServer) handler(w http.ResponseWriter, r *http.Request) {
	s.calls.Add(1)
	if s.status != 0 {
		w.WriteHeader(s.status)
		return
	}
	raw, _ := io.ReadAll(r.Body)
	s.last.Store(raw)
	var body struct {
		Input []struct {
			Content []struct {
				Data map[string]any `json:"data"`
			} `json:"content"`
		} `json:"input"`
		Questions []struct {
			Name string `json:"name"`
		} `json:"questions"`
	}
	_ = json.Unmarshal(raw, &body)
	thai, _ := body.Input[0].Content[0].Data["thai_text"].(string)
	var answers []any
	for _, q := range body.Questions {
		p := 0.1
		if v, ok := s.scores[thai][q.Name]; ok {
			p = v
		}
		answers = append(answers, map[string]any{"type": "predicate", "name": q.Name, "probability": p})
	}
	_ = json.NewEncoder(w).Encode(map[string]any{"answers": answers})
}

func newHybrid(t *testing.T, js *jevServer, ls *lunaServer) *Judge {
	t.Helper()
	j := newJudge(t, js)
	srv := httptest.NewServer(http.HandlerFunc(ls.handler))
	t.Cleanup(srv.Close)
	j.Luna = &Luna{APIKey: "o", Endpoint: srv.URL, HTTP: srv.Client()}
	return j
}

func TestHybridUsesLunaThresholdAndSkipsJevOnOtherAspects(t *testing.T) {
	batch := sample(3)
	batch[1].ThaiText = "LUNA"
	batch[2].ThaiText = "JEVONLY"
	js := &jevServer{scores: map[string]map[string]float64{
		// Jev の誤訳はもう聞かないので、高くても落ちない。
		"JEVONLY": {"trans_wrong": 0.95, "trans_drop": 0.7},
	}}
	ls := &lunaServer{scores: map[string]map[string]float64{
		"LUNA":      {"trans_wrong": 0.65, "collocation": 0.55},
		"ผมกินข้าว": {"trans_add": 0.99},
	}}
	res, err := newHybrid(t, js, ls).ReviewAll(t.Context(), batch)
	if err != nil {
		t.Fatal(err)
	}
	if len(res.Flagged) != 1 || res.Flagged[0].ThaiText != "LUNA" {
		t.Fatalf("LUNA だけが落ちるはず: %+v", res.Verdicts)
	}
	if res.Verdicts[0].Reason != "誤訳 0.65" {
		t.Errorf("Luna は 0.6 を超えた観点だけ: %q", res.Verdicts[0].Reason)
	}
	// Jev には jevAlso の2観点だけを聞く。
	var body struct {
		Questions map[string]any `json:"questions"`
	}
	_ = json.Unmarshal(js.last.Load().([]byte), &body)
	if len(body.Questions) != len(jevAlso) {
		t.Errorf("Jev への観点: %v", body.Questions)
	}
	// Luna には訳の加筆を聞かない。
	if strings.Contains(string(ls.last.Load().([]byte)), `"trans_add"`) {
		t.Error("Luna に trans_add を聞いている")
	}
}

func TestHybridFlagsOnJevAlsoAspect(t *testing.T) {
	batch := sample(1)
	js := &jevServer{scores: map[string]map[string]float64{
		"ผมกินข้าว": {"trans_drop": 0.8},
	}}
	res, err := newHybrid(t, js, &lunaServer{}).ReviewAll(t.Context(), batch)
	if err != nil {
		t.Fatal(err)
	}
	if len(res.Verdicts) != 1 || res.Verdicts[0].Reason != "訳の欠落（Jev） 0.80" {
		t.Fatalf("Jev の訳の欠落で落ちるはず: %+v", res.Verdicts)
	}
	if n := len(res.Verdicts[0].RetryNotes()); n != 1 {
		t.Errorf("差し戻しの指摘は観点ごとに1つ: %d", n)
	}
}

func TestHybridPoolSkipsJev(t *testing.T) {
	js := &jevServer{}
	if _, err := newHybrid(t, js, &lunaServer{}).ReviewPool(t.Context(), sample(1)); err != nil {
		t.Fatal(err)
	}
	if js.calls.Load() != 0 {
		t.Errorf("プールの観点に jevAlso は無いので Jev は呼ばない: %d", js.calls.Load())
	}
}

func TestHybridErrorIsNotAccepted(t *testing.T) {
	res, err := newHybrid(t, &jevServer{}, &lunaServer{status: http.StatusBadRequest}).ReviewAll(t.Context(), sample(1))
	if err == nil || len(res.Accepted) != 0 || len(res.Flagged) != 0 {
		t.Fatalf("Luna の失敗は合格にしない: %+v %v", res, err)
	}
}

func TestLunaRewordsQuestions(t *testing.T) {
	ls := &lunaServer{}
	if _, err := newHybrid(t, &jevServer{}, ls).ReviewAll(t.Context(), sample(1)); err != nil {
		t.Fatal(err)
	}
	raw := string(ls.last.Load().([]byte))
	if !strings.Contains(raw, "そうした語が `thai_text` に無い文も当てはまらない") {
		t.Error("訳の欠落は Luna 用の問いに置き換えるはず")
	}
	if !strings.Contains(raw, "学ばせたい語。") {
		t.Error("前置きは残すはず")
	}
}
