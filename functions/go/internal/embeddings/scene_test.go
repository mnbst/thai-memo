package embeddings

import (
	"context"
	"math"
	"slices"
	"testing"
)

func sceneStore() *Store {
	return &Store{
		matrix:   [][]float32{{1, 0}},
		words:    []Word{{Word: "พริก"}},
		wordToIx: map[string]int{"พริก": 0},
		shotEmbs: map[string][]float32{
			"spicy1": {1, 0.1},
			"spicy2": {2, 0}, // 長さが違っても正規化して平均する
			"price1": {0, 1},
		},
	}
}

func TestFindNearScenes(t *testing.T) {
	scenes := []Scene{
		{Name: "辛さ", Texts: []string{"spicy1", "spicy2"}},
		{Name: "値段", Texts: []string{"price1"}},
		{Name: "未知", Texts: []string{"no-embedding"}},
	}
	s := sceneStore()
	if got, _ := s.FindNearScenes(context.Background(), "พริก", scenes, 0.9); !slices.Equal(got, []string{"辛さ"}) {
		t.Errorf("got %q, want [辛さ]", got)
	}
	// 下限を通った場面はすべて返す。
	if got, _ := s.FindNearScenes(context.Background(), "พริก", scenes, -1); !slices.Equal(got, []string{"辛さ", "値段"}) {
		t.Errorf("got %q, want [辛さ 値段]", got)
	}
	// 最も近い場面でも下限に届かなければ選ばない。
	if got, _ := s.FindNearScenes(context.Background(), "พริก", scenes, 0.9999); got != nil {
		t.Errorf("下限未満なのに %q", got)
	}
	if got, _ := s.FindNearScenes(context.Background(), "ไม่มี", scenes, 0); got != nil {
		t.Errorf("未知語で %q", got)
	}
}

// SceneScores は場面ごとに語彙全体との類似度で標準化する。どの語にも近い場面は
// 生の類似度が高くても z は上がらない。
func TestSceneScores(t *testing.T) {
	s := &Store{
		// 基準語は sceneRefStride 間隔で取るので、行0・行5が基準になる。
		matrix: [][]float32{
			{1, 0}, {0, 0}, {0, 0}, {0, 0}, {0, 0},
			{0.6, 0.8},
		},
		words:    []Word{{Word: "พริก"}, {}, {}, {}, {}, {Word: "x"}},
		wordToIx: map[string]int{"พริก": 0, "x": 5},
		shotEmbs: map[string][]float32{
			"spicy": {1, 0},
			"wide":  {0.8, 0.6}, // 基準語のどちらにも近い
			"price": {0, 1},
		},
	}
	scenes := []Scene{
		{Name: "辛さ", Texts: []string{"spicy"}},
		{Name: "汎用", Texts: []string{"wide"}},
		{Name: "値段", Texts: []string{"price"}},
		{Name: "未知", Texts: []string{"no-embedding"}},
	}
	z, err := s.SceneScores(context.Background(), "พริก", scenes)
	if err != nil || len(z) != 4 {
		t.Fatalf("z=%v err=%v", z, err)
	}
	// 生の類似度は 辛さ 1・汎用 0.8・値段 0。汎用はもう一方の基準語（0.96）の
	// ほうに近いので z は下側（-1）になり、辛さだけが上側（+1）に残る。
	for i, want := range []float64{1, -1, -1} {
		if math.Abs(z[i]-want) > 1e-9 {
			t.Errorf("%s: z=%v, want %v", scenes[i].Name, z[i], want)
		}
	}
	if !math.IsInf(z[3], -1) {
		t.Errorf("embedding の無い場面が -Inf でない: %v", z[3])
	}
	if z, _ := s.SceneScores(context.Background(), "ไม่มี", scenes); z != nil {
		t.Errorf("未知語で %v", z)
	}
}
