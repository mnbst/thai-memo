package embeddings

import (
	"context"
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

func TestFindBestScene(t *testing.T) {
	scenes := []Scene{
		{Name: "辛さ", Texts: []string{"spicy1", "spicy2"}},
		{Name: "値段", Texts: []string{"price1"}},
		{Name: "未知", Texts: []string{"no-embedding"}},
	}
	s := sceneStore()
	if got, _ := s.FindBestScene(context.Background(), "พริก", scenes, 0.9); got != "辛さ" {
		t.Errorf("got %q, want 辛さ", got)
	}
	// 最も近い場面でも下限に届かなければ選ばない。
	if got, _ := s.FindBestScene(context.Background(), "พริก", scenes, 0.9999); got != "" {
		t.Errorf("下限未満なのに %q", got)
	}
	if got, _ := s.FindBestScene(context.Background(), "ไม่มี", scenes, 0); got != "" {
		t.Errorf("未知語で %q", got)
	}
}
