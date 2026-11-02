package themeshots

import (
	"math/rand"
	"strings"
	"testing"

	"github.com/mnbst/thai-memo/functions/go/internal/bldrama"
	"github.com/mnbst/thai-memo/functions/go/internal/sentence"
)

// firstShot は topic の場面 scene に属する最初のショット ID。
func firstShot(t *testing.T, topic, scene string) string {
	t.Helper()
	for _, sc := range sceneCatalog()[topic] {
		if sc.name == scene {
			return sc.ids[0]
		}
	}
	t.Fatalf("%s に場面 %s が無い", topic, scene)
	return ""
}

// 場面 z だけ届いて、ショット z を満たす文が無い場面は選ばない。
func TestPickSceneNeedsShotZ(t *testing.T) {
	food := sentence.Topics[1]
	ok := firstShot(t, food, "値段を聞く")
	b := &Builder{Rand: rand.New(rand.NewSource(1)), Scenes: zScenes{
		"値段を聞く": 4, "売り切れ": 4, "shot:" + ok: 4,
	}}
	for range 200 {
		pick, found := b.PickScene("x", []string{food}, sentence.SceneZOmakase)
		if !found {
			t.Fatal("場面合致を通った場面があるのに選ばれない")
		}
		if pick.Topic != food || pick.Scene != "値段を聞く" || pick.ShotID != ok {
			t.Fatalf("ショット z の無い場面・ショットを選んだ: %+v", pick)
		}
	}
}

// 場面 z が閾値に届かなければ、ショット z が高くても選ばない。
func TestPickSceneNeedsSceneZ(t *testing.T) {
	food := sentence.Topics[1]
	id := firstShot(t, food, "値段を聞く")
	b := &Builder{Scenes: zScenes{"値段を聞く": 2.9, "shot:" + id: 9}}
	if b.HasScene("x", []string{food}, sentence.SceneZOmakase) {
		t.Error("z 2.9 の場面がおまかせ（3.0）で通った")
	}
	if !b.HasScene("x", []string{food}, sentence.SceneZPinned) {
		t.Error("z 2.9 の場面がテーマ指定（2.5）で通らない")
	}
}

// テーマ → 場面の順に一様に選ぶ。通った場面が3つのテーマと1つのテーマでも、
// テーマは半々になる。
func TestPickSceneEvenByTopic(t *testing.T) {
	food, weather := sentence.Topics[1], sentence.Topics[8]
	z := zScenes{}
	var foodScenes []string
	for _, sc := range sceneCatalog()[food][:3] {
		z[sc.name] = 4
		z["shot:"+sc.ids[0]] = 4
		foodScenes = append(foodScenes, sc.name)
	}
	ws := sceneCatalog()[weather][0]
	z[ws.name] = 4
	z["shot:"+ws.ids[0]] = 4

	b := &Builder{Rand: rand.New(rand.NewSource(2)), Scenes: z}
	n, got := 20000, 0
	for range n {
		pick, _ := b.PickScene("x", []string{food, weather}, sentence.SceneZOmakase)
		if pick.Topic == weather {
			got++
		}
	}
	if share := float64(got) / float64(n); share < 0.47 || share > 0.53 {
		t.Errorf("天気の割合 %.3f、テーマ単位で一様なら 0.5", share)
	}
}

// BL も同じ候補に入り、bldrama のショットで場面合致する。
func TestPickSceneIncludesBL(t *testing.T) {
	sh := bldrama.SceneShots()[0]
	b := &Builder{Scenes: zScenes{sh.Scene: 4, "shot:" + sh.ID: 4}}
	pick, ok := b.PickScene("x", []string{sentence.Topics[15]}, sentence.SceneZOmakase)
	if !ok || pick.Topic != sentence.Topics[15] || pick.ShotID != sh.ID {
		t.Fatalf("BL の場面が選ばれない: %+v ok=%v", pick, ok)
	}
}

// 選定時に決めたショットの断片には、場面と ID が付く。ID が無ければ雰囲気の3文を付ける。
func TestShotSectionByID(t *testing.T) {
	food := sentence.Topics[1]
	id := firstShot(t, food, "値段を聞く")
	b := &Builder{Rand: rand.New(rand.NewSource(1))}
	sec := b.ShotSection(food, id, sentence.Media[0].Name)
	if sec.Scene != "値段を聞く" || sec.ShotID != id || sec.Context == "" {
		t.Errorf("ショットの断片が違う: %+v", sec)
	}
	sec = b.ShotSection(food, "", sentence.Media[0].Name)
	if strings.Count(sec.Context, "\n  - ") != moodShots || sec.ShotID != "" || sec.Scene != "" {
		t.Errorf("雰囲気の3文になっていない: %+v", sec)
	}
}

// BL は性的な語にセリフを結びつけない（ショット無しで作る）。
func TestBLNoShotWords(t *testing.T) {
	id := sentence.Topics[15]
	var any string
	for _, sc := range sceneCatalog()[id] {
		any = "shot:" + sc.ids[0]
		break
	}
	z := zScenes{any: 9}
	for _, sc := range sceneCatalog()[id] {
		z[sc.name] = 9
	}
	b := &Builder{Scenes: z}
	if b.HasScene("ร่วมเพศ", []string{id}, sentence.SceneZPinned) {
		t.Error("性的な語に BL のセリフが付いた")
	}
	if !b.HasScene("กิน", []string{id}, sentence.SceneZPinned) {
		t.Error("ふつうの語に BL のセリフが付かない")
	}
}
