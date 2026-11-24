package quality

import (
	"context"
	"encoding/json"
	"fmt"
	"maps"
	"os"
	"slices"
	"sync"
	"testing"

	"github.com/mnbst/thai-memo/functions/go/internal/lang"
	"github.com/mnbst/thai-memo/functions/go/internal/secrets"
)

// TestGeminiEvalLive は評価セット（EVAL_CASES、既定 testdata/judge_eval.json）の各文を本番と同じ経路
// （geminiAspects → Gemini.score）で判定し、観点ごとの確率を GEMINI_EVAL_OUT へ書く。
//
// 問いの文面を比べるときは QUESTION_VARIANTS に {"案の名前": {"観点ID": "問い"}} の JSON を渡す。
// 案ごとに geminiQuestions を差し替えて回し、"base"（今の文面）と並べて書き出す。
// Gemini は同じ文に毎回同じ点を返すので、1回ずつで比べられる。
//
//	JUDGE_EVAL_LIVE=1 GEMINI_EVAL_OUT=out.json go test ./internal/quality -run TestGeminiEvalLive -v
func TestGeminiEvalLive(t *testing.T) {
	if os.Getenv("JUDGE_EVAL_LIVE") == "" {
		t.Skip("JUDGE_EVAL_LIVE が未設定")
	}
	path := os.Getenv("EVAL_CASES")
	if path == "" {
		path = "testdata/judge_eval.json"
	}
	var cases []evalCase
	readJSON(t, path, &cases)
	variants := map[string]map[string]string{}
	if p := os.Getenv("QUESTION_VARIANTS"); p != "" {
		readJSON(t, p, &variants)
	}
	variants["base"] = map[string]string{}
	ctx := context.Background()
	key, err := secrets.Get(ctx, "gemini-api-key")
	if err != nil {
		t.Fatal(err)
	}
	g := &Gemini{APIKey: key}

	type row struct {
		Case   evalCase           `json:"case"`
		Scores map[string]float64 `json:"scores"`
	}
	out := map[string][]row{}
	orig := maps.Clone(geminiQuestions)
	t.Cleanup(func() { geminiQuestions = orig })
	for _, name := range slices.Sorted(maps.Keys(variants)) {
		geminiQuestions = maps.Clone(orig)
		maps.Copy(geminiQuestions, variants[name])
		rows := make([]row, len(cases))
		var wg sync.WaitGroup
		sem := make(chan struct{}, 4)
		for i, ec := range cases {
			wg.Add(1)
			go func(i int, ec evalCase) {
				defer wg.Done()
				sem <- struct{}{}
				defer func() { <-sem }()
				c := Candidate{ThaiText: ec.ThaiText, JapaneseTranslation: ec.Translation, KeyWord: ec.KeyWord, Lang: lang.Resolve(ec.Lang)}
				send, _ := geminiAspects(c, aspectsIn(slices.Concat(Aspects, PoolAspects), c))
				scores, err := g.score(ctx, c, send)
				if err != nil {
					t.Logf("%s %s: %v", name, ec.ThaiText, err)
				}
				rows[i] = row{Case: ec, Scores: scores}
			}(i, ec)
		}
		wg.Wait()
		out[name] = rows

		var bad, badHit, good, goodHit int
		for _, r := range rows {
			if r.Scores == nil {
				continue
			}
			hit := false
			for k, v := range r.Scores {
				th := geminiThreshold
				if x, ok := geminiThresholds[k]; ok {
					th = x
				}
				hit = hit || v > th
			}
			if r.Case.Label == "bad" {
				bad++
				if hit {
					badHit++
				}
			} else {
				good++
				if hit {
					goodHit++
				}
			}
		}
		t.Logf("%s: 欠陥 %d/%d・誤検出 %d/%d", name, badHit, bad, goodHit, good)
	}
	if p := os.Getenv("GEMINI_EVAL_OUT"); p != "" {
		raw, _ := json.MarshalIndent(out, "", " ")
		if err := os.WriteFile(p, raw, 0o644); err != nil {
			t.Fatal(fmt.Errorf("書き出し: %w", err))
		}
	}
}

func readJSON(t *testing.T, path string, v any) {
	t.Helper()
	raw, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if err := json.Unmarshal(raw, v); err != nil {
		t.Fatal(err)
	}
}
