package sentence

import (
	"context"
	"fmt"
	"log"
	"strings"

	"github.com/mnbst/thai-memo/functions/go/internal/lang"
)

// モデルは稀に指定と違う言語で書く。クイズ側（internal/gemini/repair.go）と
// 同じく、ずれたフィールドだけ書き直させる。文全体は作り直さない。
//
// 見るのは訳文・語義・使い方の3つ。thai_text と発音は言語指定の対象外。

// Drift はどのフィールドがずれているか。Index は word_breakdown の位置。
type Drift struct {
	Translation bool
	Meanings    []int
	Notes       []int
}

// Any はずれが1つでもあるか。
func (d Drift) Any() bool {
	return d.Translation || len(d.Meanings) > 0 || len(d.Notes) > 0
}

// essential は訳文・語義のずれ。空にして出すわけにいかないフィールド。
func (d Drift) essential() bool { return d.Translation || len(d.Meanings) > 0 }

// wordIndexes は書き直しを求める語の位置（語義・使い方をまとめたもの）。
func (d Drift) wordIndexes() []int {
	seen := make(map[int]bool, len(d.Meanings)+len(d.Notes))
	out := make([]int, 0, len(d.Meanings)+len(d.Notes))
	for _, group := range [][]int{d.Meanings, d.Notes} {
		for _, i := range group {
			if !seen[i] {
				seen[i] = true
				out = append(out, i)
			}
		}
	}
	return out
}

// LanguageDrift は言語がずれているフィールドを返す。
func LanguageDrift(s *Sentence, l lang.Lang) Drift {
	drift := Drift{Translation: lang.IsWrongLanguage(s.JapaneseTranslation, l)}
	for i, w := range s.WordBreakdown {
		if lang.IsWrongLanguage(w.Meaning, l) {
			drift.Meanings = append(drift.Meanings, i)
		}
		if lang.IsWrongLanguage(w.Notes, l) {
			drift.Notes = append(drift.Notes, i)
		}
	}
	return drift
}

var driftLanguageName = map[lang.Lang]string{lang.JA: "日本語", lang.EN: "英語"}

// RepairLanguage は言語がずれたフィールドだけ書き直させる。
//
// 直らなかった使い方は空にする（アプリはこの欄が空でも例文を出せる）。
// 訳文・語義が直らなければ ok=false を返し、呼び出し側で文ごと作り直す。
func RepairLanguage(
	ctx context.Context, gen Generator, s *Sentence, req *Request,
) (ok bool) {
	drift := LanguageDrift(s, req.Lang)
	if !drift.Any() {
		return true
	}
	log.Printf("language drift detected: translation=%v meanings=%v notes=%v in %s",
		drift.Translation, drift.Meanings, drift.Notes, s.ThaiText)

	if err := fillLanguageRepair(ctx, gen, s, drift, req); err != nil {
		// 書き直しの失敗で生成全体を落とさない。残りは下の判定で扱う。
		log.Printf("language repair failed: %v", err)
	}

	remaining := LanguageDrift(s, req.Lang)
	for _, i := range remaining.Notes {
		s.WordBreakdown[i].Notes = ""
	}
	if remaining.essential() {
		log.Printf("language repair gave up: translation=%v meanings=%v in %s",
			remaining.Translation, remaining.Meanings, s.ThaiText)
		return false
	}
	return true
}

func fillLanguageRepair(
	ctx context.Context, gen Generator, s *Sentence, drift Drift, req *Request,
) error {
	raw, err := gen.GenerateSentence(ctx,
		LanguageRepairSystemPrompt(req.Lang),
		BuildLanguageRepairPrompt(s, drift),
		req.IsPremium,
		req.TierLabel+"-lang",
		LanguageRepairSchema(drift),
	)
	if err != nil {
		return err
	}

	var repaired struct {
		JapaneseTranslation string `json:"japanese_translation"`
		Words               []Word `json:"words"`
	}
	if err := remarshal(raw, &repaired); err != nil {
		return err
	}
	applyLanguageRepair(s, drift, repaired.JapaneseTranslation, repaired.Words)
	return nil
}

// applyLanguageRepair は書き直しを求めたフィールドだけ差し替える。
// 語は綴りで突き合わせる（位置を返し間違えても別の語を壊さない）。
func applyLanguageRepair(
	s *Sentence, drift Drift, translation string, words []Word,
) {
	if drift.Translation && strings.TrimSpace(translation) != "" {
		s.JapaneseTranslation = translation
	}

	byWord := make(map[string]Word, len(words))
	for _, w := range words {
		byWord[strings.TrimSpace(w.Word)] = w
	}
	for _, i := range drift.Meanings {
		if w, found := byWord[strings.TrimSpace(s.WordBreakdown[i].Word)]; found &&
			strings.TrimSpace(w.Meaning) != "" {
			s.WordBreakdown[i].Meaning = w.Meaning
		}
	}
	for _, i := range drift.Notes {
		if w, found := byWord[strings.TrimSpace(s.WordBreakdown[i].Word)]; found &&
			strings.TrimSpace(w.Notes) != "" {
			s.WordBreakdown[i].Notes = w.Notes
		}
	}
}

// LanguageRepairSystemPrompt は書き直しクエリのシステムプロンプト。
func LanguageRepairSystemPrompt(l lang.Lang) string {
	if l != lang.EN {
		l = lang.JA
	}
	return fmt.Sprintf(
		"渡された項目が指定と違う言語で書かれている。%sで書き直す。"+
			"述べている中身は変えず、訳し直すだけ。新しい内容を足さない。"+
			"タイ語の語はそのまま返す。渡された項目以外は返さない。",
		driftLanguageName[l])
}

// BuildLanguageRepairPrompt は書き直させる中身（現在の値）を並べる。
func BuildLanguageRepairPrompt(s *Sentence, drift Drift) string {
	var b strings.Builder
	fmt.Fprintf(&b, "タイ語文:\n<thai_text>\n%s\n</thai_text>\n", s.ThaiText)

	if drift.Translation {
		fmt.Fprintf(&b, "\njapanese_translation: %s\n", s.JapaneseTranslation)
	}
	if indexes := drift.wordIndexes(); len(indexes) > 0 {
		b.WriteString("\nwords:\n")
		for _, i := range indexes {
			w := s.WordBreakdown[i]
			fmt.Fprintf(&b, "- word: %s\n  meaning: %s\n", w.Word, w.Meaning)
			if w.Notes != "" {
				fmt.Fprintf(&b, "  notes: %s\n", w.Notes)
			}
		}
	}
	b.WriteString("\n渡した項目だけを書き直して返す。")
	return b.String()
}

// LanguageRepairSchema は書き直させるフィールドだけのレスポンススキーマ。
func LanguageRepairSchema(drift Drift) map[string]any {
	properties := map[string]any{}
	required := make([]any, 0, 2)

	if drift.Translation {
		properties["japanese_translation"] = map[string]any{"type": "string"}
		required = append(required, "japanese_translation")
	}
	if len(drift.wordIndexes()) > 0 {
		properties["words"] = map[string]any{
			"type": "array",
			"items": map[string]any{
				"type": "object",
				"properties": map[string]any{
					"word":    map[string]any{"type": "string"},
					"meaning": map[string]any{"type": "string"},
					"notes":   map[string]any{"type": "string"},
				},
				"required":             []any{"word", "meaning"},
				"additionalProperties": false,
			},
		}
		required = append(required, "words")
	}
	return map[string]any{
		"type":                 "object",
		"properties":           properties,
		"required":             required,
		"additionalProperties": false,
	}
}
