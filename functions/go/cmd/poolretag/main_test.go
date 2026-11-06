package main

import (
	"testing"

	"github.com/mnbst/thai-memo/functions/go/internal/lang"
)

func TestHighConfidence(t *testing.T) {
	cases := []struct {
		word, meaning, tag string
		l                  lang.Lang
		want               bool
	}{
		{"พรุ่งนี้", "明日", "名詞", lang.JA, true},
		{"พรุ่งนี้", "明日", "副詞", lang.JA, false},
		{"ของ", "物", "名詞", lang.JA, true},
		{"ไป", "行く", "動詞", lang.JA, true},
		{"ไป", "〜してしまう", "動詞", lang.JA, false},
		{"ไป", "行く", "助動詞", lang.JA, false},
		{"ไป", "〜してしまう", "助動詞", lang.JA, true},
		{"ไป", "to go", "動詞", lang.EN, true},
		{"ไป", "to go", "助動詞", lang.EN, false},
		{"ไป", "가다", "助動詞", lang.KO, false},
		{"มา", "来る", "助動詞", lang.JA, true},
		{"ขึ้น", "上がる", "動詞", lang.JA, false},
		{"พวกนี้", "これらの", "名詞", lang.JA, false},
	}
	for _, c := range cases {
		if got := highConfidence(c.word, c.meaning, c.tag, c.l); got != c.want {
			t.Errorf("highConfidence(%q, %q, %q, %v) = %v, want %v", c.word, c.meaning, c.tag, c.l, got, c.want)
		}
	}
}
