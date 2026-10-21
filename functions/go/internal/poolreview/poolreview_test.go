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
