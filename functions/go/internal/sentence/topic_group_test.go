package sentence

import (
	"context"
	"math/rand"
	"slices"
	"testing"

	"github.com/mnbst/thai-memo/functions/go/internal/lang"
)

// まとめたテーマの中身は、どれも個別テーマの一覧にある。
func TestTopicGroupsMembersAreTopics(t *testing.T) {
	for group, members := range TopicGroups {
		if slices.Contains(Topics, group) {
			t.Errorf("%s: まとめたテーマが個別テーマの一覧に入っている", group)
		}
		if len(members) == 0 {
			t.Errorf("%s: 中身が無い", group)
		}
		for _, m := range members {
			if !slices.Contains(Topics, m) {
				t.Errorf("%s: 中身 %q が個別テーマに無い", group, m)
			}
		}
	}
}

type stubGroups struct{ topic string }

func (g stubGroups) ResolveGroup(string, string) string { return g.topic }

// まとめたテーマは語ごとに中身の1つへ解決し、頼まれた値を Group に残す。
func TestResolveGroupTopic(t *testing.T) {
	s := &TargetWordSelector{Groups: stubGroups{topic: Topics[7]}}
	tw := TargetWord{Word: "ยา", Topic: LifeTopic}
	s.resolveGroup(&tw)
	if tw.Topic != Topics[7] || tw.Group != LifeTopic {
		t.Errorf("= %+v, want 健康に解決して Group にタイ暮らし", tw)
	}

	// 解決器が決められなければ中身から選ぶ。
	s = &TargetWordSelector{Groups: stubGroups{}, Rand: rand.New(rand.NewSource(1))}
	for range 20 {
		tw := TargetWord{Word: "x", Topic: TravelTopic}
		s.resolveGroup(&tw)
		if !slices.Contains(TopicGroups[TravelTopic], tw.Topic) {
			t.Fatalf("中身の外へ解決した: %q", tw.Topic)
		}
	}

	// まとめたテーマでなければ触らない。
	tw = TargetWord{Word: "x", Topic: Topics[15]}
	s.resolveGroup(&tw)
	if tw.Topic != Topics[15] || tw.Group != "" {
		t.Errorf("個別テーマが変わった: %+v", tw)
	}
}

// topicBank は (語, テーマ) が stock にある文だけ返す。
type topicBank struct {
	stock map[[2]string]bool
	calls []string
}

func (b *topicBank) Pick(
	_ context.Context, w string, _ lang.Lang, topic string, _ bool,
) (*Sentence, error) {
	b.calls = append(b.calls, topic)
	if !b.stock[[2]string{w, topic}] {
		return nil, nil
	}
	return &Sentence{ThaiText: w + topic, Context: map[string]any{"topic": topic}}, nil
}

// 解決した個別テーマに在庫が無ければ、同じまとめの他の中身から引く。
func TestPickCachedFallsBackWithinGroup(t *testing.T) {
	bank := &topicBank{stock: map[[2]string]bool{{"ราคา", Topics[1]}: true}}
	tw := TargetWord{Word: "ราคา", Topic: Topics[6], Group: LifeTopic}
	got, topic, err := pickCached(context.Background(), bank, tw, lang.JA, true)
	if err != nil {
		t.Fatal(err)
	}
	if got == nil || topic != Topics[1] {
		t.Fatalf("= %v %q, want 食べ物の在庫", got, topic)
	}

	// まとめたテーマでなければ他のテーマを見ない。
	bank.calls = nil
	tw = TargetWord{Word: "ราคา", Topic: Topics[6]}
	if got, _, _ := pickCached(context.Background(), bank, tw, lang.JA, true); got != nil {
		t.Errorf("指定外のテーマから引いた: %v", got)
	}
	if len(bank.calls) != 1 {
		t.Errorf("引いた回数 %d, want 1", len(bank.calls))
	}
}
