package sentence

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"slices"
	"testing"
)

// selectGoldenPath は
// functions/python/scripts/daily_golden/gen_select_golden.py の出力。
// sentence_service.py の選定前段を変えたら再生成すること。
// 2026-11-06: 語彙100以上のおまかせ候補からあいさつを外した分は、生成元が無いので JSON を直接更新した。
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

// おまかせのあいさつは語彙100未満だけ。指定されたときは語彙によらず従来どおり。
func TestOmakaseGreetingOnlyForBeginners(t *testing.T) {
	greeting := Topics[0]
	for _, c := range []struct {
		vocab int
		want  bool
	}{{0, true}, {99, true}, {100, false}, {300, false}, {600, false}, {5000, false}} {
		if got := slices.Contains(OmakaseTopicPool(c.vocab), greeting); got != c.want {
			t.Errorf("vocab=%d: OmakaseTopicPool のあいさつ = %v", c.vocab, got)
		}
		premium := ChooseTopic("", true, c.vocab, func() float64 { return 1 }, func(int) int { return 0 })
		if got := slices.Contains(premium.Pool, greeting); got != c.want {
			t.Errorf("vocab=%d: premium の候補のあいさつ = %v", c.vocab, got)
		}
		free := false
		for i := range Topics {
			got := ChooseTopic("", false, c.vocab, func() float64 { return 1 }, func(n int) int { return i % n })
			free = free || got.Topic == greeting
		}
		if free != c.want {
			t.Errorf("vocab=%d: free であいさつを引くか = %v", c.vocab, free)
		}
		resolved := (&Resolver{}).Resolve(context.Background(), map[string]any{
			"topic": greeting, "timeFrame": "x", "relation": "x", "medium": "x", "style": "x", "emotion": "x",
		}, nil, c.vocab)
		if got := slices.Contains(resolved.TopicOptions, greeting); got != c.want || resolved.Topic != greeting {
			t.Errorf("vocab=%d: Resolve options のあいさつ = %v, topic = %q", c.vocab, got, resolved.Topic)
		}
		if got := ChooseTopic(greeting, true, c.vocab, nil, nil); got.Topic != greeting {
			t.Errorf("vocab=%d: 指定したあいさつが通らない: %q", c.vocab, got.Topic)
		}
	}
}

// あいさつの新規生成を止めるのは GreetingStopMinVersion 以降のアプリだけ。
func TestGreetingStoppedByAppVersion(t *testing.T) {
	v := GreetingStopMinVersion
	newApp := map[string]any{"app_version": fmt.Sprintf("%d.%d.%d", v[0], v[1], v[2])}
	oldApp := map[string]any{"app_version": fmt.Sprintf("%d.%d.%d", v[0], v[1], v[2]-1)}
	greeting, work := Topics[0], "仕事（報告・連絡・相談、打ち合わせ、残業申請、同僚雑談）"
	for _, c := range []struct {
		name  string
		user  map[string]any
		topic string
		want  bool
	}{
		{"新アプリ・正式名", newApp, greeting, true},
		{"新アプリ・短縮名", newApp, "あいさつ", true},
		{"新アプリ・別テーマ", newApp, work, false},
		{"新アプリ・未指定", newApp, "", false},
		{"旧アプリ", oldApp, greeting, false},
		{"版の記録なし", map[string]any{}, greeting, false},
	} {
		if got := GreetingGenerationStopped(c.user, c.topic); got != c.want {
			t.Errorf("%s: %v", c.name, got)
		}
	}
	interview := map[string]any{"goal": "work"}
	newApp["interview"], oldApp["interview"] = interview, interview
	seenOld := map[string]bool{}
	for i := 0; i < 2; i++ {
		pick := func(n int) int { return i % n }
		if got := ResolveInterviewTopic(newApp, pick); got != work {
			t.Errorf("新アプリのヒアリング: %q", got)
		}
		seenOld[ResolveInterviewTopic(oldApp, pick)] = true
	}
	if !seenOld[greeting] || !seenOld[work] {
		t.Errorf("旧アプリのヒアリング: %v", seenOld)
	}
}
