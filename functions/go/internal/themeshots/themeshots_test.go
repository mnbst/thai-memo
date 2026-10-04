package themeshots

import (
	"context"
	"math/rand"
	"regexp"
	"strings"
	"testing"

	"github.com/mnbst/thai-memo/functions/go/internal/embeddings"
	"github.com/mnbst/thai-memo/functions/go/internal/sentence"
)

// ショットは字幕の文そのもの。英字（番組名・話者名）や注釈の括弧を混ぜない。
func TestShotsArePlainThai(t *testing.T) {
	bad := regexp.MustCompile(`[A-Za-z\[\]()（）【】:：]`)
	n := 0
	for topic, ts := range topicShots {
		if len(ts.ids) == 0 || ts.fallback == "" {
			t.Errorf("%s: 候補か代わりのやり取りが無い", topic)
		}
		n += len(ts.ids)
	}
	if n != len(shots) {
		t.Errorf("候補 %d 件とショット %d 件が合わない", n, len(shots))
	}
	for id, text := range shots {
		if strings.TrimSpace(text) == "" {
			t.Fatalf("%s: 本文が無い", id)
		}
		if bad.MatchString(text) {
			t.Errorf("%s: 文以外が混ざっている: %q", id, text)
		}
		if shotScene[id] == "" {
			t.Errorf("%s: 場面が無い", id)
		}
	}
}

func TestBuildShotSection(t *testing.T) {
	b := &Builder{Rand: rand.New(rand.NewSource(1))}

	got := b.BuildShotSection(sentence.Topics[1], []string{"อร่อย"})
	id := pickedID(t, got.Context)
	if !strings.Contains(got.Context, "- 場面: "+shotScene[id]) {
		t.Errorf("場面の行が無い: %q", got.Context)
	}
	if !strings.Contains(got.Required, "食事・注文のやり取りにする") {
		t.Errorf("場面を落としたときのやり取りがテーマに合っていない: %q", got.Required)
	}

	// 場面を落としたときのやり取りはテーマごとに変わる。
	if s := b.BuildShotSection(sentence.Topics[5], []string{"ราคา"}); !strings.Contains(s.Required, "買い物のやり取りにする") {
		t.Errorf("買い物のやり取りになっていない: %q", s.Required)
	}

	// ショットの無いテーマ（BL はドラマ側が持つ）には何も付けない。
	if s := b.BuildShotSection(sentence.Topics[15], []string{"รัก"}); s != (sentence.DramaSection{}) {
		t.Errorf("ショットの無いテーマに付いた: %+v", s)
	}
}

// pickedID は Context に入ったショットの ID を返す。
func pickedID(t *testing.T, ctx string) string {
	t.Helper()
	for _, id := range foodShotIDs {
		if strings.Contains(ctx, ": "+shots[id]+"\n") {
			return id
		}
	}
	t.Fatalf("ショットが入っていない: %q", ctx)
	return ""
}

type stubScenes struct{ scene string }

func (f stubScenes) FindBestScene(context.Context, string, []embeddings.Scene, float64) (string, error) {
	return f.scene, nil
}

// 語に近い場面があればその場面のショットだけから選び、無ければ全体から選ぶ。
func TestPickShotByScene(t *testing.T) {
	b := &Builder{Rand: rand.New(rand.NewSource(1)), Scenes: stubScenes{scene: "値段を聞く"}}
	for range 30 {
		id := b.PickShot(sentence.Topics[1], []string{"ราคา"})
		if shotScene[id] != "値段を聞く" {
			t.Fatalf("場面の外から選んだ: %s %s", id, shotScene[id])
		}
	}
	b = &Builder{Rand: rand.New(rand.NewSource(1)), Scenes: stubScenes{}}
	seen := map[string]bool{}
	for range 200 {
		seen[shotScene[b.PickShot(sentence.Topics[1], []string{"รัฐมนตรี"})]] = true
	}
	if len(seen) < 10 {
		t.Errorf("近い場面が無いのに場面が偏った: %d 種", len(seen))
	}
}

// まとめたテーマは、語に近い場面を持つ中身のテーマへ解決する。
// 同じ名前の場面が複数の中身にあれば、そのどれか。
func TestResolveGroup(t *testing.T) {
	b := &Builder{Rand: rand.New(rand.NewSource(1)), Scenes: stubScenes{scene: "薬を飲む"}}
	if got := b.ResolveGroup(sentence.LifeTopic, "ยา"); got != sentence.Topics[7] {
		t.Errorf("= %q, want 健康", got)
	}
	b = &Builder{Rand: rand.New(rand.NewSource(1)), Scenes: stubScenes{scene: "値段を聞く"}}
	for range 20 {
		got := b.ResolveGroup(sentence.TravelTopic, "ราคา")
		if got != sentence.Topics[1] && got != sentence.Topics[5] {
			t.Fatalf("= %q, want 食べ物か買い物", got)
		}
	}
	// 近い場面が無ければ決めない（呼び出し側が中身から選ぶ）。
	b = &Builder{Scenes: stubScenes{}}
	if got := b.ResolveGroup(sentence.LifeTopic, "x"); got != "" {
		t.Errorf("= %q, want 空", got)
	}
}
