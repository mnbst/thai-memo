//go:build manual

package spellunit

import (
	"os"
	"sort"
	"strings"
	"testing"
)

// TestDisplayAudit は全綴りを画面の分解表示にかけ、字と部品が1対1にならない
// 形（例外）を数える。出題されうる語だけを見たいので BEST.dict 見出し語に
// 絞った数も出す。SPELLUNIT_DISPLAY=1 のときだけ動く。
func TestDisplayAudit(t *testing.T) {
	if os.Getenv("SPELLUNIT_DISPLAY") == "" {
		t.Skip("SPELLUNIT_DISPLAY=1 で実行")
	}
	ix, err := LoadIndex()
	if err != nil {
		t.Fatal(err)
	}

	type bucket struct {
		all, real int
		samples   []string
	}
	buckets := map[string]*bucket{}
	note := func(kind, word string, real bool) {
		b := buckets[kind]
		if b == nil {
			b = &bucket{}
			buckets[kind] = b
		}
		b.all++
		if real {
			b.real++
			if len(b.samples) < 6 {
				b.samples = append(b.samples, word)
			}
		}
	}

	words := make([]string, 0, len(ix.codes))
	for w := range ix.codes {
		words = append(words, w)
	}
	sort.Strings(words)

	for _, w := range words {
		real := ix.realWord[w]
		parts, ok := ix.Parts(w)
		if !ok {
			note("00 引けない", w, real)
			continue
		}
		p := map[string]Part{}
		for _, part := range parts {
			p[part.Role] = part
		}
		onset, vowel, coda, tone := p["onset"], p["vowel"], p["coda"], p["tone"]

		if onset.Text == "" && vowel.Text == "" {
			note("01 切り分け失敗（字を出さない）", w, real)
			continue
		}

		// 母音字が末子音を兼ねる
		if coda.Text == "" && coda.Sound != "" {
			switch {
			case strings.Contains(vowel.Text, "ำ"):
				note("10 ำ = 母音a + 末子音m", w, real)
			case strings.ContainsAny(vowel.Text, "ไใ"):
				note("11 ไ/ใ = 母音a + 末子音i", w, real)
			case strings.HasPrefix(vowel.Text, "เ") && strings.HasSuffix(vowel.Text, "า"):
				note("12 เ-า = 母音a + 末子音w", w, real)
			case strings.Contains(vowel.Text, "ร"):
				note("13 単独の ร が母音+末子音", w, real)
			case vowel.Text == "":
				note("14 母音も末子音も字なし", w, real)
			default:
				note("19 その他（母音字が末子音を兼ねる）", w, real)
			}
		}

		// 書かない母音
		if vowel.Text == "" && !(coda.Text == "" && coda.Sound != "") {
			if coda.Text != "" {
				note("20 母音を書かない（頭子音+末子音だけ）", w, real)
			} else {
				note("21 母音も末子音も無い", w, real)
			}
		}
		if vowel.Text == "รร" {
			note("22 รร = 母音a", w, real)
		}

		// 頭子音が2字以上（二重子音・ห นำ・อย）
		if len([]rune(onset.Text)) > 1 {
			note("30 頭子音が2字以上（二重子音・ห นำ）", w, real)
		}
		// 読まない字が末子音側に付く
		if strings.Contains(coda.Text, "ร") && len([]rune(coda.Text)) > 1 {
			note("31 末子音の前後に読まない ร", w, real)
		}
		if strings.Contains(coda.Text, "์") || strings.Contains(onset.Text, "์") {
			note("32 ์ が付いた読まない字", w, real)
		}
		if p[silentRole].Text != "" {
			note("50 読まない字（独立した枠で表示）", w, real)
		}
		if len([]rune(tone.Text)) > 1 {
			note("40 声調記号が複数（表記ゆれ）", w, real)
		}
	}

	kinds := make([]string, 0, len(buckets))
	for k := range buckets {
		kinds = append(kinds, k)
	}
	sort.Strings(kinds)
	t.Logf("綴り総数: %d（うち BEST.dict 見出し語 %d）", len(words), countReal(ix, words))
	for _, k := range kinds {
		b := buckets[k]
		t.Logf("%-38s 全%5d 語%5d  例: %v", k, b.all, b.real, b.samples)
	}
}

func countReal(ix *Index, words []string) int {
	n := 0
	for _, w := range words {
		if ix.realWord[w] {
			n++
		}
	}
	return n
}
