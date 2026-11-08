package sentence

import "testing"

// 単語リストの「เร็ว ๆ」と分解の「เร็วๆ」は同じ語として引ける。
func TestKeyWordMeaningIgnoresSpaceBeforeYamok(t *testing.T) {
	s := &Sentence{WordBreakdown: []Word{{Word: "เร็วๆ", Meaning: "早く", Pronunciation: "rew-rew"}}}
	if got := s.KeyWordMeaning("เร็ว ๆ"); got != "早く" {
		t.Errorf("KeyWordMeaning = %q", got)
	}
	if got := s.KeyWordPronunciation("เร็ว ๆ"); got != "rew-rew" {
		t.Errorf("KeyWordPronunciation = %q", got)
	}
}

// 分解の語は単語リストの表記へそろえ、ほかの語は変えない。
func TestAlignTargetSpelling(t *testing.T) {
	s := &Sentence{WordBreakdown: []Word{{Word: "ทำ"}, {Word: "เร็วๆ"}, {Word: "ดีๆ"}}}
	alignTargetSpelling(s, []string{"เร็ว ๆ"})
	got := []string{s.WordBreakdown[0].Word, s.WordBreakdown[1].Word, s.WordBreakdown[2].Word}
	want := []string{"ทำ", "เร็ว ๆ", "ดีๆ"}
	for i := range want {
		if got[i] != want[i] {
			t.Errorf("word[%d] = %q, want %q", i, got[i], want[i])
		}
	}
}
