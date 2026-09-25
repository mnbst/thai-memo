package quality

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/mnbst/thai-memo/functions/go/internal/lang"
)

func sample(n int) []Candidate {
	out := make([]Candidate, n)
	for i := range out {
		out[i] = Candidate{
			UID:                 "u1",
			SentenceID:          string(rune('a' + i)),
			ThaiText:            "ผมกินข้าว",
			Pronunciation:       "phom kin khao",
			JapaneseTranslation: "ご飯を食べます",
			KeyWord:             "กิน",
			Lang:                lang.JA,
		}
	}
	return out
}

// jevServer は thai_text ごとに決めた確率を返す Jev のスタブ。
// 指定の無い観点は 0.1 を返す。
type jevServer struct {
	scores map[string]map[string]float64 // thai_text → 観点 → 確率
	status int                           // 0 なら 200
	calls  atomic.Int32
	last   atomic.Value // 最後に受け取った本文
}

func (s *jevServer) handler(w http.ResponseWriter, r *http.Request) {
	s.calls.Add(1)
	if s.status != 0 {
		w.WriteHeader(s.status)
		return
	}
	raw, _ := io.ReadAll(r.Body)
	s.last.Store(raw)
	var body struct {
		State     map[string]string `json:"state"`
		Questions map[string]any    `json:"questions"`
	}
	_ = json.Unmarshal(raw, &body)
	answers := map[string]any{}
	for id := range body.Questions {
		p := 0.1
		if v, ok := s.scores[body.State["thai_text"]][id]; ok {
			p = v
		}
		answers[id] = map[string]any{"type": "noul", "noul": p}
	}
	_ = json.NewEncoder(w).Encode(map[string]any{"answers": answers})
}

func newJudge(t *testing.T, s *jevServer) *Judge {
	t.Helper()
	srv := httptest.NewServer(http.HandlerFunc(s.handler))
	t.Cleanup(srv.Close)
	return &Judge{APIKey: "k", Endpoint: srv.URL, HTTP: srv.Client()}
}

func TestReviewSplitsFlaggedAndAccepted(t *testing.T) {
	batch := sample(3)
	batch[1].ThaiText = "bad"
	batch[1].SentenceID = "target"
	s := &jevServer{scores: map[string]map[string]float64{
		"bad": {"collocation": 0.62, "grammar": 0.45},
	}}

	res, err := newJudge(t, s).Review(context.Background(), batch)
	if err != nil {
		t.Fatal(err)
	}
	if len(res.Flagged) != 1 || res.Flagged[0].SentenceID != "target" {
		t.Fatalf("不合格の対応がずれている: %+v", res.Flagged)
	}
	if len(res.Accepted) != 2 {
		t.Fatalf("合格は2件のはず: %+v", res.Accepted)
	}
	v := res.Verdicts[0]
	// 確率の高い順に、閾値を超えた観点だけが理由になる。
	if v.Index != 1 || v.Reason != "共起 0.62・文法 0.45" {
		t.Errorf("verdict = %+v", v)
	}
	// 閾値未満の観点も scores に残す。
	if len(v.Scores) != len(Aspects) {
		t.Errorf("scores は全観点を持つ: %v", v.Scores)
	}
	if s.calls.Load() != 3 {
		t.Errorf("1文1リクエストのはず: %d", s.calls.Load())
	}
}

// trans_add だけは閾値が高い。0.4〜0.6 は細かい揺れで立つ。
func TestTransAddUsesHigherThreshold(t *testing.T) {
	batch := sample(2)
	batch[0].ThaiText = "mid"
	batch[1].ThaiText = "high"
	s := &jevServer{scores: map[string]map[string]float64{
		"mid":  {"trans_add": 0.55},
		"high": {"trans_add": 0.65},
	}}
	res, err := newJudge(t, s).Review(context.Background(), batch)
	if err != nil {
		t.Fatal(err)
	}
	if len(res.Flagged) != 1 || res.Flagged[0].ThaiText != "high" {
		t.Fatalf("trans_add 0.55 は合格・0.65 は不合格のはず: %+v", res.Flagged)
	}
}

// 英訳の文には訳の観点を聞かない（直訳・時制なしが仕様で、問いと噛み合わない）。
func TestEnglishSkipsTranslationAspects(t *testing.T) {
	batch := sample(1)
	batch[0].Lang = lang.EN
	batch[0].JapaneseTranslation = "I eat rice"
	s := &jevServer{scores: map[string]map[string]float64{
		"ผมกินข้าว": {"trans_add": 0.9, "trans_wrong": 0.9},
	}}
	res, err := newJudge(t, s).Review(context.Background(), batch)
	if err != nil {
		t.Fatal(err)
	}
	if len(res.Flagged) != 0 {
		t.Fatalf("英訳で訳の観点が効いている: %+v", res.Verdicts)
	}
	var body struct {
		Questions map[string]any `json:"questions"`
	}
	_ = json.Unmarshal(s.last.Load().([]byte), &body)
	want := 0
	for _, a := range Aspects {
		if a.JAOnly || a.Check != nil {
			if _, ok := body.Questions[a.ID]; ok {
				t.Errorf("英訳の文に %s を送っている", a.ID)
			}
			continue
		}
		want++
	}
	if len(body.Questions) != want {
		t.Errorf("質問数 = %d, want %d", len(body.Questions), want)
	}
}

// 呼び出しに失敗した文は合格にも不合格にもしない。判定できた分は返す。
func TestReviewKeepsJudgedOnError(t *testing.T) {
	good := &jevServer{}
	j := newJudge(t, good)
	fail := &jevServer{status: http.StatusBadRequest}
	failSrv := httptest.NewServer(http.HandlerFunc(fail.handler))
	t.Cleanup(failSrv.Close)

	res, err := j.Review(context.Background(), sample(2))
	if err != nil || len(res.Accepted) != 2 {
		t.Fatalf("正常系: %+v %v", res, err)
	}
	j.Endpoint = failSrv.URL
	res, err = j.Review(context.Background(), sample(2))
	if err == nil {
		t.Fatal("エラーを返していない")
	}
	if len(res.Accepted)+len(res.Flagged) != 0 {
		t.Errorf("判定できなかった文を振り分けている: %+v", res)
	}
}

func TestScoreRetriesOnRateLimit(t *testing.T) {
	var n atomic.Int32
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if n.Add(1) == 1 {
			w.WriteHeader(http.StatusTooManyRequests)
			return
		}
		answers := map[string]any{}
		for _, a := range Aspects {
			answers[a.ID] = map[string]any{"noul": 0.1}
		}
		_ = json.NewEncoder(w).Encode(map[string]any{"answers": answers})
	}))
	t.Cleanup(srv.Close)
	j := &Judge{APIKey: "k", Endpoint: srv.URL, HTTP: srv.Client()}
	res, err := j.Review(context.Background(), sample(1))
	if err != nil || len(res.Accepted) != 1 {
		t.Fatalf("429 の後に再試行していない: %+v %v", res, err)
	}
}

// 観点が欠けたレスポンスは判定不能（欠けた観点を合格にしない）。
func TestParseScoresRejectsMissingAspect(t *testing.T) {
	raw := []byte(`{"answers":{"collocation":{"noul":0.1}}}`)
	if _, err := ParseScores(raw, Aspects); err == nil {
		t.Error("観点の欠落を通している")
	}
	if _, err := ParseScores([]byte(`not json`), Aspects); err == nil {
		t.Error("壊れた JSON を通している")
	}
}

func TestRequestBodyState(t *testing.T) {
	c := sample(1)[0]
	raw, err := json.Marshal(RequestBody("jev-latest", c))
	if err != nil {
		t.Fatal(err)
	}
	body := string(raw)
	// thai_text を先頭に固定する。Jev は state のキー順で確率が動き、閾値は
	// この順で測っている（map だと辞書順で japanese_translation が先に来る）。
	i := strings.Index(body, `"state":`)
	if i < 0 || !strings.HasPrefix(body[i:], `"state":{"thai_text":`) {
		t.Errorf("state が thai_text から始まっていない: %s", body)
	}
	// 発音は渡さない（読ませる情報を増やすほど注意が散る）。
	if strings.Contains(body, "pronunciation") || strings.Contains(body, "phom") {
		t.Error("発音まで渡している")
	}
	if !strings.Contains(body, `"key_word":"กิน"`) {
		t.Errorf("key_word を渡していない: %s", body)
	}
	c.KeyWord = ""
	raw, _ = json.Marshal(RequestBody("m", c))
	if strings.Contains(string(raw), "key_word\":") || strings.Contains(string(raw), `"key_word":`) {
		t.Error("空の key_word を渡している")
	}
	// 観点は並列に評価され互いを見ないので、各問が state の説明を持つ。
	for id, q := range RequestBody("m", c)["questions"].(map[string]any) {
		ins := q.(map[string]any)["instructions"].(string)
		if !strings.HasPrefix(ins, aspectPreamble) {
			t.Errorf("%s に state の説明が無い", id)
		}
	}
}

// 差し戻しの指摘にタイ語を入れない（生成側が写す）。Note を持つ観点は Note を使う。
func TestRetryNotesHaveNoThai(t *testing.T) {
	var ids []string
	for _, a := range Aspects {
		ids = append(ids, a.ID)
	}
	for _, n := range (Verdict{Hits: ids}).RetryNotes() {
		for _, r := range n {
			if r >= 0x0E00 && r <= 0x0E7F {
				t.Errorf("差し戻しの指摘にタイ文字がある: %s", n)
				break
			}
		}
	}
}

// 文字種・記号はコードで判定し、Jev には送らない。
func TestCodeChecks(t *testing.T) {
	batch := sample(3)
	batch[0].JapaneseTranslation = "พี่と一緒に行きたい"
	batch[1].JapaneseTranslation = "兄（姉）が助けてくれなかった。"
	s := &jevServer{}
	res, err := newJudge(t, s).Review(context.Background(), batch)
	if err != nil {
		t.Fatal(err)
	}
	if len(res.Flagged) != 2 || len(res.Accepted) != 1 {
		t.Fatalf("タイ文字・括弧の文だけ不合格のはず: %+v", res)
	}
	if res.Verdicts[0].Reason != "訳にタイ文字 1.00" || res.Verdicts[1].Reason != "訳の括弧補足 1.00" {
		t.Errorf("reason = %q / %q", res.Verdicts[0].Reason, res.Verdicts[1].Reason)
	}
	var body struct {
		Questions map[string]any `json:"questions"`
	}
	_ = json.Unmarshal(s.last.Load().([]byte), &body)
	for _, id := range []string{"trans_thai", "trans_paren"} {
		if _, ok := body.Questions[id]; ok {
			t.Errorf("コード判定の %s を Jev に送っている", id)
		}
	}

	// 英訳でもタイ文字は判定する。括弧は英語では普通に使うので見ない。
	en := sample(2)
	en[0].Lang, en[0].JapaneseTranslation = lang.EN, "I go with พี่"
	en[1].Lang, en[1].JapaneseTranslation = lang.EN, "I (really) like it"
	res, _ = newJudge(t, &jevServer{}).Review(context.Background(), en)
	if len(res.Flagged) != 1 || res.Flagged[0].JapaneseTranslation != "I go with พี่" {
		t.Errorf("英訳の判定が違う: %+v", res.Flagged)
	}
}

func TestFlagIDIsStable(t *testing.T) {
	c := Candidate{UID: "u1", SentenceID: "s1"}
	if FlagID(c) != "u1_s1" {
		t.Errorf("doc ID が固定でない: %s", FlagID(c))
	}
}

func TestFlagDocCarriesSentenceBody(t *testing.T) {
	created := time.Date(2026, 9, 1, 0, 0, 0, 0, time.UTC)
	judged := created.Add(24 * time.Hour)
	c := Candidate{
		UID: "u1", SentenceID: "s1",
		ThaiText: "ผมกินข้าว", JapaneseTranslation: "ご飯を食べます",
		KeyWord: "กิน", Topic: "食べ物", Emotion: "neutral",
		GenerationTier: "premium", CreatedAt: created,
	}
	v := Verdict{Reason: "共起 0.62", Scores: map[string]float64{"collocation": 0.62}}

	doc := FlagDoc(c, v, "jev-latest", judged)

	// 30日後に例文が消えても台帳が読めること＝本文の複製が要る。
	for k, want := range map[string]any{
		"thai_text":            "ผมกินข้าว",
		"japanese_translation": "ご飯を食べます",
		"key_word":             "กิน",
		"topic":                "食べ物",
		"uid":                  "u1",
		"sentence_id":          "s1",
		"reason":               "共起 0.62",
		"judge_model":          "jev-latest",
		"created_at":           created,
		"judged_at":            judged,
	} {
		if doc[k] != want {
			t.Errorf("%s = %v, want %v", k, doc[k], want)
		}
	}
	if fmt.Sprint(doc["scores"]) != fmt.Sprint(v.Scores) {
		t.Errorf("scores = %v", doc["scores"])
	}
}
