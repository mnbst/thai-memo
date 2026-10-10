package function

import "testing"

// TestIsSentenceViewed は既読判定の互換ルールを固定する。
// フィールドが無い＝既読扱い、false が入っているときだけ未読。
func TestIsSentenceViewed(t *testing.T) {
	cases := []struct {
		name string
		data map[string]any
		want bool
	}{
		{"フィールド無しは既読扱い", map[string]any{"thai_text": "ก"}, true},
		{"false は未読", map[string]any{"viewed": false}, false},
		{"true は既読", map[string]any{"viewed": true}, true},
		{"bool 以外は既読扱い", map[string]any{"viewed": "false"}, true},
		{"nil は既読扱い", map[string]any{"viewed": nil}, true},
	}
	for _, c := range cases {
		if got := isSentenceViewed(c.data); got != c.want {
			t.Errorf("%s: isSentenceViewed = %v, want %v", c.name, got, c.want)
		}
	}
}

// TestSelectionSrsBudget は SRS 枠が周をまたいで数えられることを確かめる。
// 既読だけの周で枠を使い切っていたら、未読の周では SRS から足さない。
func TestSelectionSrsBudget(t *testing.T) {
	sel := newSelection(maxQuestions)
	for i := 0; i < maxSrsSentences; i++ {
		sel.add(selectedSentence{
			ID: string(rune('a' + i)), Data: map[string]any{"key_word": "กิน"}, SrsInterval: 1,
		})
	}
	if sel.srsCount != maxSrsSentences {
		t.Errorf("srsCount = %d, want %d", sel.srsCount, maxSrsSentences)
	}
	sel.add(selectedSentence{ID: "filler", Data: map[string]any{}, SrsInterval: -1})
	if sel.srsCount != maxSrsSentences {
		t.Errorf("補充で SRS 枠が増えている: %d", sel.srsCount)
	}
	if !sel.usedKeyWords["กิน"] {
		t.Error("key_word が記録されていない")
	}
	if sel.full() {
		t.Errorf("maxQuestions=%d 未満なのに full", maxQuestions)
	}
	for i := len(sel.sentences); i < maxQuestions; i++ {
		sel.add(selectedSentence{ID: string(rune('A' + i)), Data: map[string]any{}, SrsInterval: -1})
	}
	if !sel.full() {
		t.Error("maxQuestions まで選んでも full にならない")
	}
}

// TestSelectionLimit は入門者の短いクイズで、問題数と SRS 枠が
// セット本数に合わせて縮むことを確かめる。
func TestSelectionLimit(t *testing.T) {
	cases := []struct {
		limit, wantLimit, wantSrs int
	}{
		{2, 2, 1},
		{3, 3, 1},
		{4, 4, 2},
		{5, 5, maxSrsSentences},
		{9, maxQuestions, maxSrsSentences},
	}
	for _, c := range cases {
		sel := newSelection(c.limit)
		if sel.limit != c.wantLimit || sel.srsLimit() != c.wantSrs {
			t.Errorf("limit=%d: got limit=%d srs=%d, want %d/%d",
				c.limit, sel.limit, sel.srsLimit(), c.wantLimit, c.wantSrs)
		}
	}

	sel := newSelection(2)
	sel.add(selectedSentence{ID: "a", Data: map[string]any{}})
	if sel.full() {
		t.Error("1問で full")
	}
	sel.add(selectedSentence{ID: "b", Data: map[string]any{}})
	if !sel.full() {
		t.Error("2問で full にならない")
	}
}
