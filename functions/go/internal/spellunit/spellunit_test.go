package spellunit

import (
	"math/rand"
	"testing"
)

func TestParseCode(t *testing.T) {
	cases := map[string]Code{
		"?OOk1":  {Onset: "?", Vowel: "OO", Coda: "k", Tone: "1"},
		"kin0":   {Onset: "k", Vowel: "i", Coda: "n", Tone: "0"},
		"?OO0":   {Onset: "?", Vowel: "OO", Coda: "", Tone: "0"},
		"khwaa4": {Onset: "khw", Vowel: "aa", Coda: "", Tone: "4"},
	}
	for raw, want := range cases {
		got, ok := ParseCode(raw)
		if !ok || got != want {
			t.Errorf("ParseCode(%q) = %+v, %v; want %+v", raw, got, ok, want)
		}
		if got.String() != raw {
			t.Errorf("String() = %q, want %q", got.String(), raw)
		}
	}
	for _, raw := range []string{"?a1'?oN0", "?a1^h ee0", `ch\@n2`, "", "aa"} {
		if _, ok := ParseCode(raw); ok {
			t.Errorf("ParseCode(%q) を受け入れてしまった", raw)
		}
	}
}

// TestDistractorsAreNonWords はダミーが実在語でなく、正解と1次元だけ違い、
// 見た目の長さが揃っていることを確かめる。
func TestDistractorsAreNonWords(t *testing.T) {
	ix, err := LoadIndex()
	if err != nil {
		t.Fatal(err)
	}
	rnd := rand.New(rand.NewSource(1))

	words := []string{"ออก", "กิน", "หมา", "รัก"}
	found := 0
	for _, word := range words {
		code, ok := ix.Lookup(word)
		if !ok {
			continue
		}
		dummies, ok := ix.Distractors(word, rnd)
		if !ok {
			continue
		}
		found++
		if len(dummies) != distractorCount {
			t.Fatalf("%s: ダミーが %d 件", word, len(dummies))
		}
		seen := map[string]bool{}
		for _, d := range dummies {
			if ix.realWord[d.Text] {
				t.Errorf("%s: ダミー %q が実在語", word, d.Text)
			}
			if d.Text == word || seen[d.Text] {
				t.Errorf("%s: ダミーが重複 %q", word, d.Text)
			}
			seen[d.Text] = true
			if displayLen(d.Text) != displayLen(word) {
				t.Errorf("%s: ダミー %q の表示長が違う", word, d.Text)
			}
			other, ok := ix.Lookup(d.Text)
			if !ok {
				continue
			}
			if dim, _, ok := diffDim(code, other); !ok || dim != d.Dim {
				t.Errorf("%s: ダミー %q が1次元差になっていない", word, d.Text)
			}
		}
	}
	if found == 0 {
		t.Fatal("どの語でもダミーを作れなかった")
	}
}

func TestObservations(t *testing.T) {
	ix, err := LoadIndex()
	if err != nil {
		t.Fatal(err)
	}
	const word = "ออก" // ?OOk1
	code, ok := ix.Lookup(word)
	if !ok {
		t.Skip("辞書が引けない")
	}
	rnd := rand.New(rand.NewSource(7))
	dummies, ok := ix.Distractors(word, rnd)
	if !ok {
		t.Skip("ダミーを作れない")
	}
	choices := []string{word}
	for _, d := range dummies {
		choices = append(choices, d.Text)
	}

	// 正解: 測った次元ぶんの正の証拠。
	got := ix.Observations(word, choices, word, true)
	if len(got) == 0 {
		t.Fatal("正解なのに証拠が無い")
	}
	for _, o := range got {
		if !o.Correct || o.Value != code.At(o.Dim) {
			t.Errorf("正解の証拠が壊れている: %+v", o)
		}
	}

	// 不正解: 選んだ選択肢の次元だけに負の証拠。
	picked := dummies[0]
	got = ix.Observations(word, choices, picked.Text, false)
	if len(got) != 1 {
		t.Fatalf("不正解の証拠が %d 件", len(got))
	}
	o := got[0]
	if o.Correct || o.Dim != picked.Dim ||
		o.Value != code.At(picked.Dim) || o.ConfusedWith != picked.Value {
		t.Errorf("不正解の証拠が壊れている: %+v (選んだのは %+v)", o, picked)
	}
}

// TestUpdatePRecovery は間違え続けた部品でも2回の正解で 0.5 を越えられること。
func TestUpdatePRecovery(t *testing.T) {
	p := PFloor
	for i := 0; i < 2; i++ {
		p = UpdateP(p, true)
	}
	if p <= 0.5 {
		t.Errorf("2回正解しても P=%.3f", p)
	}
	low := PFloor
	for i := 0; i < 10; i++ {
		low = UpdateP(low, false)
	}
	if low < PFloor {
		t.Errorf("P が下限を割った: %.3f", low)
	}
}

func TestParts(t *testing.T) {
	ix, err := LoadIndex()
	if err != nil {
		t.Fatal(err)
	}
	cases := map[string][]Part{
		"ฉัน": { // chǎn
			{Role: "onset", Text: "ฉ", Sound: "ch"},
			{Role: "vowel", Text: "ั", Sound: "a"},
			{Role: "coda", Text: "น", Sound: "n"},
			{Role: "tone", Tone: "rising"},
		},
		"ออก": { // ɔ̀ɔk 頭子音は声門閉鎖なので読みは空
			{Role: "onset", Text: "อ", Sound: ""},
			{Role: "vowel", Text: "อ", Sound: "ɔɔ"},
			{Role: "coda", Text: "ก", Sound: "k"},
			{Role: "tone", Tone: "low"},
		},
		"คน": { // khon 母音は字にならない
			{Role: "onset", Text: "ค", Sound: "kh"},
			{Role: "vowel", Text: "", Sound: "o"},
			{Role: "coda", Text: "น", Sound: "n"},
			{Role: "tone", Tone: "mid"},
		},
		"ไม่": { // mâi 末子音 j は母音字 ไ が兼ねる
			{Role: "onset", Text: "ม", Sound: "m"},
			{Role: "vowel", Text: "ไ", Sound: "a"},
			{Role: "coda", Text: "", Sound: "i"},
			{Role: "tone", Text: "่", Tone: "falling"},
		},
		"ดี": { // dii 末子音なし
			{Role: "onset", Text: "ด", Sound: "d"},
			{Role: "vowel", Text: "ี", Sound: "ii"},
			{Role: "coda", Text: "", Sound: ""},
			{Role: "tone", Tone: "mid"},
		},
	}
	for word, want := range cases {
		got, ok := ix.Parts(word)
		if !ok {
			t.Errorf("%s: 引けない", word)
			continue
		}
		if len(got) != len(want) {
			t.Errorf("%s: %d 部品", word, len(got))
			continue
		}
		for i := range want {
			if got[i] != want[i] {
				t.Errorf("%s の %s: %+v, want %+v", word, want[i].Role, got[i], want[i])
			}
		}
	}
}

// TestSegment は綴りの切り分け。規則で切れない綴りは空で返すこと。
func TestSegment(t *testing.T) {
	ix, err := LoadIndex()
	if err != nil {
		t.Fatal(err)
	}
	// 頭子音 / 母音 / 末子音 / 声調 / 読まない字 の順。
	cases := map[string][5]string{
		"ฉัน":   {"ฉ", "ั", "น", "", ""},     // 素直な CVC
		"แล้ว":  {"ล", "แ", "ว", "้", ""},    // 前置母音＋声調記号
		"เป็น":  {"ป", "เ็", "น", "", ""},    // 母音が子音をまたぐ
		"หนึ่ง": {"หน", "ึ", "ง", "่", ""},   // ห を前に置く頭子音
		"ใกล้":  {"กล", "ใ", "", "้", ""},    // 二重子音＋末子音を母音字が兼ねる
		"อยู่":  {"อย", "ู", "", "่", ""},    // อย
		"จริง":  {"จ", "ิ", "ง", "", "ร"},    // 読まない ร は独立した枠
		"องค์":  {"อ", "", "ง", "", "ค์"},    // ์ の付いた字は読まない枠
		"จันทร์": {"จ", "ั", "น", "", "ทร์"},  // 末子音の後ろがまるごと読まない
		"คน":    {"ค", "", "น", "", ""},     // 母音が字にならない
		"เรียน": {"ร", "เีย", "น", "", ""},   // 分かれて書く母音
	}
	for word, want := range cases {
		code, ok := ix.Lookup(word)
		if !ok {
			t.Errorf("%s: 引けない", word)
			continue
		}
		got, ok := segment(word, code)
		if !ok {
			t.Errorf("%s: 切れなかった", word)
			continue
		}
		for i := range want {
			if got[i] != want[i] {
				t.Errorf("%s の %s: %q, want %q", word, Dims[i], got[i], want[i])
			}
		}
	}
}

// 綴りは書く順に切れる。前置母音の เ は頭子音より前に来る。
func TestGlyphs(t *testing.T) {
	ix, err := LoadIndex()
	if err != nil {
		t.Fatalf("LoadIndex: %v", err)
	}
	cases := map[string][]Glyph{
		"เป็น": {{"vowel", "เ"}, {"onset", "ป"}, {"vowel", "็"}, {"coda", "น"}},
		"แล้ว": {{"vowel", "แ"}, {"onset", "ล"}, {"tone", "้"}, {"coda", "ว"}},
		"คน":   {{"onset", "ค"}, {"coda", "น"}},
		"กรรม": {{"onset", "ก"}, {"vowel", "รร"}, {"coda", "ม"}},
	}
	for word, want := range cases {
		got, ok := ix.Glyphs(word)
		if !ok {
			t.Errorf("%s: 切れなかった", word)
			continue
		}
		if len(got) != len(want) {
			t.Errorf("%s: %v, want %v", word, got, want)
			continue
		}
		var rebuilt string
		for i, g := range got {
			if g != want[i] {
				t.Errorf("%s[%d]: %v, want %v", word, i, g, want[i])
			}
			rebuilt += g.Text
		}
		if rebuilt != word {
			t.Errorf("%s: 組み直せない %q", word, rebuilt)
		}
	}
}

// 声調の3要素（階級・生死・記号）が規則どおりに出る。
func TestToneRule(t *testing.T) {
	ix, err := LoadIndex()
	if err != nil {
		t.Fatalf("LoadIndex: %v", err)
	}
	cases := map[string]ToneRule{
		"คน":   {Class: "low", Syllable: "live", ShortVowel: true},               // 低子音・生音・無記号 = 平声
		"ที่":   {Class: "low", Syllable: "live", Mark: "่"},      // 低子音+第1 = 下降声
		"ปิด":  {Class: "mid", Syllable: "dead", ShortVowel: true},               // 中子音・死音 = 低声
		"สวย":  {Class: "high", Syllable: "live"},              // 高子音・生音 = 上昇声
		"ไม่":   {Class: "low", Syllable: "live", Mark: "่", ShortVowel: true},      // 母音字が末子音を兼ねる
		"รัก":   {Class: "low", Syllable: "dead", ShortVowel: true},               // 破裂音で終わる = 死音
		"หนึ่ง": {Class: "high", Syllable: "live", Mark: "่", ShortVowel: true},      // ห นำ は ห の階級
	}
	for word, want := range cases {
		got, ok := ix.ToneRule(word)
		if !ok {
			t.Errorf("%s: 3要素を出せなかった", word)
			continue
		}
		if got != want {
			t.Errorf("%s: %+v, want %+v", word, got, want)
		}
	}
}
