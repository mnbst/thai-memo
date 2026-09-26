package quality

import (
	"context"
	"encoding/json"
	"os"
	"sort"
	"sync"
	"testing"

	"github.com/mnbst/thai-memo/functions/go/internal/lang"
)

// evalCase は testdata/judge_eval.json の1件。label は bad（欠陥）か good（正常）。
// 正常には、過去に誤検出された文も入れてある（閾値や問いを変えたときの回帰確認）。
type evalCase struct {
	ThaiText    string `json:"thai_text"`
	Translation string `json:"translation"`
	KeyWord     string `json:"key_word"`
	Lang        string `json:"lang"`
	Label       string `json:"label"`
	Class       string `json:"class"`
	Source      string `json:"source"`
}

// TestJudgeEvalLive は評価セットを実際の Jev にかけ、欠陥の検出数と正常の誤検出数を出す。
// 観点・閾値を変えたら回して前後を比べる。Jev は同じ文でも ±0.05 ほど揺れるので
// 合否は付けず、数と取りこぼし・誤検出の中身を出すだけにする。
//
//	TYPESAFE_API_KEY=... JUDGE_EVAL_LIVE=1 go test ./internal/quality -run TestJudgeEvalLive -v
func TestJudgeEvalLive(t *testing.T) {
	if os.Getenv("JUDGE_EVAL_LIVE") == "" {
		t.Skip("JUDGE_EVAL_LIVE が未設定")
	}
	raw, err := os.ReadFile("testdata/judge_eval.json")
	if err != nil {
		t.Fatal(err)
	}
	var cases []evalCase
	if err := json.Unmarshal(raw, &cases); err != nil {
		t.Fatal(err)
	}
	ctx := context.Background()
	j, err := NewJudge(ctx)
	if err != nil {
		t.Fatal(err)
	}

	reasons := make([]string, len(cases))
	flagged := make([]bool, len(cases))
	var wg sync.WaitGroup
	sem := make(chan struct{}, 8)
	for i, c := range cases {
		wg.Add(1)
		go func(i int, c evalCase) {
			defer wg.Done()
			sem <- struct{}{}
			defer func() { <-sem }()
			res, err := j.Review(ctx, []Candidate{{
				ThaiText: c.ThaiText, JapaneseTranslation: c.Translation,
				KeyWord: c.KeyWord, Lang: lang.Resolve(c.Lang),
			}})
			if err != nil {
				t.Errorf("%s: %v", c.ThaiText, err)
				return
			}
			if len(res.Verdicts) > 0 {
				flagged[i], reasons[i] = true, res.Verdicts[0].Reason
			}
		}(i, c)
	}
	wg.Wait()

	type tally struct{ hit, total int }
	byClass := map[string]*tally{}
	var bad, badHit, good, goodHit int
	for i, c := range cases {
		switch c.Label {
		case "bad":
			bad++
			tl := byClass[c.Class]
			if tl == nil {
				tl = &tally{}
				byClass[c.Class] = tl
			}
			tl.total++
			if flagged[i] {
				badHit++
				tl.hit++
			} else {
				t.Logf("取りこぼし [%s] %s | %s", c.Class, c.ThaiText, c.Translation)
			}
		case "good":
			good++
			if flagged[i] {
				goodHit++
				t.Logf("誤検出 (%s) %s | %s", reasons[i], c.ThaiText, c.Translation)
			}
		}
	}
	classes := make([]string, 0, len(byClass))
	for k := range byClass {
		classes = append(classes, k)
	}
	sort.Strings(classes)
	for _, k := range classes {
		t.Logf("  %s: %d/%d", k, byClass[k].hit, byClass[k].total)
	}
	t.Logf("欠陥の検出 %d/%d・正常の誤検出 %d/%d", badHit, bad, goodHit, good)
}
