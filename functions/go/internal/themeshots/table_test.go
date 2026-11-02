package themeshots

import (
	"context"
	"encoding/json"
	"errors"
	"reflect"
	"testing"

	"github.com/mnbst/thai-memo/functions/go/internal/sentence"
)

// blobs は名前 → 中身。無い名前はエラー。
type blobs map[string][]byte

func (f blobs) Blob(_ context.Context, name string) ([]byte, error) {
	if b, ok := f[name]; ok {
		return b, nil
	}
	return nil, errors.New("not found")
}

// 表を引いた結果は、その場で計算した結果と同じ。
func TestMatchTableSameAsLive(t *testing.T) {
	food := sentence.Topics[1]
	id := firstShot(t, food, "値段を聞く")
	live := &Builder{Scenes: zScenes{"値段を聞く": 3.2, "売り切れ": 2.6, "shot:" + id: 3.8}}
	raw, err := json.Marshal(live.BuildMatchTable([]string{"x"}))
	if err != nil {
		t.Fatal(err)
	}
	tab := &Builder{Scenes: live.Scenes, Tables: blobs{MatchTableBlob: raw}}
	for _, tc := range []struct {
		topics []string
		z      float64
	}{
		{[]string{food}, sentence.SceneZPinned},
		{sentence.Topics, sentence.SceneZOmakase},
		{[]string{sentence.OshiTopic}, sentence.SceneZPinned},
	} {
		want := live.matchScenes("x", tc.topics, tc.z)
		if got := tab.matchScenes("x", tc.topics, tc.z); !reflect.DeepEqual(got, want) {
			t.Errorf("topics=%v z=%v: 表 %+v, その場 %+v", tc.topics, tc.z, got, want)
		}
	}
	if tab.table == nil {
		t.Fatal("表を使っていない")
	}
	if !tab.HasScene("x", []string{food}, sentence.SceneZPinned) {
		t.Error("表から場面合致が引けない")
	}
}

// 版の合わない表・読めない表は使わず、その場で計算する。
func TestMatchTableFallback(t *testing.T) {
	scenes := zScenes{"値段を聞く": 3.2, "shot:" + firstShot(t, sentence.Topics[1], "値段を聞く"): 3.8}
	stale, _ := json.Marshal(&MatchTable{Version: "old", Rows: map[string]TableRow{}})
	for name, src := range map[string]BlobSource{
		"版が古い": blobs{MatchTableBlob: stale},
		"無い":   blobs{},
	} {
		b := &Builder{Scenes: scenes, Tables: src}
		if !b.HasScene("x", []string{sentence.Topics[1]}, sentence.SceneZPinned) {
			t.Errorf("%s: その場の計算に戻っていない", name)
		}
		if b.table != nil {
			t.Errorf("%s: 使えない表を使った", name)
		}
	}
}

// 表の下限はどのテーマの閾値より低い（下回ると表から当たりが落ちる）。
func TestMinShotZBelowThresholds(t *testing.T) {
	for _, topic := range append(sentence.Topics, "") {
		for _, z := range []float64{sentence.SceneZPinned, sentence.SceneZOmakase} {
			if _, shotMin := sentence.SceneThresholds(topic, z); shotMin < minShotZ {
				t.Errorf("%s: ショット z の閾値 %v が表の下限 %v より低い", topic, shotMin, minShotZ)
			}
		}
	}
}
