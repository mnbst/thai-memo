// Package wordgap は word_breakdown の欠落を検出し、補完結果を差し込む。
// functions/python/word_gap.py の移植。
//
// 文全体の発音は word_breakdown の各語の発音を連結して作っている。
// そのため word_breakdown に語の抜けがあると、発音からその語が丸ごと消える
// （2026-08-05 実測: 622文中2件）。
//
// 文全体の再生成はコスト・レイテンシが見合わないため、欠落した文字列だけを
// 補完する小さなクエリを1回だけ投げる。補完に失敗した場合でも、発音だけは
// thai_text から直接作り直して壊れたまま返さない。
package wordgap

import (
	"fmt"
	"log"
	"sort"
	"strings"

	"github.com/mnbst/thai-memo/functions/go/internal/thainlp"
)

// Gap は欠落1件。Index は word_breakdown への挿入位置、Segment は欠落文字列。
//
// Index が -1 のときは「word_breakdown に thai_text へ無い語がある」状態で、
// 補完では直せない（呼び出し側の発音フォールバックに任せる）。
type Gap struct {
	Index   int
	Segment string
}

// GapSystemPrompt は補完クエリのシステムプロンプト。
const GapSystemPrompt = "タイ語文の単語分解から抜け落ちた部分を補う。" +
	"指定された文字列だけを語に分け、word と meaning（日本語の語義）を返す。" +
	"文全体を作り直さない。指定された文字列以外の語を足さない。"

// GapResponseSchema は補完クエリのレスポンススキーマ。
// word と meaning だけを返させる。
func GapResponseSchema() map[string]any {
	return map[string]any{
		"type": "object",
		"properties": map[string]any{
			"words": map[string]any{
				"type": "array",
				"items": map[string]any{
					"type": "object",
					"properties": map[string]any{
						"word":    map[string]any{"type": "string"},
						"meaning": map[string]any{"type": "string"},
					},
					"required":             []any{"word", "meaning"},
					"additionalProperties": false,
				},
			},
		},
		"required":             []any{"words"},
		"additionalProperties": false,
	}
}

// Word は word_breakdown の1件（欠落検出に使う最小限）。
type Word struct {
	Word    string
	Meaning string
}

// FindGaps は word_breakdown が thai_text を再構成できない箇所を返す。
// 欠落が無ければ空。
func FindGaps(thaiText string, breakdown []Word) []Gap {
	thai := strings.ReplaceAll(thaiText, " ", "")
	if thai == "" {
		return nil
	}

	var gaps []Gap
	pos := 0
	for index, entry := range breakdown {
		word := strings.ReplaceAll(entry.Word, " ", "")
		if word == "" {
			continue
		}
		rel := strings.Index(thai[pos:], word)
		if rel < 0 {
			// word_breakdown に thai_text へ無い語がある。補完では直せない。
			return []Gap{{Index: -1, Segment: ""}}
		}
		found := pos + rel
		if found > pos {
			gaps = append(gaps, Gap{Index: index, Segment: thai[pos:found]})
		}
		pos = found + len(word)
	}

	if pos < len(thai) {
		gaps = append(gaps, Gap{Index: len(breakdown), Segment: thai[pos:]})
	}
	return gaps
}

// BuildGapPrompt は欠落文字列を補完させる user prompt を組み立てる。
func BuildGapPrompt(thaiText string, gaps []Gap) string {
	segments := make([]string, 0, len(gaps))
	for _, g := range gaps {
		segments = append(segments, g.Segment)
	}
	return fmt.Sprintf(
		"タイ語文:\n<thai_text>\n%s\n</thai_text>\n\n"+
			"単語分解から抜けている文字列:\n<missing>\n%s\n</missing>\n\n"+
			"抜けている文字列だけを語に分け、出現順に words へ入れて返す。",
		thaiText, strings.Join(segments, "／"))
}

// ApplyGapWords は補完結果を word_breakdown の正しい位置へ挿入する。
// 挿入後に thai_text を再構成できれば ok=true。
func ApplyGapWords(
	thaiText string, breakdown []Word, gaps []Gap, filled []Word,
) (out []Word, ok bool) {
	if len(filled) == 0 {
		return breakdown, false
	}

	result := append([]Word(nil), breakdown...)

	remaining := make([]Word, 0, len(filled))
	for _, w := range filled {
		word := strings.TrimSpace(w.Word)
		if word == "" {
			continue
		}
		remaining = append(remaining, Word{
			Word: word, Meaning: strings.TrimSpace(w.Meaning),
		})
	}

	// 後ろの位置から挿入するとインデックスがずれない。
	sorted := append([]Gap(nil), gaps...)
	sort.SliceStable(sorted, func(a, b int) bool {
		return sorted[a].Index > sorted[b].Index
	})

	for _, gap := range sorted {
		var picked []Word
		joined := ""
		for len(remaining) > 0 && joined != gap.Segment {
			// Python は remaining.pop()（末尾から取り）、picked の先頭へ挿す。
			candidate := remaining[len(remaining)-1]
			remaining = remaining[:len(remaining)-1]
			picked = append([]Word{candidate}, picked...)

			var b strings.Builder
			for _, w := range picked {
				b.WriteString(w.Word)
			}
			joined = b.String()
		}
		if joined != gap.Segment {
			return breakdown, false
		}
		result = append(result[:gap.Index],
			append(append([]Word(nil), picked...), result[gap.Index:]...)...)
	}

	return result, len(FindGaps(thaiText, result)) == 0
}

// RepairPronunciation は word_breakdown を直せなかったときに、
// 文全体の発音だけ thai_text から作り直す。
//
// 表記は通常経路（語ごとに変換してスペース結合）に揃える。thai_text を
// そのまま一括変換すると全音節がハイフンで繋がり、語の切れ目が読めなくなる。
// 発音変換に失敗した場合は空を返し、呼び出し側は既存の値を残す。
// word_gap.py:repair_pronunciation:121 の移植。
func RepairPronunciation(thaiText string) string {
	if thaiText == "" {
		return ""
	}

	words, err := thainlp.TokenizeWords(thaiText)
	if err != nil {
		log.Printf("word_gap: pronunciation fallback failed: %v", err)
		return ""
	}
	if len(words) == 0 {
		pron, err := thainlp.ThaiToPronunciation(thaiText)
		if err != nil {
			log.Printf("word_gap: pronunciation fallback failed: %v", err)
			return ""
		}
		return pron
	}

	parts := make([]string, 0, len(words))
	for _, w := range words {
		pron, err := thainlp.ThaiToPronunciation(w)
		if err != nil {
			log.Printf("word_gap: pronunciation fallback failed: %v", err)
			return ""
		}
		parts = append(parts, pron)
	}
	return strings.Join(parts, " ")
}
