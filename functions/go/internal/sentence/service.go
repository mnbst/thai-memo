package sentence

import (
	"fmt"
	"regexp"
	"strings"

	"github.com/mnbst/thai-memo/functions/go/internal/lang"
	"github.com/mnbst/thai-memo/functions/go/internal/pystr"
	"github.com/mnbst/thai-memo/functions/go/internal/wordgap"
)

// functions/python/sentence_service.py の移植（純粋ロジック部分）。
// LLM 呼び出しとリトライの制御は別ファイル。

// MaxRetry は生成のやり直し回数。
const MaxRetry = 1

// reSpaceBeforeYamok は Python の r"\s+ๆ"。
var reSpaceBeforeYamok = regexp.MustCompile(`[` + pystr.SpaceClass + `]+ๆ`)

// CompactYamok は畳語記号 ๆ の前の空白を詰める。
//
// 王立学士院の正式記法は ๆ の前を空けるが、TTS は空白を語境界のポーズとして
// 読むため จริง ๆ が分断されて発音される。表示より発音の自然さを優先する。
// ๆ の後ろの空白は節の切れ目になりうるので残す。
func CompactYamok(text string) string {
	return reSpaceBeforeYamok.ReplaceAllString(text, "ๆ")
}

// StripSpaces は Python の "".join(text.split())。空白を全て落とす。
func StripSpaces(text string) string {
	return strings.Join(pystr.Split(text), "")
}

// MatchWord はターゲット語と word_breakdown の語を照合する。
//
// ๆ の前の空白は NormalizeThaiSpacing で詰めるが、そこを通らない経路
// （欠落補完・テスト）からも呼ばれるので照合時にも両表記を同一視する。
func MatchWord(wordText, target string) bool {
	w := CompactYamok(strings.TrimSpace(wordText))
	t := CompactYamok(target)
	return w == t || w == t+"ๆ" || w+"ๆ" == t
}

// ValidateTargetWords は word_breakdown に target_word が独立エントリとして
// 存在するか検証し、含まれていなかった語を返す。
//
// 複合語の一部としてのみ含まれるケースは missing として扱い、
// リトライで独立した形での使用を強制する。
func ValidateTargetWords(breakdownWords, targetWords []string) []string {
	if len(targetWords) == 0 {
		return nil
	}

	// Python は集合にしてから照合する。重複は結果に影響しないが揃えておく。
	var trimmed []string
	seen := map[string]bool{}
	for _, w := range breakdownWords {
		t := strings.TrimSpace(w)
		if seen[t] {
			continue
		}
		seen[t] = true
		trimmed = append(trimmed, t)
	}

	var missing []string
	for _, tw := range targetWords {
		target := strings.TrimSpace(tw)
		if target == "" {
			continue
		}
		found := false
		for _, w := range trimmed {
			if MatchWord(w, target) {
				found = true
				break
			}
		}
		if !found {
			missing = append(missing, target)
		}
	}
	return missing
}

// contextFields は context のうち LLM に生成させうるフィールド。
var contextFields = []string{"topic", "style", "emotion"}

// SchemaFor は確定値が無い context フィールドだけ LLM に生成させるスキーマを返す。
func SchemaFor(resolvedContext map[string]any, l lang.Lang) map[string]any {
	var ask []string
	for _, f := range contextFields {
		if isTruthy(resolvedContext[f]) {
			continue
		}
		ask = append(ask, f)
	}
	return BuildResponseSchema(ask, l)
}

// isTruthy は Python の真偽値評価（空文字・0・nil は偽）。
func isTruthy(v any) bool {
	switch x := v.(type) {
	case nil:
		return false
	case string:
		return x != ""
	case bool:
		return x
	case int:
		return x != 0
	case int64:
		return x != 0
	case float64:
		return x != 0
	}
	return true
}

// BuildRetryPrompt は target_word の欠落を指摘する再生成プロンプト。
func BuildRetryPrompt(prompt string, missing []string) string {
	return fmt.Sprintf(
		"%s\n\n"+
			"【再生成指示】前回の生成では次の単語がword_breakdownに独立エントリとして含まれていませんでした: %s\n"+
			"これらの単語を複合語の一部ではなく、単独で意味が成り立つ形で文中に使い、word_breakdownにも独立した項目として含めてください。",
		prompt, strings.Join(missing, ", "))
}

// BuildMismatchRetryPrompt は thai_text と word_breakdown の食い違いを
// 指摘する再生成プロンプト。
func BuildMismatchRetryPrompt(prompt, thaiText string) string {
	return fmt.Sprintf(
		"%s\n\n"+
			"【再生成指示】前回の生成では thai_text と word_breakdown の語が食い違っていました"+
			"（thai_text: %s）。多くは thai_text 側の綴り誤りです。"+
			"thai_text を正しい綴りで書き直し、word_breakdown の各語が thai_text に"+
			"そのまま出現する形で出力してください。",
		prompt, thaiText)
}

// NormalizeThaiSpacing は thai_text の空白を整える。
//
//  1. 畳語記号 ๆ の前の空白を詰める（TTS 対策。CompactYamok を参照）
//  2. word_breakdown の分割が thai_text に漏れた文の空白を詰める
//
// 2 は、同じ文の分割版（word_breakdown）を同時に出力させる構造上、プロンプトで
// 何度禁じても残る（2026-08-06 実測 6/548=1.1%。例文の有無・語クラスブロックの
// 有無と相関せず、ルール追加では消えない）。観測された6件はすべて空白位置が
// word_breakdown の区切りと一致していたので、その一致を条件に詰める。
// 節の切れ目に空白1つの正しい文（トークン2個）と、word_breakdown と連結が
// 一致しない文には触らない。
//
// 戻り値は 整えた thai_text と、ๆ を詰めた word_breakdown の語。
func NormalizeThaiSpacing(thaiText string, breakdownWords []string) (string, []string) {
	text := CompactYamok(thaiText)

	words := make([]string, len(breakdownWords))
	for i, w := range breakdownWords {
		if w != "" {
			words[i] = CompactYamok(w)
		}
	}

	tokens := pystr.Split(text)
	// 3トークン以下は空白過多ではあっても、どれが節の切れ目か判別できない。
	// 実測の分かち書き崩壊は全て4トークン以上（2026-08-06）。
	if len(tokens) < 4 {
		return text, words
	}

	stripped := make([]string, 0, len(words))
	for _, w := range words {
		stripped = append(stripped, strings.TrimSpace(w))
	}
	if len(stripped) == 0 {
		return text, words
	}
	if StripSpaces(text) != StripSpaces(strings.Join(stripped, "")) {
		return text, words
	}
	// 空白が語の区切りと一致するだけでは足りない（2節の文でも一致する）。
	// 語数に近い数まで割れているものだけを分かち書きの漏れとみなす。
	// 実測6件は 0.8〜1.0、正しい2節の文は 0.5 未満（2026-08-06）。
	if float64(len(tokens)) < float64(len(stripped))*0.7 {
		return text, words
	}

	return StripSpaces(text), words
}

// HasUnrepairableBreakdown は word_breakdown に thai_text へ出現しない語が
// あるか（綴り不一致）を返す。
func HasUnrepairableBreakdown(thaiText string, breakdown []wordgap.Word) bool {
	for _, g := range wordgap.FindGaps(thaiText, breakdown) {
		if g.Index < 0 {
			return true
		}
	}
	return false
}
