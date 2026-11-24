package function

import (
	"testing"
	"time"
)

func TestFlaggedReviewData(t *testing.T) {
	created := time.Date(2026, 11, 21, 3, 0, 0, 0, time.UTC)
	flag := map[string]any{
		"sentence_doc": poolDoc(),
		"reason":       "訳の意味のずれ 0.55",
		"scores":       map[string]any{"tmean": 0.55},
		"judge_model":  "gemini-decision-1",
		"created_at":   created,
		"judged_at":    created.Add(time.Second),
	}
	data, ok := flaggedReviewData(flag)
	if !ok {
		t.Fatal("sentence_doc のある flag を落としている")
	}
	q, _ := data["quality"].(map[string]any)
	if q["passed"] != false || q["reason"] != "訳の意味のずれ 0.55" {
		t.Errorf("quality = %v, want passed=false と所見", q)
	}
	if data["created_at"] != created {
		t.Errorf("created_at = %v, want 生成時刻", data["created_at"])
	}
	if _, ok := poolDoc()["quality"]; ok {
		t.Fatal("元の sentence_doc を書き換えている")
	}
	e, ok := buildPoolEntry(data)
	if !ok {
		t.Fatal("確認待ちへ入れる形になっていない")
	}
	if e.Tier != "premium" || e.Sentence.KeyWord != "กิน" {
		t.Errorf("entry = %+v", e)
	}
}

func TestFlaggedReviewDataOld(t *testing.T) {
	// sentence_doc を残す前の flag は文の全体が無いので回さない。
	if _, ok := flaggedReviewData(map[string]any{"thai_text": "ผมกินข้าว"}); ok {
		t.Error("sentence_doc の無い flag を回している")
	}
}

func TestJudgeLabel(t *testing.T) {
	cases := []struct {
		data map[string]any
		want string
	}{
		{map[string]any{"quality": map[string]any{"passed": true}}, judgeOK},
		{map[string]any{"quality": map[string]any{"passed": false}}, judgeNG},
		{map[string]any{}, judgeNone},
	}
	for _, c := range cases {
		if got := judgeLabel(c.data); got != c.want {
			t.Errorf("judgeLabel(%v) = %q, want %q", c.data, got, c.want)
		}
	}
}
