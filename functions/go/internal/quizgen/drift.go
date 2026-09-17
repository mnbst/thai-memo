package quizgen

import (
	"fmt"
	"strings"

	"github.com/mnbst/thai-memo/functions/go/internal/lang"
)

// 出力フィールド名。ドリフトの検出結果と再出力の要求に使う。
// 文字での判定は lang.IsWrongLanguage（他の生成経路と共通）。
const (
	FieldExplanation  = "explanation"
	FieldDummyReasons = "dummy_reasons"
)

// DriftedFields は Draft のうち言語がずれているフィールド名を返す。
// dummies はタイ語なので見ない。
func DriftedFields(draft Draft, l lang.Lang) []string {
	var fields []string
	if lang.IsWrongLanguage(draft.Explanation, l) {
		fields = append(fields, FieldExplanation)
	}
	for _, reason := range draft.DummyReasons {
		if lang.IsWrongLanguage(reason, l) {
			fields = append(fields, FieldDummyReasons)
			break
		}
	}
	return fields
}

var repairLanguageName = map[lang.Lang]string{lang.JA: "日本語", lang.EN: "英語"}

// RepairSystemPrompt は言語がずれたフィールドだけ書き直させる指示。
//
// 書式はそのまま残させる。dummy_reasons の「語（ローマ字 / 意味）：理由」は
// extractDummyPronunciation が依存しており、崩すと4択の発音が空になる。
func RepairSystemPrompt(fields []string, l lang.Lang) string {
	if l != lang.EN {
		l = lang.JA
	}
	var rules []string
	for _, field := range fields {
		switch field {
		case FieldExplanation:
			rules = append(rules, "- "+explanationRule[l])
		case FieldDummyReasons:
			rules = append(rules, "- "+dummyReasonFormat[l])
		}
	}
	return fmt.Sprintf(`渡された項目が指定と違う言語で書かれています。%sで書き直してください。

【出力】
%s の%d項目のみ。
%s

【書き直し方】
- 述べている中身は変えない。訳し直すだけで、新しい内容を足さない
- タイ語の語・ローマ字・括弧・区切り記号は元のまま残す
- dummy_reasons は渡された行数と同じ数、同じ順で返す`,
		repairLanguageName[l],
		strings.Join(fields, " / "), len(fields),
		strings.Join(rules, "\n"))
}

// BuildRepairPrompt は書き直させる中身（現在の値）を並べる。
func BuildRepairPrompt(draft Draft, fields []string) string {
	var b strings.Builder
	b.WriteString("以下の項目を書き直してください。\n")
	for _, field := range fields {
		switch field {
		case FieldExplanation:
			b.WriteString("\nexplanation: " + draft.Explanation + "\n")
		case FieldDummyReasons:
			b.WriteString("\ndummy_reasons:\n")
			for _, reason := range draft.DummyReasons {
				b.WriteString("- " + reason + "\n")
			}
		}
	}
	return strings.TrimRight(b.String(), "\n")
}
