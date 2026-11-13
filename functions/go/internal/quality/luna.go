package quality

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"
)

// Luna は OpenAI Decisions API（gpt-6-luna）で観点を判定する。
//
// 2026-11-13 に Jev 単独から「Luna が主、Jev は2観点だけ」へ切り替えた。
// prod の不合格82本（Codex で誤検出48・本物34）と評価セット全件（欠陥60・正常80）で:
//
//	                   prod 誤検出  prod 欠陥  評価 欠陥  評価 正常の誤検出
//	Jev だけ            43/48       33/34      51/60      14/80
//	Luna＋Jev 2観点     11/48       21/34      44/60       4/80
//
// Jev は訳の観点（訳の意味のずれ・訳の加筆・誤訳）で、場面に合わせた補いや意訳を
// 誤訳として落としていた。Luna はそこを誤検出しないが、目的・可能性・義務の語
// （เพื่อให้・อาจจะ・ต้อง）の抜けとその場で作ったたとえを見逃すので、その2観点だけ
// Jev にも聞く（jevAlso）。訳の加筆はどちらも正しい訳と見分けられないので聞かない。
type Luna struct {
	APIKey string
	// Model が空なら gpt-6-luna。
	Model string
	// Endpoint と HTTP はテストで差し替える。空なら既定値。
	Endpoint string
	HTTP     *http.Client
}

const (
	lunaEndpoint = "https://api.openai.com/v1/decisions"
	LunaModel    = "gpt-6-luna"
	// lunaThreshold は Luna の全観点に共通の閾値。0.5 では prod の誤検出 14/48、
	// 0.7 では本物の欠陥の検出が 17→12/34 に落ちる。
	lunaThreshold = 0.6
)

// lunaSkip は Luna に聞かない観点。訳の加筆は Luna で正常 5/48・欠陥 5/51 と見分けがつかない。
var lunaSkip = map[string]bool{"trans_add": true}

// lunaQuestions は Luna 用に言い換えた問い。Jev の「〜が抜けているか」「〜が合っていないか」
// のままだと、Luna は該当する語の無い正常文にも 0.9 前後を付けた（訳の欠落 25/48、
// 接続語の論理 12/48）。言い換え後は 0/48。
var lunaQuestions = map[string]string{
	"trans_drop":  "`thai_text` に目的・条件・否定・可能性・義務・譲歩を表す語（เพื่อ、เพื่อให้、ถ้า、ไม่、อาจจะ、ต้อง、ทั้งที่ など）があり、その意味が `japanese_translation` のどこにも表れていない。言い方を変えて同じ意味が訳に残っているものは当てはまらない。そうした語が `thai_text` に無い文も当てはまらない",
	"conjunction": "`thai_text` に接続語（เพราะ、เลย、ก็เลย、ดังนั้น、แต่、แม้ว่า、ถึง 等）があり、その接続語が前後の内容の関係と食い違っている（理由・結果の接続語なのに後ろが前の理由・結果になっていない、逆接の接続語なのに前後が対立していない）。接続語が無い文は当てはまらない",
}

// jevAlso は Luna と並べて Jev にも聞く観点と、その Jev の閾値。
// 訳の欠落は 0.45 のままだと prod の誤検出が 11→16/48 に増え、欠陥の検出は変わらない。
var jevAlso = map[string]float64{
	"trans_drop": 0.75,
	"metaphor":   Threshold,
}

// jevPrefix は Jev の確率を scores に入れるときのキーの接頭辞（Luna の同じ観点と分ける）。
const jevPrefix = "jev:"

func (l *Luna) model() string {
	if l.Model != "" {
		return l.Model
	}
	return LunaModel
}

// lunaRequest は Decisions API の本文を組む。state は Jev と同じもの（thai_text が先頭）。
func lunaRequest(model string, c Candidate, aspects []Aspect) map[string]any {
	jb := requestBody("", c, aspects)
	qs := make([]map[string]any, 0, len(aspects))
	jq := jb["questions"].(map[string]any)
	for _, a := range aspects {
		q, ok := jq[a.ID].(map[string]any)
		if !ok {
			continue
		}
		instr := q["instructions"].(string)
		if alt, ok := lunaQuestions[a.ID]; ok {
			instr = strings.TrimSuffix(instr, a.Question) + alt
		}
		qs = append(qs, map[string]any{"type": "predicate", "name": a.ID, "instructions": instr})
	}
	return map[string]any{
		"model": model,
		"input": []any{map[string]any{
			"role":    "user",
			"content": []any{map[string]any{"type": "input_json", "data": jb["state"]}},
		}},
		"questions": qs,
	}
}

// score は aspects（コードで判定する観点を除く）を Luna に聞き、観点 ID → はいの確率 を返す。
// 429 / 5xx は指数バックオフで数回だけ再試行する。答えが欠けたら判定不能として扱う。
func (l *Luna) score(ctx context.Context, c Candidate, aspects []Aspect) (map[string]float64, error) {
	if len(aspects) == 0 {
		return map[string]float64{}, nil
	}
	body, err := json.Marshal(lunaRequest(l.model(), c, aspects))
	if err != nil {
		return nil, err
	}
	client := l.HTTP
	if client == nil {
		client = &http.Client{Timeout: 30 * time.Second}
	}
	endpoint := l.Endpoint
	if endpoint == "" {
		endpoint = lunaEndpoint
	}
	const maxAttempts = 4
	for attempt := 0; ; attempt++ {
		req, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint, bytes.NewReader(body))
		if err != nil {
			return nil, err
		}
		req.Header.Set("Authorization", "Bearer "+l.APIKey)
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
			return nil, fmt.Errorf("luna: status %d: %s", resp.StatusCode, strings.TrimSpace(string(raw)))
		}
		scores, err := parseLuna(raw, aspects)
		// 答えが欠ける（refusal）ことが評価セット140文×15問で10回あった。1回だけ聞き直す。
		if errors.Is(err, errLunaMissing) && attempt == 0 {
			continue
		}
		return scores, err
	}
}

var errLunaMissing = errors.New("luna: answer missing")

func parseLuna(raw []byte, aspects []Aspect) (map[string]float64, error) {
	var resp struct {
		Answers []struct {
			Type        string   `json:"type"`
			Name        string   `json:"name"`
			Probability *float64 `json:"probability"`
		} `json:"answers"`
	}
	if err := json.Unmarshal(raw, &resp); err != nil {
		return nil, fmt.Errorf("luna: parse: %w", err)
	}
	got := make(map[string]float64, len(resp.Answers))
	for _, a := range resp.Answers {
		if a.Probability != nil {
			got[a.Name] = *a.Probability
		}
	}
	out := make(map[string]float64, len(aspects))
	for _, a := range aspects {
		p, ok := got[a.ID]
		if !ok {
			return nil, fmt.Errorf("%w: %q", errLunaMissing, a.ID)
		}
		out[a.ID] = p
	}
	return out, nil
}

// hybridScore は Luna を主に、jevAlso の観点だけ Jev にも聞いて1文を判定する。
// 返す観点のリストは verdictFrom 用（Jev の観点は ID に jevPrefix を付け、閾値を差し替える）。
func (j *Judge) hybridScore(ctx context.Context, c Candidate, aspects []Aspect) ([]Aspect, map[string]float64, error) {
	var lunaAsp, jevAsp, judged []Aspect
	for _, a := range aspects {
		switch {
		case a.Check != nil:
			judged = append(judged, a)
		case lunaSkip[a.ID]:
		case a.ID == "keyword" && c.KeyWord == "":
			// key_word が無い文では Luna はこの問いに答えを返さない。
		default:
			la := a
			la.Threshold = lunaThreshold
			lunaAsp = append(lunaAsp, la)
			judged = append(judged, la)
			if th, ok := jevAlso[a.ID]; ok {
				jevAsp = append(jevAsp, a)
				ja := a
				ja.ID = jevPrefix + a.ID
				ja.Label = a.Label + "（Jev）"
				ja.Threshold = th
				judged = append(judged, ja)
			}
		}
	}
	scores, err := j.Luna.score(ctx, c, lunaAsp)
	if err != nil {
		return nil, nil, err
	}
	if len(jevAsp) > 0 {
		js, err := j.score(ctx, c, jevAsp)
		if err != nil {
			return nil, nil, err
		}
		for id, p := range js {
			scores[jevPrefix+id] = p
		}
	}
	for _, a := range aspects {
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
