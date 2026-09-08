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
// words（word_breakdown の語）が本文を再構成できるならそちらと突き合わせ、
// できないときだけ本文の部分一致で位置を決める。見つからなければ ok=false。
func buildBlankText(thaiText, answer string, words []string) (string, bool) {
	if thaiText == "" || answer == "" {
		return "", false
	}
	if cleaned := cleanWords(words); rebuildsText(thaiText, cleaned) {
		// 語として一致しなければ空欄を作らない。
		// 語の途中を空欄にするより、その例文を出題しない方がよい。
		return blankByWords(thaiText, cleaned, answer)
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

// blankByWords は分割済みの語（word_breakdown）と key_word を突き合わせ、
// 一致した語だけを空欄にした本文を返す。
//
// タイ語は分かち書きしないため、本文の部分一致では長い語の内側
// （例: เวลา の中の ลา）を空欄にしてしまう。例文生成の時点で語には
// 分かれているので、そちらと比べればどこを空欄にするかは一意に決まる。
//
// ๆ のように key_word が複数語に分かれることがあるため、連続する語も見る。
// 一致する語が無ければ ok=false（その例文は出題に使わない）。
// words は cleanWords を通し、rebuildsText が真であること。
func blankByWords(thaiText string, cleaned []string, answer string) (string, bool) {
	target := stripSpaces(answer)

	// pos は「スペースを除いた本文」での語の開始位置。
	pos := 0
	for i, word := range cleaned {
		for j, joined := i, ""; j < len(cleaned) && len(joined) < len(target); j++ {
			joined += cleaned[j]
			if joined != target {
				continue
			}
			start := skipSpaces(thaiText, offsetWithSpaces(thaiText, 0, pos))
			end := offsetWithSpaces(thaiText, start, len(target))
			return thaiText[:start] + blankText + thaiText[end:], true
		}
		pos += len(word)
	}
	return "", false
}

// cleanWords は語からスペースを落とし、空の語を除く。
func cleanWords(words []string) []string {
	cleaned := make([]string, 0, len(words))
	for _, word := range words {
		if w := stripSpaces(word); w != "" {
			cleaned = append(cleaned, w)
		}
	}
	return cleaned
}

// rebuildsText は語を並べると本文に戻るか（分解に欠落・余りが無いか）。
// 戻らない分解は位置決めに使えない。
func rebuildsText(thaiText string, cleaned []string) bool {
	return len(cleaned) > 0 && strings.Join(cleaned, "") == stripSpaces(thaiText)
}

// stripSpaces はスペースを落とす。
// 語の区切りにスペースを入れるかは本文と word_breakdown で揃わないため、
// 突き合わせはスペースを無視して行う。
func stripSpaces(s string) string {
	return strings.ReplaceAll(s, " ", "")
}

// offsetWithSpaces は from から「スペースを除いて count バイト」進んだ位置を、
// 元の thaiText 上の位置で返す。
func offsetWithSpaces(thaiText string, from, count int) int {
	i := from
	for count > 0 && i < len(thaiText) {
		if thaiText[i] != ' ' {
			count--
		}
		i++
	}
	return i
}

// skipSpaces は i から続くスペースを飛ばした位置を返す。
func skipSpaces(thaiText string, i int) int {
	for i < len(thaiText) && thaiText[i] == ' ' {
		i++
	}
	return i
}
