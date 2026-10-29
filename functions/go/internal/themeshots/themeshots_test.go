package themeshots

import (
	"context"
	"math"
	"math/rand"
	"regexp"
	"slices"
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

	got := b.BuildShotSection(sentence.Topics[1], []string{"อร่อย"}, "")
	id := pickedID(t, got.Context)
	situation := shotScene[id]
	if s, ok := shotSituation[id]; ok {
		situation = s
	}
	if !strings.Contains(got.Context, "- 場面: "+situation) {
		t.Errorf("場面の行が無い: %q", got.Context)
	}
	if !strings.Contains(got.Required, "食事・注文のやり取りにする") {
		t.Errorf("場面を落としたときのやり取りがテーマに合っていない: %q", got.Required)
	}

	// 場面を落としたときのやり取りはテーマごとに変わる。
	if s := b.BuildShotSection(sentence.Topics[5], []string{"ราคา"}, ""); !strings.Contains(s.Required, "買い物のやり取りにする") {
		t.Errorf("買い物のやり取りになっていない: %q", s.Required)
	}

	// ショットの無いテーマ（BL はドラマ側が持つ）には何も付けない。
	if s := b.BuildShotSection(sentence.Topics[15], []string{"รัก"}, ""); s.Context != "" || s.Required != "" || s.Medium != "" || len(s.NameKana) > 0 {
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

func (f stubScenes) FindNearScenes(context.Context, string, []embeddings.Scene, float64) ([]string, error) {
	if f.scene == "" {
		return nil, nil
	}
	return []string{f.scene}, nil
}

func (f stubScenes) SceneScores(_ context.Context, _ string, scenes []embeddings.Scene) ([]float64, error) {
	if f.scene == "" {
		return nil, nil
	}
	return multiScenes{f.scene}.SceneScores(context.Background(), "", scenes)
}

// multiScenes は挙げた場面だけ z を大きく返す（足切りでは通った場面）。
type multiScenes []string

func (f multiScenes) FindNearScenes(context.Context, string, []embeddings.Scene, float64) ([]string, error) {
	return f, nil
}

func (f multiScenes) SceneScores(_ context.Context, _ string, scenes []embeddings.Scene) ([]float64, error) {
	z := make([]float64, len(scenes))
	for i, sc := range scenes {
		if slices.Contains(f, sc.Name) {
			z[i] = 10
		}
	}
	return z, nil
}

// zScenes は場面ごとに決めた z を返す。挙げていない場面は 0。
type zScenes map[string]float64

func (f zScenes) FindNearScenes(context.Context, string, []embeddings.Scene, float64) ([]string, error) {
	return nil, nil
}

func (f zScenes) SceneScores(_ context.Context, _ string, scenes []embeddings.Scene) ([]float64, error) {
	z := make([]float64, len(scenes))
	for i, sc := range scenes {
		z[i] = f[sc.Name]
	}
	return z, nil
}

// 場面は exp(z / sceneTemp) の重みで選ぶ。z が sceneTemp だけ高い場面は e 倍出る。
func TestPickShotWeightedByZ(t *testing.T) {
	b := &Builder{Rand: rand.New(rand.NewSource(1)), Scenes: zScenes{"値段を聞く": sceneTemp}}
	names := sceneNames(foodShotIDs)
	n := 200000
	seen := map[string]int{}
	for range n {
		seen[shotScene[b.PickShot(sentence.Topics[1], []string{"ราคา"})]]++
	}
	want := math.E / (math.E + float64(len(names)-1))
	if got := float64(seen["値段を聞く"]) / float64(n); math.Abs(got-want) > 0.01 {
		t.Errorf("値段を聞く = %.3f, want %.3f", got, want)
	}
	if len(seen) != len(names) {
		t.Errorf("z の低い場面も出るはずが %d/%d 種", len(seen), len(names))
	}
}

// z の大きい場面が複数あれば、そのどれからも選ぶ。
func TestPickShotAmongNearScenes(t *testing.T) {
	b := &Builder{Rand: rand.New(rand.NewSource(1)), Scenes: multiScenes{"値段を聞く", "辛さを確かめる"}}
	seen := map[string]int{}
	for range 200 {
		seen[shotScene[b.PickShot(sentence.Topics[1], []string{"ราคา"})]]++
	}
	if len(seen) != 2 || seen["値段を聞く"] < 60 || seen["辛さを確かめる"] < 60 {
		t.Errorf("通った場面から一様に選んでいない: %v", seen)
	}
}

// 近い場面が無ければ、ショットの数によらず場面を一様に選ぶ。
func TestPickShotUniformScene(t *testing.T) {
	names := sceneNames(foodShotIDs)
	b := &Builder{Rand: rand.New(rand.NewSource(1)), Scenes: stubScenes{}}
	seen := map[string]int{}
	n := 300 * len(names)
	for range n {
		seen[shotScene[b.PickShot(sentence.Topics[1], []string{"รัฐมนตรี"})]]++
	}
	for _, name := range names {
		if c := seen[name]; c < 200 || c > 400 {
			t.Errorf("%s が %d 回（期待 300 前後）", name, c)
		}
	}
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

// 解説・紹介文の例文があるテーマはそれを付け、無いテーマ（あいさつ）は会話のショットに戻す。
func TestBuildShotSectionWritten(t *testing.T) {
	b := &Builder{Rand: rand.New(rand.NewSource(1))}
	written := sentence.Media[1].Name

	got := b.BuildShotSection(sentence.Topics[1], []string{"อร่อย"}, written)
	if got.Medium != written || strings.Contains(got.Context, "- 場面:") {
		t.Errorf("解説文の例文になっていない: %+v", got)
	}
	if got := b.BuildShotSection(sentence.Topics[0], []string{"สวัสดี"}, written); got.Medium != sentence.Media[0].Name {
		t.Errorf("あいさつが会話に戻っていない: %+v", got)
	}
	for topic, byMedium := range writtenShots {
		for medium := range byMedium {
			if medium != written {
				t.Errorf("%s: Media に無い媒体 %q", topic, medium)
			}
		}
	}
}
