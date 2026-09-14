package function

import (
	"testing"

	"github.com/mnbst/thai-memo/functions/go/internal/lang"
	"github.com/mnbst/thai-memo/functions/go/internal/sentence"
)

func poolDoc() map[string]any {
	return map[string]any{
		"generation_tier":      "premium",
		"lang":                 "ja",
		"from_cache":           false,
		"thai_text":            "ผมกินข้าว",
		"pronunciation":        "phom kin khao",
		"japanese_translation": "ご飯を食べます",
		"key_word":             "กิน",
		"context":              map[string]any{"topic": "食べ物"},
		"word_breakdown": []any{
			map[string]any{"word": "กิน", "meaning": "食べる", "notes": ""},
		},
	}
}

func TestBuildPoolEntry(t *testing.T) {
	e, ok := buildPoolEntry(poolDoc())
	if !ok {
		t.Fatal("正常な doc を落としている")
	}
	if e.Lang != lang.JA {
		t.Errorf("lang = %q, want ja", e.Lang)
	}
	if e.Sentence.KeyWord != "กิน" {
		t.Errorf("key_word = %q, want กิน", e.Sentence.KeyWord)
	}
	// ティアはプールでは持たない（Pick した側が付け直す）。
	if e.Sentence.GenerationTier != "" {
		t.Errorf("generation_tier = %q, want 空", e.Sentence.GenerationTier)
	}
	if e.Sentence.Context["topic"] != "食べ物" {
		t.Errorf("context が落ちている: %+v", e.Sentence.Context)
	}
}

func TestBuildPoolEntrySkips(t *testing.T) {
	cases := []struct {
		name   string
		mutate func(map[string]any)
	}{
		// lang を付ける前に保存された doc。訳文の言語が決められない。
		{"lang なし", func(d map[string]any) { delete(d, "lang") }},
		{"lang 不明", func(d map[string]any) { d["lang"] = "th" }},
		{"key_word なし", func(d map[string]any) { delete(d, "key_word") }},
		// key_word から外した語（古語の一人称）。プールにも入れない。
		{"除外語", func(d map[string]any) { d["key_word"] = "ข้า" }},
		{"訳文なし", func(d map[string]any) { d["japanese_translation"] = "" }},
		{"分解なし", func(d map[string]any) { d["word_breakdown"] = []any{} }},
	}
	for _, c := range cases {
		d := poolDoc()
		c.mutate(d)
		if _, ok := buildPoolEntry(d); ok {
			t.Errorf("%s: 落とすべき doc を通している", c.name)
		}
	}
}

func TestMergePoolSkipsDuplicatesAndCaps(t *testing.T) {
	existing := []sentence.Sentence{{ThaiText: "a"}, {ThaiText: "b"}}
	incoming := []sentence.Sentence{{ThaiText: "b"}, {ThaiText: "c"}, {ThaiText: "c"}}

	merged, added := mergePool(existing, incoming, 10)
	if added != 1 {
		t.Errorf("added = %d, want 1（b は既存・c は入力内で重複）", added)
	}
	if len(merged) != 3 {
		t.Fatalf("プール件数 = %d, want 3", len(merged))
	}

	// 上限を超えたら古い側（先頭）から落とす。
	merged, _ = mergePool(existing, []sentence.Sentence{{ThaiText: "c"}}, 2)
	if len(merged) != 2 || merged[0].ThaiText != "b" || merged[1].ThaiText != "c" {
		t.Errorf("上限での切り詰めが古い側からになっていない: %+v", merged)
	}
}
