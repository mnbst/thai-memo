package quality

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"maps"
	"net/http"
	"strings"
	"time"
)

// Gemini は Gemini Decisions API（gemini-decision-1）で観点を判定する。
//
// 2026-11-21 に「Luna（gpt-6-luna）が主、Jev は2観点」から Gemini 一本へ切り替えた。
// 同じ問いで、各文の欠陥の検出・正常の誤検出は:
//
//	                       ja 評価セット  prod 不合格82本  en 評価セット
//	                       （欠陥60・正常80）（本物39・誤検出43）（欠陥55・正常145）
//	Luna＋Jev 2観点         44・2         18・7           39・7
//	Gemini だけ 0.52        44・3         18・6           40・7
//
// prod 82本のラベルと en 評価セット（prod en プール150本＋Codex に1か所ずらさせた50本）は
// Codex の判定。精度はほぼ同じで、呼び出しが1つになり、料金は Luna の約半分
// （1文 約1,900トークン・$0.10/100万）。同じ文には毎回同じ点を返す（3回で幅0。Jev は最大0.3揺れる）。
// 英訳の意味のずれ（en_mean）も Gemini のほうが分けられた（AUC Gemini 0.95・Jev 0.92）。
//
// 同日、問いの文面を3つ直した（訳の意味のずれ・英訳の意味のずれ・key_word の用法。pool.go・judge.go）。
// 直した後は ja 46・0、prod 23・6、en 45・3。直した文面は同じデータを見て作ったので、
// 見ていない prod の判定（Luna 時代 11/13〜21 の不合格44本＋通った246本。Codex が判定を伏せて
// ラベル付けし、欠陥69・正常221）で確かめ直した:
//
//	Luna＋Jev（本番）       23・21
//	Gemini 直す前の問い     18・10
//	Gemini 直した問い       24・13（新たに拾った6本のうち5本は訳の意味のずれ）
//
// 閾値は 0.45〜0.6 を 0.01 刻みで見て 0.52 にした。0.53 にすると prod 82本の本物の検出が 18→15 に落ち、
// 0.5 では ja 評価セットの誤検出が 3→4・en が 7→9 に増える。
type Gemini struct {
	APIKey string
	// Model が空なら gemini-decision-1。
	Model string
	// Endpoint と HTTP はテストで差し替える。空なら既定値。
	Endpoint string
	HTTP     *http.Client
}

const (
	geminiEndpoint = "https://generativelanguage.googleapis.com/v1beta/decisions"
	GeminiModel    = "gemini-decision-1"
	// geminiThreshold は Gemini の全観点に共通の閾値（Gemini のコメント参照）。
	geminiThreshold = 0.52
)

// geminiThresholds は geminiThreshold と別の閾値にする観点。
// 呼称の音写は正しいあだ名表記（マウィンさん、prod の「先輩」）が 0.6 を超えていた（Luna で測った値を引き継ぐ）。
var geminiThresholds = map[string]float64{"trans_vocative": vocativeThreshold}

// geminiKeywordSceneQuestion は usage_scenarios がある文の key_word の用法の問い。
// 場面を渡して問いでも見させると、語を合わない物・相手に使う文を拾う
// （2026-11-25: ×เมนูนี้ใช้ไม่ได้ 0.27→0.56、prod プール100件で不合格 3→13・増えた10件は目視・Codex で7〜8件が怪しい文）。
const geminiKeywordSceneQuestion = "`key_word` が `thai_text` の中で、タイ語の母語話者が使わない形で使われている（本来と違う意味で使う、その語が合わない相手・物・場面に使う 等）。`usage_scenarios` の場面で言う文として、`key_word` の意味が合わないものも含む。くだけた言い方や話し言葉の綴りであること自体は当てはまらない"

// geminiSkip は Gemini に聞かない観点。訳の加筆は Luna で正常 5/48・欠陥 5/51 と見分けがつかず、
// Gemini でも聞かずに測った。
var geminiSkip = map[string]bool{"trans_add": true}

// geminiQuestions は Jev の問いから言い換えた問い（Luna のときに作った。Gemini もこの文面で測った）。
// Jev の「〜が抜けているか」「〜が合っていないか」のままだと、Luna は該当する語の無い正常文にも
// 0.9 前後を付けた（訳の欠落 25/48、接続語の論理 12/48）。言い換え後は 0/48。
var geminiQuestions = map[string]string{
	"trans_drop":  "`thai_text` に目的・条件・否定・可能性・義務・譲歩を表す語（เพื่อ、เพื่อให้、ถ้า、ไม่、อาจจะ、ต้อง、ทั้งที่ など）があり、その意味が `japanese_translation` のどこにも表れていない。言い方を変えて同じ意味が訳に残っているものは当てはまらない。そうした語が `thai_text` に無い文も当てはまらない",
	"conjunction": "`thai_text` に接続語（เพราะ、เลย、ก็เลย、ดังนั้น、แต่、แม้ว่า、ถึง 等）があり、その接続語が前後の内容の関係と食い違っている（理由・結果の接続語なのに後ろが前の理由・結果になっていない、逆接の接続語なのに前後が対立していない）。接続語が無い文は当てはまらない",
}

func (g *Gemini) model() string {
	if g.Model != "" {
		return g.Model
	}
	return GeminiModel
}

// geminiAspects は c に聞く観点のうち Gemini に送るもの（閾値を Gemini 用に差し替える）と、
// コードで判定する観点を合わせて返す。返す観点のリストは verdictFrom 用。
func geminiAspects(c Candidate, aspects []Aspect) (send, judged []Aspect) {
	for _, a := range aspects {
		switch {
		case a.Check != nil:
			judged = append(judged, a)
		case geminiSkip[a.ID]:
		case a.ID == "keyword" && c.KeyWord == "":
			// key_word が無い文には用法を聞かない。
		default:
			ga := a
			ga.Threshold = geminiThreshold
			if th, ok := geminiThresholds[a.ID]; ok {
				ga.Threshold = th
			}
			send = append(send, ga)
			judged = append(judged, ga)
		}
	}
	return send, judged
}

// geminiRequest は Decisions API の本文を組む。state は Jev と同じもの（thai_text が先頭）を
// JSON 文字列にしてテキストとして渡す。問いの文面は Jev と同じ（前置き＋問い）。
// 前置きを入力へ1回だけ置くと 2,111 → 1,631 トークンに減るが、確率が動いて評価セットの
// 誤検出が 0→4/80 に増えた（2026-11-25）。閾値はこの形で測ったものなので問いごとに付ける。
func geminiRequest(model string, c Candidate, aspects []Aspect) (map[string]any, error) {
	st, preamble := stateAndPreamble(c)
	state, err := json.Marshal(st)
	if err != nil {
		return nil, err
	}
	qs := make(map[string]any, len(aspects))
	for _, a := range aspects {
		if a.Check != nil {
			continue
		}
		instr := a.Question
		if alt, ok := geminiQuestions[a.ID]; ok {
			instr = alt
		}
		if a.ID == "keyword" && c.UsageScenarios != "" {
			instr = geminiKeywordSceneQuestion
		}
		qs[a.ID] = map[string]any{"type": "noul", "instructions": preamble + instr}
	}
	return map[string]any{
		"model":     model,
		"input":     []any{map[string]any{"type": "text", "text": string(state)}},
		"questions": qs,
	}, nil
}

// score は aspects（Gemini に送る観点）を聞き、観点 ID → はいの確率 を返す。
func (g *Gemini) score(ctx context.Context, c Candidate, aspects []Aspect) (map[string]float64, error) {
	if len(aspects) == 0 {
		return map[string]float64{}, nil
	}
	// usage_scenarios は key_word の用法の問いにだけ見せる。入力は全問で共有されるので、
	// 同じリクエストに載せると他の観点も場面に引っ張られる（訳の意味のずれの誤検出が
	// prod プール300件で 0→10。「見ずに判定する」と問いに書いても 6 残った）。
	if c.UsageScenarios != "" {
		var kw, rest []Aspect
		for _, a := range aspects {
			if a.ID == "keyword" {
				kw = append(kw, a)
			} else {
				rest = append(rest, a)
			}
		}
		if len(kw) > 0 {
			plain := c
			plain.UsageScenarios = ""
			out, err := g.score(ctx, plain, rest)
			if err != nil {
				return nil, err
			}
			ks, err := g.scoreOnce(ctx, c, kw)
			if err != nil {
				return nil, err
			}
			maps.Copy(out, ks)
			return out, nil
		}
		c.UsageScenarios = ""
	}
	return g.scoreOnce(ctx, c, aspects)
}

// scoreOnce は aspects を1回のリクエストで聞く。
func (g *Gemini) scoreOnce(ctx context.Context, c Candidate, aspects []Aspect) (map[string]float64, error) {
	if len(aspects) == 0 {
		return map[string]float64{}, nil
	}
	req, err := geminiRequest(g.model(), c, aspects)
	if err != nil {
		return nil, err
	}
	ids := make([]string, len(aspects))
	for i, a := range aspects {
		ids[i] = a.ID
	}
	return g.post(ctx, req, ids)
}

// Ask は input（テキスト）について questions（ID → 問い）を noul で聞き、ID → はいの確率 を返す。
// 例文の判定以外（生成パラメータの選択など）に使う。
func (g *Gemini) Ask(ctx context.Context, input string, questions map[string]string) (map[string]float64, error) {
	if len(questions) == 0 {
		return map[string]float64{}, nil
	}
	qs := make(map[string]any, len(questions))
	ids := make([]string, 0, len(questions))
	for id, q := range questions {
		qs[id] = map[string]any{"type": "noul", "instructions": q}
		ids = append(ids, id)
	}
	return g.post(ctx, map[string]any{
		"model":     g.model(),
		"input":     []any{map[string]any{"type": "text", "text": input}},
		"questions": qs,
	}, ids)
}

// post は Decisions API へ req を送り、ids の答えを返す。
// 429 / 5xx は指数バックオフで数回だけ再試行する。答えが欠けたら1回だけ聞き直す。
func (g *Gemini) post(ctx context.Context, req map[string]any, ids []string) (map[string]float64, error) {
	body, err := json.Marshal(req)
	if err != nil {
		return nil, err
	}
	client := g.HTTP
	if client == nil {
		client = &http.Client{Timeout: 30 * time.Second}
	}
	endpoint := g.Endpoint
	if endpoint == "" {
		endpoint = geminiEndpoint
	}
	const maxAttempts = 4
	for attempt := 0; ; attempt++ {
		req, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint, bytes.NewReader(body))
		if err != nil {
			return nil, err
		}
		req.Header.Set("x-goog-api-key", g.APIKey)
		req.Header.Set("Content-Type", "application/json")
		resp, err := client.Do(req)
		if err != nil {
			return nil, err
		}
		raw, err := io.ReadAll(resp.Body)
		resp.Body.Close()
		if err != nil {
			return nil, err
		}
		retryable := resp.StatusCode == http.StatusTooManyRequests || resp.StatusCode >= 500
		if retryable && attempt+1 < maxAttempts {
			select {
			case <-ctx.Done():
				return nil, ctx.Err()
			case <-time.After(time.Duration(1<<attempt) * time.Second):
			}
			continue
		}
		if resp.StatusCode != http.StatusOK {
			return nil, fmt.Errorf("gemini: status %d: %s", resp.StatusCode, strings.TrimSpace(string(raw)))
		}
		scores, err := parseGemini(raw, ids)
		if errors.Is(err, errGeminiMissing) && attempt == 0 {
			continue
		}
		return scores, err
	}
}

var errGeminiMissing = errors.New("gemini: answer missing")

func parseGemini(raw []byte, ids []string) (map[string]float64, error) {
	var resp struct {
		Answers map[string]struct {
			Noul *float64 `json:"noul"`
		} `json:"answers"`
	}
	if err := json.Unmarshal(raw, &resp); err != nil {
		return nil, fmt.Errorf("gemini: parse: %w", err)
	}
	out := make(map[string]float64, len(ids))
	for _, id := range ids {
		ans, ok := resp.Answers[id]
		if !ok || ans.Noul == nil {
			return nil, fmt.Errorf("%w: %q", errGeminiMissing, id)
		}
		out[id] = *ans.Noul
	}
	return out, nil
}

// geminiScore は1文を Gemini で判定する。コードで判定する観点はここで点を付ける。
func (j *Judge) geminiScore(ctx context.Context, c Candidate, aspects []Aspect) ([]Aspect, map[string]float64, error) {
	send, judged := geminiAspects(c, aspects)
	scores, err := j.Gemini.score(ctx, c, send)
	if err != nil {
		return nil, nil, err
	}
	for _, a := range judged {
		if a.Check == nil {
			continue
		}
		scores[a.ID] = 0
		if a.Check(c) {
			scores[a.ID] = 1
		}
	}
	return judged, scores, nil
}
