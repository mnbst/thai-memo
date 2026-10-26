package poolreview

import (
	"testing"

	"github.com/mnbst/thai-memo/functions/go/internal/sentence"
)

func TestMergePoolSkipsDuplicatesAndCaps(t *testing.T) {
	existing := []sentence.Sentence{{ThaiText: "a"}, {ThaiText: "b"}}
	incoming := []sentence.Sentence{{ThaiText: "b"}, {ThaiText: "c"}, {ThaiText: "c"}}

	merged, added := MergePool(existing, incoming, 10)
	if added != 1 {
		t.Errorf("added = %d, want 1（b は既存・c は入力内で重複）", added)
	}
	if len(merged) != 3 {
		t.Fatalf("プール件数 = %d, want 3", len(merged))
	}

	// 上限を超えたら古い側（先頭）から落とす。
	merged, _ = MergePool(existing, []sentence.Sentence{{ThaiText: "c"}}, 2)
	if len(merged) != 2 || merged[0].ThaiText != "b" || merged[1].ThaiText != "c" {
		t.Errorf("上限での切り詰めが古い側からになっていない: %+v", merged)
	}
}

func TestApplyFix(t *testing.T) {
	orig := map[string]any{
		"thai_text": "ab", "pronunciation": "a b", "japanese_translation": "旧訳", "key_word": "a",
		"word_breakdown": []any{map[string]any{"word": "a"}, map[string]any{"word": "b"}},
	}

	s, err := ApplyFix(orig, map[string]any{"japanese_translation": "新訳"})
	if err != nil || s.JapaneseTranslation != "新訳" || s.ThaiText != "ab" {
		t.Errorf("書いたキーだけ差し替わっていない: %+v %v", s, err)
	}

	// 本文だけ直して分解を直し忘れたら止める。
	if _, err := ApplyFix(orig, map[string]any{"thai_text": "ac"}); err == nil {
		t.Error("分解と本文の食い違いを通した")
	}
	// key_word を本文から消したら止める。
	if _, err := ApplyFix(orig, map[string]any{
		"thai_text": "cb", "word_breakdown": []any{map[string]any{"word": "c"}, map[string]any{"word": "b"}},
	}); err == nil {
		t.Error("key_word のない本文を通した")
	}
}
