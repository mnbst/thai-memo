package thainlp

import (
	"regexp"
	"strings"
	"unicode"

	"golang.org/x/text/unicode/norm"
)

// IPA から学習者向けローマ字への変換（functions/python/pronunciation.py）。
// TLTK ではなくプロジェクト自身のコード。

// toneMarks は pronunciation.py:_TONE_MARKS。声調番号 -> 結合ダイアクリティカル。
var toneMarks = map[string]string{
	"1": "",  // 平声（สามัญ）: 記号なし
	"2": "̀", // 低声（เอก）: à
	"3": "̂", // 下降声（โท）: â
	"4": "́", // 高声（ตรี）: á
	"5": "̌", // 上昇声（จัตวา）: ǎ
}

// ipaToRoman は pronunciation.py:_IPA_TO_ROMAN。
// **順序が重要**。長い綴りを先に当てる必要がある。
var ipaToRoman = [][2]string{
	// プレースホルダ退避（後の j→i 変換と衝突させないため）
	{"tɕʰ", "CH"},
	{"cʰ", "CH"},
	{"tɕ", "J"},
	{"c", "J"},
	// 有気音
	{"kʰ", "kh"},
	{"tʰ", "th"},
	{"pʰ", "ph"},
	// 鼻音・その他
	{"ŋ", "ng"},
	{"ɲ", "ny"},
	{"ʔ", ""},
	// 母音
	{"ɯː", "ʉʉ"},
	{"ɯ", "ʉ"},
	{"ɛː", "ɛɛ"},
	{"ɛ", "ɛ"},
	{"ᴐː", "ɔɔ"},
	{"ᴐ", "ɔ"},
	{"ɤː", "əə"},
	{"ɤ", "ə"},
	{"aː", "aa"},
	{"iː", "ii"},
	{"uː", "uu"},
	{"eː", "ee"},
	{"oː", "oo"},
}

// vowels は声調記号を置く位置（最初の母音）の判定に使う。
const vowelSet = "aeiouɔɛəʉ"

// silentThaiMarks は発音しない記号。ฯ（paiyannoi）。
const silentThaiMarks = "ฯ"

// addTone は pronunciation.py:_add_tone:141。
// 最初の母音の直後に結合ダイアクリティカルを挿入する。
func addTone(syllable, tone string) string {
	mark := toneMarks[tone]
	if mark == "" {
		return syllable
	}
	r := []rune(syllable)
	for i, ch := range r {
		if strings.ContainsRune(vowelSet, ch) {
			return string(r[:i+1]) + mark + string(r[i+1:])
		}
	}
	return syllable
}

// reVowelThenJ は Python の (?<=[aeiouɔɛəʉ])j（後読み）。
// Go の RE2 は後読みを持たないので手で書く。
func vowelThenJToI(s string) string {
	r := []rune(s)
	var b strings.Builder
	for i, ch := range r {
		if ch == 'j' && i > 0 && strings.ContainsRune(vowelSet, r[i-1]) {
			b.WriteRune('i')
			continue
		}
		b.WriteRune(ch)
	}
	return b.String()
}

// convertSyllable は pronunciation.py:_convert_syllable:166。
func convertSyllable(ipaSyl string) string {
	// TLTK の TransformSyl はバックスラッシュを混入させる。
	//   th2ipa.py:482  re.sub(r"\@\@", "\@", phone)
	// 置換文字列が "\@" になっているため、長母音 @@ を短母音 @ に縮める意図に
	// 反して "\@" が残る。@ は後段で ɤ→ə になるので、そのまま発音表記に
	// "\" が漏れる（例: เบิ้ล -> "b\ə̂n"、正しくは "bə̂n"）。
	// 外来語で出るため実害があり、辞書78,773語のうち42語が該当した。
	// Python 側 pronunciation.py にも同じ除去を入れてある（両者一致を保つため）。
	ipaSyl = strings.ReplaceAll(ipaSyl, `\`, "")

	// 末尾の数字を声調番号として取り出す（既定は平声 "1"）
	tone := "1"
	r := []rune(ipaSyl)
	if len(r) > 0 && unicode.IsDigit(r[len(r)-1]) {
		tone = string(r[len(r)-1])
		ipaSyl = string(r[:len(r)-1])
	}

	result := ipaSyl
	for _, kv := range ipaToRoman {
		result = strings.ReplaceAll(result, kv[0], kv[1])
	}

	// 母音の後の j → i（二重母音）、それ以外の j → y（子音 ย）
	result = vowelThenJToI(result)
	result = strings.ReplaceAll(result, "j", "y")

	// プレースホルダ復元
	result = strings.ReplaceAll(result, "CH", "ch")
	result = strings.ReplaceAll(result, "J", "j")

	return addTone(result, tone)
}

// reSyllableSplit は Python の re.split(r"[.+\s]+", raw_segment)。
// Python の \s に合わせる（pySpace の理由は th2ipa.go を参照）。
var reSyllableSplit = regexp.MustCompile(`[.+` + pySpace + `]+`)

// ThaiToPronunciation は pronunciation.py:thai_to_pronunciation:211。
func ThaiToPronunciation(thaiText string) (string, error) {
	normalizedText := strings.Map(func(r rune) rune {
		if strings.ContainsRune(silentThaiMarks, r) {
			return -1
		}
		return r
	}, thaiText)

	ipa, err := TH2IPA(normalizedText)
	if err != nil {
		return "", err
	}
	ipa = strings.TrimSpace(ipa)

	var segments []string
	for _, rawSegment := range strings.Split(ipa, "<s/>") {
		var syllables []string
		for _, s := range reSyllableSplit.Split(rawSegment, -1) {
			if s != "" {
				syllables = append(syllables, convertSyllable(s))
			}
		}
		if len(syllables) == 0 {
			continue
		}
		segments = append(segments, strings.Join(syllables, "-"))
	}

	// Python は unicodedata.normalize("NFC", ...)
	return norm.NFC.String(strings.Join(segments, " ")), nil
}
