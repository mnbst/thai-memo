package sentence

import (
	"encoding/json"
	"os"
	"testing"
)

// selectGoldenPath は
// functions/python/scripts/daily_golden/gen_select_golden.py の出力。
// sentence_service.py の選定前段を変えたら再生成すること。
const selectGoldenPath = "../../testdata/python/daily_golden/select_golden.json"

type selectGolden struct {
	ChooseTopic []struct {
		Topic          string   `json:"topic"`
		IsPremium      bool     `json:"is_premium"`
		EstimatedVocab int      `json:"estimated_vocab"`
		RandValue      float64  `json:"rand_value"`
		ChoiceIndex    int      `json:"choice_index"`
		WantTopic      string   `json:"want_topic"`
		WantPool       []string `json:"want_pool"`
	} `json:"choose_topic"`
	ResolveInterviewTopic []struct {
		UserData    map[string]any `json:"user_data"`
		ChoiceIndex int            `json:"choice_index"`
		Want        string         `json:"want"`
	} `json:"resolve_interview_topic"`
}

func loadSelectGolden(t *testing.T) *selectGolden {
	t.Helper()
	b, err := os.ReadFile(selectGoldenPath)
	if err != nil {
		t.Fatalf("golden を読めない（gen_select_golden.py を実行したか？）: %v", err)
	}
	var g selectGolden
	if err := json.Unmarshal(b, &g); err != nil {
		t.Fatalf("golden の JSON 解析に失敗: %v", err)
	}
	return &g
}

func TestChooseTopicAgainstPythonGolden(t *testing.T) {
	g := loadSelectGolden(t)
	for ci, c := range g.ChooseTopic {
		// Python 側は random.random / random.choice を台本に差し替えている。
		// choice は候補列の長さで割った余りの位置を引く。
		got := ChooseTopic(
			c.Topic, c.IsPremium, c.EstimatedVocab,
			func() float64 { return c.RandValue },
			func(n int) int { return c.ChoiceIndex % n },
		)
		if got.Topic != c.WantTopic {
			t.Fatalf("case %d %+v: topic = %q, want %q", ci, c, got.Topic, c.WantTopic)
		}
		if !equalStringSlices(got.Pool, c.WantPool) {
			t.Fatalf("case %d %+v: pool = %v, want %v", ci, c, got.Pool, c.WantPool)
		}
	}
	t.Logf("テーマの決定 %dケース一致", len(g.ChooseTopic))
}

func TestResolveInterviewTopicAgainstPythonGolden(t *testing.T) {
	g := loadSelectGolden(t)
	for ci, c := range g.ResolveInterviewTopic {
		got := ResolveInterviewTopic(c.UserData, func(n int) int { return c.ChoiceIndex % n })
		if got != c.Want {
			t.Fatalf("case %d %v: = %q, want %q", ci, c.UserData, got, c.Want)
		}
	}
	t.Logf("ヒアリングからのテーマ決定 %dケース一致", len(g.ResolveInterviewTopic))
}

func equalStringSlices(a, b []string) bool {
	if len(a) != len(b) {
		return false
	}
	for i := range a {
		if a[i] != b[i] {
			return false
		}
	}
	return true
}
