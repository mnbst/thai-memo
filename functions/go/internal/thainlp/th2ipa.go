package thainlp

import (
	"regexp"
	"strings"
)

// 前処理と IPA 変換（tltk/th2ipa.py:preprocess:1439 / g2p:74 / th2ipa:635）。

// ---------------------------------------------------------------------------
// preprocess (th2ipa.py:1439)
// ---------------------------------------------------------------------------

// pySpace は Python の str パターンにおける \s。
//
// Python は Unicode 空白を \s に含めるため、**制御文字 \x1c-\x1f も空白**になる
// （str.isspace() が真）。preprocess は区切りとして \x1f / \x1e を挿入するので、
// 以降の正規表現ではその位置が空白として扱われ、マッチ結果が変わる。
// Go の \s は [\t\n\f\r ] だけなので、明示的に揃えないと分割位置がずれる。
const pySpace = `\t\n\v\f\r\x{001c}-\x{001f} \x{0085}\x{00a0}\x{1680}\x{2000}-\x{200a}\x{2028}\x{2029}\x{202f}\x{205f}\x{3000}`

var (
	reMaiyamokSpace = regexp.MustCompile(` +ๆ`)
	reMaiyamokAfter = regexp.MustCompile(`ๆ([^ ])`)

	// 1文字ずつ空白で書かれたタイ文字を詰める
	reOneCharSpaced = regexp.MustCompile(
		`([ก-ฮเแาำะไใโฯๆ][ุูึัี๊้็่๋ิื์]*) +([ก-ฮเแาำะไใโฯๆ][ุูึัี๊้็่๋ิื์]*) +|` +
			`([ก-ฮเแาำะไใโฯๆ][ุูึัี๊้็่๋ิื์]*) +([ก-ฮเแาำะไใโฯๆ][ุูึัี๊้็่๋ิื์]*)$`)

	reSpaceLong3   = regexp.MustCompile(`([^` + pySpace + `]{3,})[` + pySpace + `]+([^` + pySpace + `]+?)`)
	reSpaceNum     = regexp.MustCompile(`([^` + pySpace + `]+)[` + pySpace + `]+([0-9]+)`)
	reSpaceShort3  = regexp.MustCompile(`([^` + pySpace + `]+?)[` + pySpace + `]+([^` + pySpace + `]{3,})`)
	reThaiAbbrMark = regexp.MustCompile(`([ก-์][ฯๆ])`)
	reThaiThenOth  = regexp.MustCompile(`([\x{0E01}-\x{0E5B}]+\.?)([^.\x{0E01}-\x{0E5B}\x{001F}]+)`)
	reOthThenThai  = regexp.MustCompile(`([^.\x{0E01}-\x{0E5B}\x{001F}]+)([\x{0E01}-\x{0E5B}]+)`)
	reTagLike      = regexp.MustCompile(`(<.+?>)`)
	reAlnumThenTh  = regexp.MustCompile(`([0-9a-zA-Z.\-]{2,})([\x{0E01}-\x{0E5B}]+)`)
	reEllipsis     = regexp.MustCompile(`(\.\.\.+)`)
)

// normalizeDict は preprocess:1449-1454。
var normalizeDict = [][2]string{
	{"เเ", "แ"},  // Sara E + Sara E -> Sara AE
	{"ํา", "ำ"},  // Nikhahit + Sara AA -> Sara AM
	{"ฤา", "ฤๅ"}, // Ru + Sara AA -> Ru + Lakkhangyao
	{"ฦา", "ฦๅ"}, // Lu + Sara AA -> Lu + Lakkhangyao
}

func preprocess(input string) string {
	input = reMaiyamokSpace.ReplaceAllString(input, "ๆ")
	input = reMaiyamokAfter.ReplaceAllString(input, "ๆ"+segSep+"$1")

	for _, kv := range normalizeDict {
		input = strings.ReplaceAll(input, kv[0], kv[1])
	}

	input = reOneCharSpaced.ReplaceAllString(input, "$1$2")
	input = reSpaceLong3.ReplaceAllString(input, "$1"+segSep+"$2")
	input = reSpaceNum.ReplaceAllString(input, "$1"+segSep+"$2")
	input = reSpaceShort3.ReplaceAllString(input, "$1"+segSep+"$2")

	input = reThaiAbbrMark.ReplaceAllString(input, "$1"+ssegSep)
	input = reThaiThenOth.ReplaceAllString(input, "$1"+ssegSep+"$2")
	input = reOthThenThai.ReplaceAllString(input, "$1"+ssegSep+"$2")
	input = reTagLike.ReplaceAllString(input, ssegSep+"$1")
	input = reAlnumThenTh.ReplaceAllString(input, "$1"+ssegSep+"$2")
	input = reEllipsis.ReplaceAllString(input, ssegSep+"$1"+ssegSep)
	return input
}

// ---------------------------------------------------------------------------
// g2p (th2ipa.py:74)
// ---------------------------------------------------------------------------

// reNonThaiSeg は Python の r"[^ก-์]+"。タイ文字以外だけの断片はそのまま通す。
var reNonThaiSeg = regexp.MustCompile(`\A[^ก-์]+`)

// G2P は th2ipa.py:g2p:74。"タイ文字<tr/>音素列" を WordSep/<s/> で連結して返す。
func G2P(input string) (string, error) {
	var output strings.Builder
	for _, s := range strings.Split(preprocess(input), segSep) {
		for _, inp := range strings.Split(s, ssegSep) {
			if inp == "" {
				continue
			}
			var out string
			if reNonThaiSeg.MatchString(inp) {
				out = inp + "<tr/>" + inp
			} else {
				var err error
				if out, err = WordParse(inp); err != nil {
					return "", err
				}
			}
			output.WriteString(out + wordSep)
		}
		output.WriteString("<s/>")
	}
	return output.String(), nil
}

// ---------------------------------------------------------------------------
// th2ipa (th2ipa.py:635)
// ---------------------------------------------------------------------------

// normalizeIPA は th2ipa:637。置換は**この順で**行う（数字の付け替えが
// 連鎖するため、順序を変えると声調番号がずれる）。
var normalizeIPA = [][2]string{
	{"O", "ᴐ"},
	{"x", "ɛ"},
	{"@", "ɤ"},
	{"N", "ŋ"},
	{"?", "ʔ"},
	{"U", "ɯ"},
	{"|", " "},
	{"~", "."},
	{"^", "."},
	{"'", "."},
	{"4", "5"},
	{"3", "4"},
	{"2", "3"},
	{"1", "2"},
	{"0", "1"},
}

var (
	reAspirated = regexp.MustCompile(`([ptkc])h`)
)

// TH2IPA は th2ipa.py:th2ipa:635。
func TH2IPA(text string) (string, error) {
	inx, err := G2P(text)
	if err != nil {
		return "", err
	}
	var out strings.Builder
	for _, seg := range strings.Split(inx, "<s/>") {
		if seg == "" {
			continue
		}
		// Python は (th, tran) = seg.split('<tr/>') と2要素で受けるので、
		// <tr/> が無い場合も2個以上ある場合も ValueError になる。
		// 例: "ทร-" は <tr/> が2個できて "too many values to unpack"。
		parts := strings.Split(seg, "<tr/>")
		if len(parts) != 2 {
			return "", errSplitTr
		}
		tran := parts[1]

		// 同じ母音字の連続を長音記号にする（後方参照なので手で書く）
		tran = replaceDoubledVowel(tran)
		// ʰ は Unicode 上「文字」なので "$1ʰ" と書くとグループ名 "1ʰ" と
		// 解釈されて置換が空になる。${1} で境界を明示する。
		tran = reAspirated.ReplaceAllString(tran, "${1}ʰ")
		for _, kv := range normalizeIPA {
			tran = strings.ReplaceAll(tran, kv[0], kv[1])
		}
		out.WriteString(tran + "<s/>")
	}
	return out.String(), nil
}

// replaceDoubledVowel は Python の re.sub(r"([aeiouUxO@])\1", r"\1ː", tran)。
// Go の RE2 は後方参照を持たないので手で書く。左から非重複で置換する。
func replaceDoubledVowel(s string) string {
	const vowels = "aeiouUxO@"
	r := []rune(s)
	var b strings.Builder
	for i := 0; i < len(r); i++ {
		if i+1 < len(r) && r[i] == r[i+1] && strings.ContainsRune(vowels, r[i]) {
			b.WriteRune(r[i])
			b.WriteRune('ː')
			i++ // 2文字消費
			continue
		}
		b.WriteRune(r[i])
	}
	return b.String()
}
