package sentence

import (
	"context"
	"math"
	"slices"
	"strings"
	"testing"
)

// fakeMatcher は words に挙げた語だけ pick を返す。
type fakeMatcher map[string]ScenePick

func (f fakeMatcher) PickScene(word string, _ []string, _ float64) (ScenePick, bool) {
	p, ok := f[word]
	return p, ok
}

func (f fakeMatcher) HasScene(word string, topics []string, z float64) bool {
	_, ok := f.PickScene(word, topics, z)
	return ok
}

// テーマ指定は合う場面が無くても指定テーマのまま。まとめたテーマは中身に解決する。
// おまかせで合わなければテーマも空（LLM が候補から選ぶ）。
func TestAssignScenes(t *testing.T) {
	s := &TargetWordSelector{Scenes: fakeMatcher{
		"กิน": {Topic: Topics[1], Scene: "注文する", ShotID: "food_001"},
	}}

	got := s.assignScenes([]string{"กิน", "แต่"}, TopicChoice{Topic: Topics[7]})
	if got[0].Topic != Topics[1] || got[0].ShotID != "food_001" || !got[0].Matched {
		t.Errorf("合う語: %+v", got[0])
	}
	if got[1].Topic != Topics[7] || got[1].ShotID != "" || !got[1].Matched {
		t.Errorf("テーマ指定で合わない語は指定テーマのままショット無し: %+v", got[1])
	}

	got = s.assignScenes([]string{"แต่"}, TopicChoice{Topic: LifeTopic})
	if got[0].Group != LifeTopic || !slices.Contains(TopicGroups[LifeTopic], got[0].Topic) {
		t.Errorf("まとめたテーマは中身に解決する: %+v", got[0])
	}

	got = s.assignScenes([]string{"แต่"}, TopicChoice{Pool: Topics})
	if got[0].Topic != "" || got[0].ShotID != "" {
		t.Errorf("おまかせで合わない語はテーマも空: %+v", got[0])
	}

	// 推し活も合わない語は推し活のまま（テーマ以外の例文を混ぜない）。
	got = s.assignScenes([]string{"แต่"}, TopicChoice{Topic: OshiTopic, Pool: Topics})
	if got[0].Topic != OshiTopic || got[0].ShotID != "" {
		t.Errorf("推し活で合わない語も推し活のまま: %+v", got[0])
	}
}

// 場面合致の回はサブテーマを引かず、選定時のショットをそのまま使う。
func TestResolveSceneMatched(t *testing.T) {
	r := (&Resolver{}).Resolve(context.Background(), map[string]any{
		"topic": Topics[1], sceneMatchedParam: true, shotIDParam: "food_001",
	}, []string{"กิน"}, 500)
	if !r.SceneMatched || r.ShotID != "food_001" || r.SubTheme != "" {
		t.Errorf("resolved=%+v", r)
	}
}

// 場面合致でショットが付かない回は、ショットを付けずに会話へ戻す。
func TestMatchedSectionNoShot(t *testing.T) {
	svc := &Service{Shots: fixedShots{}}
	r := ResolvedParams{Topic: Topics[1], Medium: Media[1].Name, SceneMatched: true, SubTheme: "x"}
	if sec := svc.SceneSection(&r, []string{"กิน"}); sec.Context != "" {
		t.Errorf("ショット無しなのに断片が付いた: %q", sec.Context)
	}
	if r.Medium != Media[0].Name || r.SubTheme != "" {
		t.Errorf("resolved=%+v", r)
	}
}

// BL でショットが付かない回は、ドラマのブロックの代わりにテーマの行を出す。
func TestBLWithoutShotKeepsTopicLine(t *testing.T) {
	r := ResolvedParams{Topic: Topics[15], SceneMatched: true}
	prompt, _ := BuildPrompt(r, []string{"รัก"}, 500, true, "ja", DramaSection{})
	if !strings.Contains(prompt, "- テーマ: "+TopicLabel(Topics[15])+"\n") {
		t.Errorf("BL のテーマ行が無い:\n%s", prompt)
	}
}

// LLM が返したテーマは正式名へ戻し、候補に無いテーマは捨てる。確定済みは触らない。
func TestCanonicalizeTopic(t *testing.T) {
	for in, want := range map[string]string{
		"趣味": Topics[9], Topics[9]: Topics[9], "Hobbies": Topics[9], "人生・哲学": "",
	} {
		s := &Sentence{Context: map[string]any{"topic": in}}
		canonicalizeTopic(s, map[string]any{})
		got, _ := s.Context["topic"].(string)
		if got != want {
			t.Errorf("%q → %q, want %q", in, got, want)
		}
	}
	s := &Sentence{Context: map[string]any{"topic": "x"}}
	canonicalizeTopic(s, map[string]any{"topic": "x"})
	if s.Context["topic"] != "x" {
		t.Error("確定済みのテーマを書き換えた")
	}
}

// 場面の少ないテーマはテーマ指定のときだけ場面で絞らずショットで比べる。
func TestSceneThresholds(t *testing.T) {
	if sc, sh := SceneThresholds(Topics[4], SceneZPinned); !math.IsInf(sc, -1) || sh != ShotZShotFirst {
		t.Errorf("家族のテーマ指定: %v %v", sc, sh)
	}
	if sc, sh := SceneThresholds(OshiTopic, SceneZOmakase); sc != SceneZOmakase || sh != ShotZ {
		t.Errorf("おまかせは従来どおり: %v %v", sc, sh)
	}
	if sc, sh := SceneThresholds(BLTopic, SceneZPinned); sc != 2.5 || sh != ShotZ {
		t.Errorf("BL は 2.5 のまま: %v %v", sc, sh)
	}
	if sc, _ := SceneThresholds(Topics[14], SceneZPinned); sc != 1.5 {
		t.Errorf("恋愛は 1.5: %v", sc)
	}
	if sc, _ := SceneThresholds(Topics[1], SceneZPinned); sc != SceneZPinned {
		t.Errorf("食べ物は既定値: %v", sc)
	}
}
