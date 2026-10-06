package sentence

import (
	"slices"
	"testing"
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
