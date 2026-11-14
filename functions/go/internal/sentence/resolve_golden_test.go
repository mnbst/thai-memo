package sentence

import (
	"context"
	"encoding/json"
	"github.com/mnbst/thai-memo/functions/go/internal/lang"
	"math/rand"
	"os"
	"reflect"
	"slices"
	"testing"
)

// resolve_golden.json は
// functions/python/scripts/daily_golden/gen_resolve_golden.py が
// 本物の prompts.resolve_generation_params を呼んで書き出したもの。

type resolveGolden struct {
	TopicOptions []struct {
		EstimatedVocab int      `json:"estimated_vocab"`
		Options        []string `json:"options"`
	} `json:"topic_options"`
	Params []struct {
		Params         map[string]any `json:"params"`
		Topic          string         `json:"topic"`
		TimeFrame      string         `json:"time_frame"`
		TimeFrameGiven bool           `json:"time_frame_given"`
		Relation       string         `json:"relation"`
		RelationGiven  bool           `json:"relation_given"`
		SubTheme       *string        `json:"sub_theme"`
	} `json:"params"`
	TimeFrames        []string            `json:"time_frames"`
	RelationStatuses  []string            `json:"relation_statuses"`
	RelationIntimacy  []string            `json:"relation_intimacy"`
	RelationSeparator string              `json:"relation_separator"`
	TopicSubThemes    map[string][]string `json:"topic_sub_themes"`
}

func loadResolveGolden(t *testing.T) *resolveGolden {
	t.Helper()
	raw, err := os.ReadFile("../../testdata/python/daily_golden/resolve_golden.json")
	if err != nil {
		t.Fatalf("golden の読み込みに失敗: %v", err)
	}
	var g resolveGolden
	if err := json.Unmarshal(raw, &g); err != nil {
		t.Fatal(err)
	}
	return &g
}

// TestTopicOptionsGolden は語彙スコアによるテーマ候補の絞り込みを見る。
// ここがずれると、入門者に上級テーマが出たり、上級者の選択肢が減ったりする。
func TestTopicOptionsGolden(t *testing.T) {
	g := loadResolveGolden(t)
	r := &Resolver{Rand: rand.New(rand.NewSource(1))}
	for _, c := range g.TopicOptions {
		got := r.Resolve(context.Background(), nil, nil, c.EstimatedVocab)
		// 語彙100以上のおまかせ候補からあいさつを外した（2026-11-06）。ゴールデンは移植元の値のまま。
		want := c.Options
		if c.EstimatedVocab >= omakaseGreetingMaxVocab {
			want = slices.DeleteFunc(slices.Clone(c.Options), func(t string) bool { return t == Topics[0] })
		}
		if !reflect.DeepEqual(got.TopicOptions, want) {
			t.Errorf("vocab=%d\ngot  %v\nwant %v",
				c.EstimatedVocab, got.TopicOptions, want)
		}
	}
	t.Logf("%d ケース一致", len(g.TopicOptions))
}

// TestResolveParamsGolden はクライアント指定値の扱いを見る。
//
// 未指定の timeFrame / relation は抽選なので値そのものは比べられない。
// 指定があればそのまま通すこと、無ければ候補集合から引くことを確かめる。
func TestResolveParamsGolden(t *testing.T) {
	g := loadResolveGolden(t)
	r := &Resolver{Rand: rand.New(rand.NewSource(20260827))}
	for i, c := range g.Params {
		got := r.Resolve(context.Background(), c.Params, nil, 1000)

		if got.Topic != c.Topic {
			t.Errorf("[%d] params=%v topic=%q want %q", i, c.Params, got.Topic, c.Topic)
		}
		if c.TimeFrameGiven {
			if got.TimeFrame != c.TimeFrame {
				t.Errorf("[%d] timeFrame=%q want %q", i, got.TimeFrame, c.TimeFrame)
			}
		} else if !contains(g.TimeFrames, got.TimeFrame) {
			t.Errorf("[%d] timeFrame=%q が候補外", i, got.TimeFrame)
		}

		if c.RelationGiven {
			if got.Relation != c.Relation {
				t.Errorf("[%d] relation=%q want %q", i, got.Relation, c.Relation)
			}
		} else if got.Relation != "" || !contains(g.RelationStatuses, got.RelationStatus) ||
			!contains(relationSpeakers, got.RelationSpeaker) {
			// 指定が無ければ地位と性別だけ引き、関係は LLM が決める。
			t.Errorf("[%d] relation=%q status=%q speaker=%q が候補外",
				i, got.Relation, got.RelationStatus, got.RelationSpeaker)
		}

		// SubThemes を渡していないのでサブテーマは付かない。
		if got.SubTheme != "" {
			t.Errorf("[%d] subTheme=%q が付いている", i, got.SubTheme)
		}
	}
	t.Logf("%d ケース一致", len(g.Params))
}

// TestDrawRelationCoverage は抽選が地位×親密度×話し手の性別を全て引けることを見る。
func TestDrawRelationCoverage(t *testing.T) {
	g := loadResolveGolden(t)
	r := &Resolver{Rand: rand.New(rand.NewSource(7))}
	seen := map[string]bool{}
	for i := 0; i < 3000; i++ {
		seen[r.DrawRelation()] = true
	}
	want := len(g.RelationStatuses) * len(g.RelationIntimacy) * len(relationSpeakers)
	if len(seen) != want {
		t.Errorf("組み合わせ %d 種 want %d", len(seen), want)
	}
	for _, s := range g.RelationStatuses {
		for _, in := range g.RelationIntimacy {
			for _, sp := range relationSpeakers {
				combo := s + g.RelationSeparator + in + g.RelationSeparator + sp
				if !seen[combo] {
					t.Errorf("引かれない組み合わせ: %q", combo)
				}
			}
		}
	}
}

// TestSubThemeSelection はサブテーマを持つテーマでだけ選出が走ることを見る。
func TestSubThemeSelection(t *testing.T) {
	g := loadResolveGolden(t)
	if len(g.TopicSubThemes) == 0 {
		t.Fatal("サブテーマを持つテーマが無い")
	}
	if !reflect.DeepEqual(topicSubThemes, g.TopicSubThemes) {
		t.Fatalf("TOPIC_SUB_THEMES 不一致")
	}

	finder := &fakeSubThemes{}
	r := &Resolver{Rand: rand.New(rand.NewSource(3)), SubThemes: finder}

	var withSub string
	for topic := range g.TopicSubThemes {
		withSub = topic
		break
	}

	// ターゲット語が無ければ選出しない。
	if got := r.Resolve(context.Background(),
		map[string]any{"topic": withSub}, nil, 1000); got.SubTheme != "" {
		t.Errorf("ターゲット語が無いのに subTheme=%q", got.SubTheme)
	}
	// サブテーマを持たないテーマでも選出しない。
	if got := r.Resolve(context.Background(),
		map[string]any{"topic": "存在しないテーマ"}, []string{"กิน"}, 1000,
	); got.SubTheme != "" {
		t.Errorf("候補が無いのに subTheme=%q", got.SubTheme)
	}
	// 両方揃えば先頭のターゲット語で引く。
	got := r.Resolve(context.Background(),
		map[string]any{"topic": withSub}, []string{"กิน", "ไป"}, 1000)
	if got.SubTheme == "" {
		t.Error("subTheme が付いていない")
	}
	if finder.word != "กิน" {
		t.Errorf("引いた語=%q want กิน", finder.word)
	}
	if !reflect.DeepEqual(finder.subThemes, g.TopicSubThemes[withSub]) {
		t.Errorf("候補=%v want %v", finder.subThemes, g.TopicSubThemes[withSub])
	}
}

type fakeSubThemes struct {
	word      string
	subThemes []string
}

func (f *fakeSubThemes) FindBestSubTheme(
	_ context.Context, word string, subThemes []string,
) (string, error) {
	f.word = word
	f.subThemes = subThemes
	return subThemes[0], nil
}

func contains(items []string, v string) bool {
	for _, item := range items {
		if item == v {
			return true
		}
	}
	return false
}

// 英語版はファン向けのサブテーマを候補から外す。日本語版・韓国語版は従来どおり。
func TestSubThemeSelectionDropsFanThemesForEN(t *testing.T) {
	const food = "食べ物（注文、感想、屋台、辛さ調整、アレルギー）"
	for _, name := range []string{"コラボカフェ", "ロケ地めぐり"} {
		if !fanSubThemes[name] {
			t.Fatalf("%s がファン向けに入っていない", name)
		}
	}
	for fan := range fanSubThemes {
		found := false
		for _, subs := range topicSubThemes {
			for _, s := range subs {
				found = found || s == fan
			}
		}
		if !found {
			t.Errorf("fanSubThemes の %q がどのテーマの候補にも無い", fan)
		}
	}

	for _, tc := range []struct {
		l       lang.Lang
		wantFan bool
	}{{lang.JA, true}, {lang.KO, true}, {lang.EN, false}} {
		finder := &fakeSubThemes{}
		r := &Resolver{Rand: rand.New(rand.NewSource(3)), SubThemes: finder}
		r.ResolveFor(context.Background(),
			map[string]any{"topic": food}, []string{"กิน"}, 1000, tc.l)
		hasFan := false
		for _, s := range finder.subThemes {
			hasFan = hasFan || fanSubThemes[s]
		}
		if hasFan != tc.wantFan {
			t.Errorf("%s: 候補にファン向けがある=%v want %v (%v)",
				tc.l, hasFan, tc.wantFan, finder.subThemes)
		}
		if len(finder.subThemes) == 0 {
			t.Errorf("%s: 候補が空", tc.l)
		}
	}
}
