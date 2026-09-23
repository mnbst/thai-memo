package spellunit

import "strings"

// 綴りのどの文字がどの部品かを決める。
//
// タイ文字は音の並びどおりに書かないので、規則で切って**組み直しに成功した
// ときだけ**返す（validate）。切れない綴りでは文字を出さず、音だけを見せる。
// 中途半端に当てて間違った対応を教えるくらいなら、出さないほうがいい。

const (
	thaiConsonantLo = 0x0E01 // ก
	thaiConsonantHi = 0x0E2E // ฮ
	thaiToneLo      = 0x0E48
	thaiToneHi      = 0x0E4B
	thaiThanthakhat = 0x0E4C // ์（発音しない印）
	thaiSaraAm      = 0x0E33 // ำ（母音 a + 末子音 m）
)

// dimSilent は表示だけで使う「読まない字」の枠。部品データ（units）には
// 出さない（測るのは頭子音・母音・末子音・声調の4つだけ）。
const dimSilent = 4

// silentRole は dimSilent の役割名。Dim には入れない。
const silentRole = "silent"

// finalSounds は末子音として読むときの音（コード）。どの子音字が末子音の
// 音に当たるかが分かると、読まない字（จันทร์ の ทร์）を切り分けられる。
var finalSounds = map[rune]string{
	'ก': "k", 'ข': "k", 'ค': "k", 'ฆ': "k",
	'ง': "N",
	'จ': "t", 'ช': "t", 'ซ': "t", 'ฎ': "t", 'ฏ': "t", 'ฐ': "t", 'ฑ': "t",
	'ฒ': "t", 'ด': "t", 'ต': "t", 'ถ': "t", 'ท': "t", 'ธ': "t", 'ศ': "t",
	'ษ': "t", 'ส': "t",
	'ญ': "n", 'ณ': "n", 'น': "n", 'ร': "n", 'ล': "n", 'ฬ': "n",
	'บ': "p", 'ป': "p", 'พ': "p", 'ฟ': "p", 'ภ': "p",
	'ม': "m",
	'ย': "j",
	'ว': "w",
}

// leadingVowels は子音の前に書く母音字。
const leadingVowels = "เแโใไ"

// preposedCoda は末子音が母音字に含まれてしまう綴り。
//
//	ำ  = a + m
//	ไ/ใ = a + j
func isConsonant(r rune) bool { return r >= thaiConsonantLo && r <= thaiConsonantHi }
func isToneMark(r rune) bool  { return r >= thaiToneLo && r <= thaiToneHi }

// isCombining は土台の字に付く記号（母音記号・声調記号・発音しない印）。
func isCombining(r rune) bool {
	return r == 0x0E31 || (r >= 0x0E34 && r <= 0x0E3A) || (r >= 0x0E47 && r <= 0x0E4E)
}

// clusterOnsets は2文字で書く頭子音（二重子音）。
var clusterOnsets = map[string]bool{
	"kl": true, "kr": true, "kw": true, "khl": true, "khr": true, "khw": true,
	"pl": true, "pr": true, "phl": true, "phr": true, "tr": true, "thr": true,
	"thw": true, "bl": true, "br": true, "dr": true, "fl": true, "fr": true,
	"cl": true, "sl": true, "sr": true, "sw": true,
}

// sonorantOnsets は ห・อ を前に置いて階級を変える頭子音（หม, หน, อย など）。
var sonorantOnsets = map[string]bool{
	"m": true, "n": true, "N": true, "l": true, "w": true, "r": true, "j": true,
}

// hasCodaInVowel は末子音を母音字が兼ねる綴りか。
//
//	ำ    = a + m
//	ไ/ใ  = a + j
//	เ-า  = a + w
func hasCodaInVowel(word string) bool {
	if strings.ContainsAny(word, string(rune(thaiSaraAm))+"ไใ") {
		return true
	}
	return strings.HasPrefix(word, "เ") && strings.HasSuffix(word, "า")
}

// hasPronouncedConsonant は読む子音字（์ の付いていない子音）が残っているか。
func hasPronouncedConsonant(r []rune) bool {
	for j, ch := range r {
		if !isConsonant(ch) {
			continue
		}
		if j+1 < len(r) && r[j+1] == thaiThanthakhat {
			continue
		}
		return true
	}
	return false
}

// segment は綴りを部品ごとの文字に切る。切れなければ ok=false。
//
// 返すのは runes の添字の割り当て（0=頭子音 1=母音 2=末子音 3=声調）。
func segmentOwners(word string, code Code) ([]int, bool) {
	r := []rune(word)
	owner := make([]int, len(r))
	for i := range owner {
		owner[i] = -1
	}

	// 声調記号。無い綴り（平声・そもそも記号を使わない組み合わせ）もある。
	for i, ch := range r {
		if isToneMark(ch) {
			owner[i] = int(DimTone)
		}
	}

	// 頭子音。前置母音（เ แ โ ใ ไ）を飛ばした先の子音字から。
	i := 0
	for i < len(r) && (strings.ContainsRune(leadingVowels, r[i]) || owner[i] >= 0) {
		if owner[i] < 0 {
			owner[i] = int(DimVowel)
		}
		i++
	}
	if i >= len(r) || !isConsonant(r[i]) {
		return nil, false
	}
	owner[i] = int(DimOnset)
	onsetLen := 1
	// 2文字で書く頭子音（二重子音と、ห・อ を前に置くもの）。
	if i+1 < len(r) && isConsonant(r[i+1]) {
		lead := r[i]
		if clusterOnsets[code.Onset] ||
			((lead == 'ห' || lead == 'อ') && sonorantOnsets[code.Onset]) {
			owner[i+1] = int(DimOnset)
			onsetLen = 2
		}
	}
	i += onsetLen

	codaAssigned := false
	codaPos := -1

	// รร（หันอากาศ）は母音 a を子音字で書く綴り。後ろに字が続けば รร で a、
	// รร で終われば2つめが末子音 n を兼ねる（กรรม = ก + รร + ม）。
	if i+1 < len(r) && r[i] == 'ร' && r[i+1] == 'ร' {
		owner[i] = int(DimVowel)
		// 後ろに末子音を書く字が残っていなければ、2つめの ร が末子音 n を
		// 兼ねる（กรรม์ のように後ろが読まない字だけの綴りを含む）。
		if hasPronouncedConsonant(r[i+2:]) {
			owner[i+1] = int(DimVowel)
		} else {
			owner[i+1] = int(DimCoda)
			codaAssigned, codaPos = true, i+1
		}
		i += 2
	} else if i < len(r) && r[i] == 'ร' && code.Coda != "" &&
		!hasPronouncedConsonant(r[i+1:]) {
		// 単独の ร は母音と末子音をまとめて書く（กร = kɔɔn）。
		// 1文字を2つの部品に分けられないので、母音の側に置いて
		// 末子音は「字を持たない」扱いにする。
		owner[i] = int(DimVowel)
		codaAssigned, codaPos = true, i
		i++
	} else if i < len(r) && r[i] == 'ร' &&
		!strings.Contains(code.Onset, "r") && code.Coda != "r" {
		// 頭子音のすぐ後の ร は読まない綴りがある（จริง・สร้าง・เสร็จ）。
		// 頭子音の音に r が無いのにそこに ร があれば、読まない字。
		owner[i] = dimSilent
		i++
	}

	// 末子音。最後の子音字を当てる。ただし ำ・ไ・ใ は母音字が末子音を兼ねる
	// ので、子音字は残らない（そのときは文字を持たない部品になる）。
	if code.Coda != "" && !codaAssigned {
		// 末子音は「その音で読む子音字」。์ の付いた字は読まないので飛ばす
		// （องค์ の ค์）。音の合わない字も読まない（จันทร์ の ทร์）。
		last := -1
		fallback := -1
		for j := len(r) - 1; j >= i; j-- {
			if !isConsonant(r[j]) || owner[j] >= 0 {
				continue
			}
			if j+1 < len(r) && r[j+1] == thaiThanthakhat {
				continue
			}
			if fallback < 0 {
				fallback = j
			}
			if finalSounds[r[j]] == code.Coda {
				last = j
				break
			}
		}
		// 表に無い字で終わる綴りもあるので、音で当たらなければ
		// 「์ の付いていない最後の子音字」に戻す。
		if last < 0 {
			last = fallback
		}
		if last >= 0 {
			owner[last] = int(DimCoda)
			codaPos = last
			// 末子音の直前の ร は読まない綴りがある（มารถ・เกียรติ）。
			if last-1 > i && r[last-1] == 'ร' && owner[last-1] < 0 {
				owner[last-1] = dimSilent
			}
			// 末子音より後ろに付く記号も読まない（เกียรติ の ิ、องค์ の ์）。
			for j := last + 1; j < len(r) && isCombining(r[j]); j++ {
				owner[j] = dimSilent
			}
		} else if !hasCodaInVowel(word) {
			// 末子音があるはずなのに、それを書く字が見つからない。
			return nil, false
		}
	}

	// 残りは母音。ただし末子音より後ろに残った字は読まない字（กรรม์ の ม์、
	// จันทร์ の ทร์）。
	for j := range r {
		if owner[j] >= 0 {
			continue
		}
		if codaPos >= 0 && j > codaPos {
			owner[j] = dimSilent
			continue
		}
		owner[j] = int(DimVowel)
	}

	return owner, true
}

// segment は綴りを部品ごとの文字に切る（0=頭子音 1=母音 2=末子音 3=声調）。
// 前置母音のように離れて書く部品もあるので、ここでは並びを保たない。
func segment(word string, code Code) ([]string, bool) {
	owner, ok := segmentOwners(word, code)
	if !ok {
		return nil, false
	}
	out := make([]string, 5)
	for j, ch := range []rune(word) {
		out[owner[j]] += string(ch)
	}
	return out, true
}
