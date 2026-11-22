package poolreview

import (
	"bytes"
	"encoding/csv"
	"strings"
	"testing"

	"github.com/mnbst/thai-memo/functions/go/internal/sentence"
)

func nativeSample() sentence.Sentence {
	return sentence.Sentence{
		ThaiText: "ผมกินข้าว", Pronunciation: "phǒm kin khâaw",
		JapaneseTranslation: "僕はご飯を食べる", KeyWord: "กิน",
		WordBreakdown: []sentence.Word{
			{Word: "ผม", Meaning: "僕"}, {Word: "กิน", Meaning: "食べる"}, {Word: "ข้าว", Meaning: "ご飯"},
		},
		Context: map[string]any{"usage_scenarios": "昼に", "relation": "友達"},
	}
}

// 書き出した表にネイティブが記入した形を作る。
func filledSheet(t *testing.T, fill func(row []string)) *bytes.Buffer {
	t.Helper()
	var buf bytes.Buffer
	if err := WriteNativeSheet(&buf, []string{"id1"}, []sentence.Sentence{nativeSample()}); err != nil {
		t.Fatal(err)
	}
	recs, err := csv.NewReader(strings.NewReader(strings.TrimPrefix(buf.String(), "\ufeff"))).ReadAll()
	if err != nil {
		t.Fatal(err)
	}
	if len(recs[0]) != numCols || recs[1][colThai] != "ผมกินข้าว" || recs[1][colScene] != "昼に" {
		t.Fatalf("表の行 = %v", recs[1])
	}
	fill(recs[1])
	var out bytes.Buffer
	out.WriteString("\ufeff")
	w := csv.NewWriter(&out)
	w.WriteAll(recs)
	return &out
}

func TestReadNativeSheet(t *testing.T) {
	rows, err := ReadNativeSheet(filledSheet(t, func(r []string) {
		r[colVerdict] = "fix"
		r[colComment] = "訳は「私は」に"
	}))
	if err != nil {
		t.Fatal(err)
	}
	if len(rows) != 1 || rows[0].ID != "id1" || rows[0].Verdict != VerdictFix || rows[0].Comment != "訳は「私は」に" {
		t.Fatalf("rows = %+v", rows)
	}

	// 何も書いていない行は飛ばす（次の回へ残す）。
	rows, err = ReadNativeSheet(filledSheet(t, func(r []string) {}))
	if err != nil || len(rows) != 0 {
		t.Fatalf("空の行: rows=%v err=%v", rows, err)
	}
	// OK・NG はコメントがあってもなくてもよい。
	if _, err := ReadNativeSheet(filledSheet(t, func(r []string) { r[colVerdict] = "ng"; r[colComment] = "不自然" })); err != nil {
		t.Errorf("NG にコメント: %v", err)
	}
	for name, fill := range map[string]func([]string){
		"FIX に直し方無し": func(r []string) { r[colVerdict] = "FIX" },
		"判定無しのコメント":  func(r []string) { r[colComment] = "x" },
		"不明な判定":      func(r []string) { r[colVerdict] = "maybe" },
	} {
		if _, err := ReadNativeSheet(filledSheet(t, fill)); err == nil {
			t.Errorf("%s: エラーにならない", name)
		}
	}
}

func TestFixedSentence(t *testing.T) {
	orig := nativeSample()
	s, err := FixedSentence(orig, map[string]any{"japanese_translation": "私はご飯を食べる"})
	if err != nil || s.JapaneseTranslation != "私はご飯を食べる" || s.ThaiText != orig.ThaiText {
		t.Fatalf("訳だけの直し: %+v %v", s, err)
	}
	if _, err := FixedSentence(orig, nil); err == nil {
		t.Fatal("直し無しで通っている")
	}
	if _, err := FixedSentence(orig, map[string]any{"thai_text": "ผมกินข้าวแล้ว"}); err == nil {
		t.Fatal("タイ語を書き換えたのに分解・発音無しで通っている")
	}
	s, err = FixedSentence(orig, map[string]any{
		"thai_text":     "ผมกินข้าวแล้ว",
		"pronunciation": "phǒm kin khâaw lɛ́ɛw",
		"word_breakdown": []any{
			map[string]any{"word": "ผม", "meaning": "僕"}, map[string]any{"word": "กิน", "meaning": "食べる"},
			map[string]any{"word": "ข้าว", "meaning": "ご飯"}, map[string]any{"word": "แล้ว", "meaning": "もう"},
		},
	})
	if err != nil || s.ThaiText != "ผมกินข้าวแล้ว" || len(s.WordBreakdown) != 4 {
		t.Fatalf("タイ語の直し: %+v %v", s, err)
	}
}

func TestApplyPoolEdit(t *testing.T) {
	mk := func(t string) sentence.Sentence { return sentence.Sentence{ThaiText: t} }
	pool := []sentence.Sentence{mk("a"), mk("b"), mk("c"), mk("d")}
	out, rep, rem, miss := ApplyPoolEdit(pool, PoolEdit{
		Replace: map[string]sentence.Sentence{"b": mk("b2"), "c": mk("d"), "z": mk("z2")},
		Remove:  map[string]bool{"a": true},
	})
	var got []string
	for _, s := range out {
		got = append(got, s.ThaiText)
	}
	// a は外す、b は置き換える、c の直しは既にある d と重なるので c を外すだけ、z は無い。
	if strings.Join(got, ",") != "b2,d" || rep != 1 || rem != 2 || miss != 1 {
		t.Fatalf("out=%v replaced=%d removed=%d missing=%d", got, rep, rem, miss)
	}
}
