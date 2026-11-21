package sentence

import (
	"slices"
	"strings"
	"testing"

	"github.com/mnbst/thai-memo/functions/go/internal/lang"
)

func TestTimeFrameCandidates(t *testing.T) {
	cases := []struct {
		words   []string
		want    []string
		notWant []string
	}{
		// 時点を表す語は、その時点に絞られる。
		{words: []string{"เมื่อวาน"}, want: []string{TimeFrames[4]}, notWant: []string{TimeFrames[1], TimeFrames[2]}},
		{words: []string{"พรุ่งนี้"}, want: []string{TimeFrames[2]}, notWant: []string{TimeFrames[1], TimeFrames[4]}},
		{words: []string{"เมื่อกี้"}, want: []string{TimeFrames[1]}, notWant: []string{TimeFrames[2]}},
		// 時点を選ばない語は全時点。
		{words: []string{"ไม่"}, want: TimeFrames},
		// 表に無い語は絞らない。
		{words: []string{"未登録の語"}, want: TimeFrames},
		{words: nil, want: TimeFrames},
	}
	for _, c := range cases {
		got := TimeFrameCandidates(c.words)
		for _, w := range c.want {
			if !slices.Contains(got, w) {
				t.Errorf("%v: %q が候補に無い（%v）", c.words, w, got)
			}
		}
		for _, w := range c.notWant {
			if slices.Contains(got, w) {
				t.Errorf("%v: %q が候補に入っている（%v）", c.words, w, got)
			}
		}
	}
}

// 表の値の数が TimeFrames とずれると、その語は黙って絞り込みから外れる。
func TestTimeFrameTableMatchesTimeFrames(t *testing.T) {
	for w, probs := range loadTimeFrameFit() {
		if len(probs) != len(TimeFrames) {
			t.Fatalf("%s: 値 %d 個、TimeFrames は %d 個", w, len(probs), len(TimeFrames))
		}
	}
}

// 時点の要らないショットの回（DramaSection.NoTime）は、時点の行も context の timeFrame も出さない。
func TestBuildPromptNoTimeShot(t *testing.T) {
	resolved := ResolvedParams{Topic: Topics[1], TimeFrame: TimeFrames[1], Relation: "自分と対等／家族や恋人のように近い"}
	for _, noTime := range []bool{false, true} {
		prompt, rc := BuildPrompt(resolved, []string{"กิน"}, 800, true, lang.JA,
			DramaSection{Context: "- 場面: 注文する\n", NoTime: noTime})
		_, hasCtx := rc["timeFrame"]
		hasLine := strings.Contains(prompt, "話している時点")
		if hasCtx == noTime || hasLine == noTime {
			t.Errorf("NoTime=%v: context=%v line=%v", noTime, hasCtx, hasLine)
		}
	}
}

// 相手に向けていないショットの回（DramaSection.NoRelation）は、関係のブロックも context の relation も出さない。
func TestBuildPromptNoRelationShot(t *testing.T) {
	for _, resolved := range []ResolvedParams{
		{Topic: Topics[1], Relation: "自分と対等／家族や恋人のように近い"},
		{Topic: Topics[1], RelationStatus: "自分より目上", RelationSpeaker: "女性"},
	} {
		for _, noRel := range []bool{false, true} {
			prompt, rc := BuildPrompt(resolved, []string{"กิน"}, 800, true, lang.JA,
				DramaSection{Context: "- 場面: 昔話\n", NoRelation: noRel})
			_, hasCtx := rc["relation"]
			hasBlock := strings.Contains(prompt, "【話し手と聞き手】")
			if hasCtx == noRel || hasBlock == noRel {
				t.Errorf("%+v NoRelation=%v: context=%v block=%v", resolved, noRel, hasCtx, hasBlock)
			}
		}
	}
}
