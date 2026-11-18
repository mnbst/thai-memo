package thainlp

import (
	"regexp"
	"sort"
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

// pronunciationOverrides は綴りどおりに読まない語の発音。G2P は規則どおりに読む
// （เพล→phlee、คลิป→khá-líp）。語単位で完全一致したときだけ使う。
// 外来語・人名（長母音の後の末子音を独立した音節にする、ทร を s と読む等）と、
// パーリ・サンスクリット由来で語末の母音を落とす語が主。
var pronunciationOverrides = map[string]string{
	"เพล":            "pheen",
	"สมาธิ":          "sà-maa-thí",
	"ลิขสิทธิ์":      "lík-khà-sìt",
	"อัตรา":          "àt-traa",
	"เหอะ":           "hə̀",
	"เอ้ย":           "ə̂əi",
	"โอ้ย":           "ôoi",
	"อืมม":           "ʉʉm",
	"เขม":            "khěem",
	"พีช":            "phíit",
	"วีค":            "wíik",
	"ลุค":            "lúk",
	"แลค":            "lɛ́k",
	"ชิป":            "chíp",
	"กริป":           "kríp",
	"ทริป":           "thríp",
	"อัป":            "àp",
	"ซีรีส์":         "sii-rîi",
	"เลานจ์":         "laan",
	"ไดมอนด์":        "dai-mɔɔn",
	"ไดรเวอร์":       "drai-wə̂ə",
	"มิสเตอร์":       "mít-təə",
	"เซอร์ไพรส์":     "səə-prái",
	"โปรเจกเตอร์":    "proo-jèk-tə̂ə",
	"แอคเคานต์":      "ɛ̀k-khaw",
	"แฟนมีต":         "fɛɛn-mîit",
	"แฟนมีตติ้ง":     "fɛɛn-mîit-tîng",
	"สเปรย์":         "sà-pree",
	"สติกเกอร์":      "sà-tík-kə̂ə",
	"สตรีมเมอร์":     "sà-trii-mə̂ə",
	"สตรอว์เบอร์รี":  "sà-trɔɔ-bəə-rîi",
	"สตรอว์เบอร์รี่": "sà-trɔɔ-bəə-rîi",
	"สตรอเบอร์รี":    "sà-trɔɔ-bəə-rîi",
	"สตรอเบอร์รี่":   "sà-trɔɔ-bəə-rîi",
}

// pronunciationParts は語の一部として現れても読みが変わらない綴りの発音。
// 複合語（ศูนย์กลาง・คลิปนี้・ไลฟ์สตรีม・เทศกาลสงกรานต์）の中でも見つけ、その前後を別に読む。
// เขม（เขมร）・อัป（อัปมงคล）のように他の語の中で読みが変わるものはここに入れない。
var pronunciationParts = map[string]string{
	"ศูนย์":    "sǔun",
	"เกณฑ์":    "keen",
	"ไลฟ์":     "lái",
	"คลิป":     "khlíp",
	"คอร์ต":    "khɔ̀ɔt",
	"สตรีม":    "sà-triim",
	"สงกรานต์": "sǒng-kraan",
}

// partKeys は pronunciationParts のキーを長い順に並べたもの（同じ位置で長い綴りを先に当てる）。
var partKeys = func() []string {
	keys := make([]string, 0, len(pronunciationParts))
	for k := range pronunciationParts {
		keys = append(keys, k)
	}
	sort.Slice(keys, func(i, j int) bool { return len(keys[i]) > len(keys[j]) })
	return keys
}()

// reSaCluster は語頭の ส を sà と読む綴り（สตร・สกอ・สตอ・สปอ）。G2P は ส を
// 前の音節の末子音と見て สตรีม→sòt-riim、สกอร์→sòk-ɔɔ と読む。辞書でこの綴りの語は
// 外来語と สตรี だけで、どれも sà- で始まる（略語の สตอ. 等は除く）。
var reSaCluster = regexp.MustCompile(`^ส(?:ตร|[กตป]อ)`)

// reNumber は数字の並び（アラビア・タイ数字、桁区切りのカンマ、小数点）。
// G2P は数字を読めず、空や崩れた発音を返す（50→"5"）。
var reNumber = regexp.MustCompile(`[0-9๐-๙](?:[0-9๐-๙,]*[0-9๐-๙])?(?:\.[0-9๐-๙]+)?`)

// findSpecial は text の中で最初に現れる数字か pronunciationParts の綴りを探す。
// 見つけた範囲と、その部分の発音（数字はタイ語の数詞にしてから読む）を返す。
func findSpecial(text string) (start, end int, pron string, ok bool, err error) {
	start = -1
	if loc := reNumber.FindStringIndex(text); loc != nil {
		start, end = loc[0], loc[1]
	}
	for _, k := range partKeys {
		if i := strings.Index(text, k); i >= 0 && (start < 0 || i < start) {
			start, end = i, i+len(k)
		}
	}
	if start < 0 {
		return 0, 0, "", false, nil
	}
	seg := text[start:end]
	if p, isPart := pronunciationParts[seg]; isPart {
		return start, end, p, true, nil
	}
	pron, err = ThaiToPronunciation(thaiNumberWords(seg))
	return start, end, pron, true, err
}

var thaiDigitWords = []string{"ศูนย์", "หนึ่ง", "สอง", "สาม", "สี่", "ห้า", "หก", "เจ็ด", "แปด", "เก้า"}

// thaiNumberWords は数字の綴り（"5,000"・"๒๕"・"1.5"）をタイ語の数詞にする。
func thaiNumberWords(s string) string {
	s = strings.Map(func(r rune) rune {
		switch {
		case r >= '๐' && r <= '๙':
			return '0' + (r - '๐')
		case r == ',':
			return -1
		}
		return r
	}, s)
	intPart, frac, hasFrac := strings.Cut(s, ".")
	out := integerWords(strings.TrimLeft(intPart, "0"))
	if out == "" {
		out = thaiDigitWords[0]
	}
	if hasFrac {
		out += "จุด"
		for _, r := range frac {
			out += thaiDigitWords[r-'0']
		}
	}
	return out
}

// integerWords は先頭の 0 を除いた整数の数字列を読む。7桁以上は ล้าน で区切る。
func integerWords(d string) string {
	if len(d) > 6 {
		head := integerWords(strings.TrimLeft(d[:len(d)-6], "0"))
		return head + "ล้าน" + integerWords(strings.TrimLeft(d[len(d)-6:], "0"))
	}
	places := []string{"", "สิบ", "ร้อย", "พัน", "หมื่น", "แสน"}
	out := ""
	for i, r := range d {
		n := int(r - '0')
		pos := len(d) - 1 - i
		if n == 0 {
			continue
		}
		switch {
		case pos == 1 && n == 1:
			out += "สิบ"
		case pos == 1 && n == 2:
			out += "ยี่สิบ"
		case pos == 0 && n == 1 && len(d) > 1:
			out += "เอ็ด"
		default:
			out += thaiDigitWords[n] + places[pos]
		}
	}
	return out
}

// ThaiToPronunciation は pronunciation.py:thai_to_pronunciation:211。
func ThaiToPronunciation(thaiText string) (string, error) {
	if p, ok := pronunciationOverrides[thaiText]; ok {
		return p, nil
	}
	if start, end, p, ok, err := findSpecial(thaiText); err != nil {
		return "", err
	} else if ok {
		// 見つけた部分の前後は別に読む（前後にも数字・綴りがあれば再帰で拾う）。
		// 語の中ではハイフンでつなぎ、文の空白（ชิ้น 3 ชิ้น）は空白のまま残す。
		pre, post := thaiText[:start], thaiText[end:]
		out := p
		if strings.TrimSpace(pre) != "" {
			pp, err := ThaiToPronunciation(strings.TrimSpace(pre))
			if err != nil {
				return "", err
			}
			if pp = strings.TrimSpace(pp); pp != "" {
				out = pp + joiner(pre[len(pre)-1]) + out
			}
		}
		if strings.TrimSpace(post) != "" {
			pp, err := ThaiToPronunciation(strings.TrimSpace(post))
			if err != nil {
				return "", err
			}
			if pp = strings.TrimSpace(pp); pp != "" {
				out = out + joiner(post[0]) + pp
			}
		}
		return norm.NFC.String(out), nil
	}
	if reSaCluster.MatchString(thaiText) {
		rest, err := ThaiToPronunciation(strings.TrimPrefix(thaiText, "ส"))
		if err != nil || rest == "" {
			return rest, err
		}
		return norm.NFC.String("sà-" + rest), nil
	}
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

// joiner は分けて読んだ部分の間に置く記号。境目が空白なら空白、語の中ならハイフン。
func joiner(b byte) string {
	if b == ' ' || b == '\t' || b == '\n' {
		return " "
	}
	return "-"
}
