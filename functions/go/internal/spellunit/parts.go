package spellunit

// 綴り4択の答え合わせで見せる「部品ごとの分解」。
//
// 音と役割は音節形コードから確実に出せる。文字との対応は綴りを規則で切って
// 出すが、組み直して元に戻らない綴りでは文字を空にする（segment.go）。

// Part は分解した部品1つ。
type Part struct {
	// Role は onset / vowel / coda / tone。
	Role string `json:"role"`
	// Text はその部品を書く文字。切り分けられないとき、
	// 表記を持たない部品（母音が字にならない綴り・末子音を母音字が兼ねる綴り）
	// のときは空。
	Text string `json:"text,omitempty"`
	// Sound は学習者向けの読み（アプリの発音表記に合わせる）。
	// 末子音なし・声門閉鎖の頭子音は空。
	Sound string `json:"sound"`
	// Tone は Role が tone のときの声調名（mid / low / falling / high / rising）。
	Tone string `json:"tone,omitempty"`
}

// onsetRoman は頭子音コード -> 読み。ipaToRoman（pronunciation.go）に合わせる。
// "?" は声門閉鎖で、綴りの อ に当たる。音として読ませるものが無いので空。
var onsetRoman = map[string]string{
	"?": "", "N": "ng", "c": "j", "ch": "ch", "j": "y",
	"kh": "kh", "khl": "khl", "khr": "khr", "khw": "khw",
	"ph": "ph", "phl": "phl", "phr": "phr",
	"th": "th", "thr": "thr", "thw": "thw",
}

// vowelRoman は母音コード -> 読み。長母音は重ねる（アプリの表記と同じ）。
var vowelRoman = map[string]string{
	"a": "a", "aa": "aa", "i": "i", "ii": "ii", "u": "u", "uu": "uu",
	"e": "e", "ee": "ee", "e-": "ə", "@@": "əə",
	"o": "o", "oo": "oo", "O": "ɔ", "OO": "ɔɔ",
	"x": "ɛ", "xx": "ɛɛ", "U": "ʉ", "UU": "ʉʉ",
	"ia": "ia", "iia": "iia", "uua": "uua", "UUa": "ʉʉa",
}

// codaRoman は末子音コード -> 読み。空は「末子音なし」。
// j は母音の後なので i（ไม่ = mâi）。アプリの発音表記と同じにする
// （pronunciation.go の vowelThenJToI）。
var codaRoman = map[string]string{
	"N": "ng", "j": "i", "w": "w", "": "",
}

// toneNames は声調コード -> 声調名。コードの数字は pronunciation.go の
// 声調番号より1つ小さい（chan4 = chǎn = 上昇）。
var toneNames = map[string]string{
	"0": "mid", "1": "low", "2": "falling", "3": "high", "4": "rising",
}

// Parts は綴りを頭子音・母音・末子音・声調に分けて返す。
// 文字の切り分けに成功したときは、各部品にその文字も入る。
func (ix *Index) Parts(word string) ([]Part, bool) {
	code, ok := ix.Lookup(word)
	if !ok {
		return nil, false
	}
	parts := code.Parts()
	texts, ok := segment(word, code)
	if !ok {
		return parts, true
	}
	for i := range parts {
		parts[i].Text = texts[i]
	}
	// 読まない字（องค์ の ค์、จันทร์ の ทร์）は音の部品に混ぜず、
	// それだけの枠にして「読まない」と見せる。
	if texts[dimSilent] != "" {
		parts = append(parts, Part{Role: silentRole, Text: texts[dimSilent]})
	}
	return parts, true
}

// Parts は音節形コードの分解。
func (c Code) Parts() []Part {
	return []Part{
		{Role: DimOnset.String(), Sound: roman(onsetRoman, c.Onset)},
		{Role: DimVowel.String(), Sound: roman(vowelRoman, c.Vowel)},
		{Role: DimCoda.String(), Sound: roman(codaRoman, c.Coda)},
		{Role: DimTone.String(), Tone: toneNames[c.Tone]},
	}
}

// roman は表に無いコードをそのまま読みとして使う（k, t, p, m, n など）。
func roman(table map[string]string, code string) string {
	if v, ok := table[code]; ok {
		return v
	}
	return code
}

// Glyph は綴りを「書く順」に切った断片1つ。
// タイ語は音の順に書かないので、Part（音の順）とは並びが違う。
// 画面はこれを使って、綴りのどの字がどの部品かを色で示す。
type Glyph struct {
	// Role は onset / vowel / coda / tone。
	Role string `json:"role"`
	// Text は続けて書く同じ役割の字。
	Text string `json:"text"`
}

// Glyphs は綴りを書く順に切って返す。切り分けられない綴りでは ok=false。
func (ix *Index) Glyphs(word string) ([]Glyph, bool) {
	code, ok := ix.Lookup(word)
	if !ok {
		return nil, false
	}
	owner, ok := segmentOwners(word, code)
	if !ok {
		return nil, false
	}
	var out []Glyph
	last := -1
	for i, ch := range []rune(word) {
		if owner[i] != last {
			role := silentRole
			if owner[i] != dimSilent {
				role = Dim(owner[i]).String()
			}
			out = append(out, Glyph{Role: role})
			last = owner[i]
		}
		out[len(out)-1].Text += string(ch)
	}
	return out, true
}
