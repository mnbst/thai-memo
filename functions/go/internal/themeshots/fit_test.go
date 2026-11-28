package themeshots

import (
	"context"
	"strings"
	"testing"

	"github.com/mnbst/thai-memo/functions/go/internal/sentence"
)

type fakeAsker struct{ inputs []string }

func (f *fakeAsker) Ask(_ context.Context, input string, q map[string]string) (map[string]float64, error) {
	f.inputs = append(f.inputs, input)
	return map[string]float64{"fit": 0.5}, nil
}

// 入力は測ったときと同じキー順。場面名の出どころの印は外し、BL はドラマの場面名を使う。
func TestFitInput(t *testing.T) {
	got := fitInput("แว่น", sentence.ScenePick{Topic: sentence.Topics[5], ShotID: "shop_389"})
	if !strings.HasPrefix(got, `{"key_word":"แว่น","scene":"スマホ用品を探す","situation":"平日の夕方`) {
		t.Errorf("theme: %s", got)
	}
	got = fitInput("บุก", sentence.ScenePick{Topic: sentence.Topics[15], ShotID: "ob_39"})
	if !strings.Contains(got, `"scene":"市場からの帰りが遅いと叱る","situation":"市場からの帰りが遅いと叱る","example":"รีบเอาผักไปล้างเลย`) {
		t.Errorf("BL: %s", got)
	}
}

func TestSceneFit(t *testing.T) {
	a := &fakeAsker{}
	f := &FitScorer{Asker: a}
	got, err := f.SceneFit(context.Background(), "แว่น", []sentence.ScenePick{
		{Topic: sentence.Topics[5], ShotID: "shop_389"}, {Topic: sentence.Topics[5], ShotID: "shop_260"},
	})
	if err != nil || len(got) != 2 || len(a.inputs) != 2 {
		t.Fatalf("got=%v err=%v inputs=%d", got, err, len(a.inputs))
	}
}
