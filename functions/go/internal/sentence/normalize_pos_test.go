package sentence

import (
	"testing"

	"github.com/mnbst/thai-memo/functions/go/internal/lang"
)

func TestNormalizePOS(t *testing.T) {
	s := Sentence{WordBreakdown: []Word{
		{Word: "ทำ", GrammaticalRole: "動詞"},
		{Word: "ทุกอย่าง", GrammaticalRole: "副詞"},
		{Word: "ให้", GrammaticalRole: "受益標識"},
		{Word: "มึง", GrammaticalRole: "代名詞"},
		{Word: "วะ", GrammaticalRole: "文末詞"},
	}}
	n, err := NormalizePOS(&s, lang.JA)
	if err != nil {
		t.Fatal(err)
	}
	if n != 2 {
		t.Errorf("n = %d, want 2", n)
	}
	want := []string{"動詞", "副詞", "前置詞", "代名詞", "助詞"}
	for i, w := range s.WordBreakdown {
		if w.GrammaticalRole != want[i] {
			t.Errorf("[%d] %s = %q, want %q", i, w.Word, w.GrammaticalRole, want[i])
		}
	}

	en := Sentence{WordBreakdown: []Word{{Word: "ค่ะ", GrammaticalRole: "文末詞"}, {Word: "ไป", GrammaticalRole: "verb"}}}
	if _, err := NormalizePOS(&en, lang.EN); err != nil {
		t.Fatal(err)
	}
	if en.WordBreakdown[0].GrammaticalRole != "particle" || en.WordBreakdown[1].GrammaticalRole != "verb" {
		t.Errorf("en = %+v", en.WordBreakdown)
	}
}
