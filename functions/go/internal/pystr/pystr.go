// Package pystr は Python の文字列処理と同じ挙動を持つヘルパー。
//
// Go と Python では「空白」の定義が違う。Go の正規表現 \s は [\t\n\f\r ] の
// ASCII だけだが、Python の \s と str.isspace() は全角スペース・NBSP に加えて
// 制御文字 \x1c-\x1f と \x85 も空白として扱う。移植時にここを合わせないと、
// タイ語の文中に混ざる全角スペースが詰まらずに残る。
package pystr

import (
	"strings"
	"unicode"
)

// SpaceClass は Python の正規表現 \s と同じ文字集合（Go の正規表現に埋める用）。
const SpaceClass = `\t\n\v\f\r\x{001c}-\x{001f} \x{0085}\x{00a0}\x{1680}` +
	`\x{2000}-\x{200a}\x{2028}\x{2029}\x{202f}\x{205f}\x{3000}`

// IsSpace は Python の str.isspace() と同じ判定。str.split() の区切り文字集合。
//
// unicode.IsSpace は \x1c-\x1f と \x85 を空白としないので明示的に足す。
func IsSpace(r rune) bool {
	switch r {
	case 0x1c, 0x1d, 0x1e, 0x1f, 0x85:
		return true
	}
	return unicode.IsSpace(r)
}

// Split は Python の str.split()（引数なし）。空白の連なりで分割し、
// 両端の空要素は落とす。
func Split(text string) []string {
	return strings.FieldsFunc(text, IsSpace)
}

// TrimSpace は Python の str.strip()（引数なし）。
func TrimSpace(text string) string {
	return strings.TrimFunc(text, IsSpace)
}
