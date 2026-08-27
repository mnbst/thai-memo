// Package quizgen はクイズ生成のプロンプト組み立てと、
// モデル出力のルールベース補正・検査。
// functions/javascript/src/services/quizGenerationService.ts の移植。
package quizgen

import (
	"regexp"
	"strings"
)

// blankText は穴埋めの空欄。
const blankText = "___"

// jsSpace は JavaScript の正規表現 \s と同じ文字集合。
//
// Go の \s は [\t\n\f\r ] だけなので、明示しないと全角スペースや NBSP が
// 詰められず、JS と正規化結果がずれる（モデル出力にはこれらが混ざる）。
const jsSpace = `\t\n\v\f\r \x{00a0}\x{1680}\x{2000}-\x{200a}\x{2028}\x{2029}\x{202f}\x{205f}\x{3000}\x{feff}`

var (
	reSpaceRun  = regexp.MustCompile("[" + jsSpace + "]+")
	reThai      = regexp.MustCompile(`[\x{0E00}-\x{0E7F}]`)
	reJapanese  = regexp.MustCompile(`[\x{3040}-\x{30FF}\x{31F0}-\x{31FF}\x{4E00}-\x{9FFF}]`)
	reLatin     = regexp.MustCompile(`[A-Za-z]`)
	reAnnotSep  = regexp.MustCompile(`[(（:：]`)
	reTrimSpace = regexp.MustCompile("^[" + jsSpace + "]+|[" + jsSpace + "]+$")
)

// normalizeText は前後の空白を落とし、連続する空白を1つにまとめる。
// JS の `(value ?? ”).trim().replace(/\s+/g, ' ')`。
func normalizeText(value string) string {
	return reSpaceRun.ReplaceAllString(reTrimSpace.ReplaceAllString(value, ""), " ")
}

// isThaiChoiceText は選択肢として使えるタイ語かを見る。
// タイ文字を含み、日本語・ラテン文字を含まないこと。
func isThaiChoiceText(value string) bool {
	text := normalizeText(value)
	return text != "" &&
		reThai.MatchString(text) &&
		!reJapanese.MatchString(text) &&
		!reLatin.MatchString(text)
}

// stripChoiceAnnotation は選択肢に付いた注釈を落とす。
//
// モデルは `กิน (kin / to eat)` や `กิน (gin / to eat): 理由` のように
// 発音・英訳・解説を足してくることがある。括弧・コロンの手前がタイ文字だけなら
// それを採用し、そうでなければ元の値を返して isThaiChoiceText 側で落とす。
func stripChoiceAnnotation(value string) string {
	text := normalizeText(value)
	head := normalizeText(reAnnotSep.Split(text, 2)[0])
	if head != "" && isThaiChoiceText(head) {
		return head
	}
	return text
}

// uniqueTexts は正規化しつつ、空文字と重複を落として順序を保つ。
func uniqueTexts(values []string) []string {
	seen := map[string]bool{}
	var result []string
	for _, value := range values {
		normalized := normalizeText(value)
		if normalized == "" || seen[normalized] {
			continue
		}
		seen[normalized] = true
		result = append(result, normalized)
	}
	return result
}

// buildBlankText は thaiText 中の answer を空欄に差し替える。
// 見つからなければ ok=false。
func buildBlankText(thaiText, answer string) (string, bool) {
	if thaiText == "" || answer == "" {
		return "", false
	}
	i := strings.Index(thaiText, answer)
	if i == -1 {
		return "", false
	}
	return thaiText[:i] + blankText + thaiText[i+len(answer):], true
}

// containsBlank は空欄を含むか。
func containsBlank(s string) bool {
	return strings.Contains(s, blankText)
}

// indexOf は strings.Index の別名（JS の indexOf に対応することを明示する）。
func indexOf(haystack, needle string) int {
	return strings.Index(haystack, needle)
}

// NormalizeText は normalizeText の公開版。
// generateQuiz 側（JS の normalizeTextValue）も同じ正規化を使う。
func NormalizeText(value string) string {
	return normalizeText(value)
}

// NormalizeTextValue は Firestore の生の値を正規化する。
// JS の `typeof value === 'string' ? value.trim().replace(/\s+/g, ' ') : ”`。
func NormalizeTextValue(value any) string {
	s, ok := value.(string)
	if !ok {
		return ""
	}
	return normalizeText(s)
}

// ContainsBlank は空欄を含むか（公開版）。
func ContainsBlank(s string) bool { return containsBlank(s) }
