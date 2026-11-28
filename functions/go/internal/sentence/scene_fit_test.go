package sentence

import (
	"context"
	"errors"
	"testing"
)

// fakeCandidates は語ごとに固定の候補を返す SceneMatcher / SceneCandidates。
type fakeCandidates map[string][]ScenePick

func (f fakeCandidates) PickScene(word string, _ []string, _ float64) (ScenePick, bool) {
	if c := f[word]; len(c) > 0 {
		return c[0], true
	}
	return ScenePick{}, false
}

func (f fakeCandidates) HasScene(word string, topics []string, z float64) bool {
	_, ok := f.PickScene(word, topics, z)
	return ok
}

func (f fakeCandidates) PickScenes(word string, _ []string, _ float64, n int) []ScenePick {
	c := f[word]
	return c[:min(n, len(c))]
}

func (f fakeCandidates) PickScenesExcept(word string, _ []string, _ float64, used map[string]bool, _, n int) []ScenePick {
	var out []ScenePick
	for _, p := range f[word] {
		if !used[p.Scene] && len(out) < n {
			out = append(out, p)
		}
	}
	return out
}

func (f fakeCandidates) PickSceneExcept(word string, topics []string, z float64, used map[string]bool, unknown int) (ScenePick, bool) {
	if c := f.PickScenesExcept(word, topics, z, used, unknown, 1); len(c) > 0 {
		return c[0], true
	}
	return ScenePick{}, false
}

// fakeFitter はショット ID ごとの点を返す。err があれば常に失敗する。
type fakeFitter struct {
	scores map[string]float64
	err    error
}

func (f fakeFitter) SceneFit(_ context.Context, _ string, picks []ScenePick) ([]float64, error) {
	if f.err != nil {
		return nil, f.err
	}
	out := make([]float64, len(picks))
	for i, p := range picks {
		out[i] = f.scores[p.ShotID]
	}
	return out, nil
}

var fitCands = fakeCandidates{
	"แว่น": {
		{Topic: Topics[5], Scene: "スマホ用品を探す", ShotID: "shop_389"},
		{Topic: Topics[5], Scene: "品物を選ぶ", ShotID: "shop_260"},
		{Topic: Topics[5], Scene: "店員に相談する", ShotID: "shop_391"},
	},
	"บุก": {{Topic: Topics[15], Scene: "市場からの帰りが遅いと叱る", ShotID: "ob_39"}},
}

// 点のいちばん高い候補を使い、全部が SceneFitMin 未満ならショットを付けない。
// 採点に失敗したら1つ目の候補（従来の選び方）に戻す。
func TestAssignScenesFit(t *testing.T) {
	s := &TargetWordSelector{Scenes: fitCands, Fit: fakeFitter{scores: map[string]float64{
		"shop_389": 0.06, "shop_260": 0.91, "shop_391": 0.40, "ob_39": 0.07,
	}}}
	got := s.assignScenes(context.Background(), []string{"แว่น", "บุก", "ไม่มี"}, TopicChoice{Topic: Topics[5]})
	if got[0].ShotID != "shop_260" {
		t.Errorf("แว่น: 点の高い shop_260 のはず: %+v", got[0])
	}
	if got[1].ShotID != "" {
		t.Errorf("บุก: 全部 %.1f 未満ならショットなし: %+v", SceneFitMin, got[1])
	}
	if got[2].ShotID != "" || got[2].Topic != Topics[5] {
		t.Errorf("候補の無い語は指定テーマのままショットなし: %+v", got[2])
	}

	s.Fit = fakeFitter{err: errors.New("down")}
	got = s.assignScenes(context.Background(), []string{"แว่น"}, TopicChoice{Topic: Topics[5]})
	if got[0].ShotID != "shop_389" {
		t.Errorf("採点に失敗したら1つ目の候補: %+v", got[0])
	}
}

// 作り直しも同じ選び方。使った場面は候補から外れ、合う場面が残らなければ作り直さない。
func TestFreshSceneTargetFit(t *testing.T) {
	s := &TargetWordSelector{Scenes: fitCands, Fit: fakeFitter{scores: map[string]float64{
		"shop_389": 0.06, "shop_260": 0.91, "shop_391": 0.40,
	}}}
	tw, ok := s.FreshSceneTarget("แว่น", Topics[5], map[string]bool{"品物を選ぶ": true}, 0)
	if !ok || tw.ShotID != "shop_391" {
		t.Errorf("使っていない場面で点の高い shop_391 のはず: %+v %v", tw, ok)
	}
	if _, ok := s.FreshSceneTarget("แว่น", Topics[5], map[string]bool{"品物を選ぶ": true, "店員に相談する": true}, 0); ok {
		t.Error("残る場面が SceneFitMin 未満なら作り直さない")
	}
}
