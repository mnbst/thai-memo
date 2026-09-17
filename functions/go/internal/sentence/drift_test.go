package sentence

import (
	"context"
	"testing"

	"github.com/mnbst/thai-memo/functions/go/internal/lang"
)

// repairGenerator は書き直しクエリ1回ぶんの応答を返す。
type repairGenerator struct {
	response map[string]any
	calls    int
	schemas  []map[string]any
}

func (g *repairGenerator) GenerateSentence(
	_ context.Context, _, _ string, _ bool, _ string, schema map[string]any,
) (map[string]any, error) {
	g.calls++
	g.schemas = append(g.schemas, schema)
	return g.response, nil
}

func driftedSentence() *Sentence {
	return &Sentence{
		ThaiText:            "นี่คือเวลาคุยของเรา",
		JapaneseTranslation: "이것은 우리가 이야기하는 시간입니다",
		WordBreakdown: []Word{
			{Word: "นี่", Meaning: "これ", Notes: "주어 자리에 오는 지시 대명사"},
			{Word: "เวลา", Meaning: "時間", Notes: "時を表す名詞"},
		},
	}
}

func TestRepairLanguageRewritesOnlyDriftedFields(t *testing.T) {
	gen := &repairGenerator{response: map[string]any{
		"japanese_translation": "これは私たちが話す時間です",
		"words": []any{map[string]any{
			"word": "นี่", "meaning": "これ", "notes": "主語の位置に置く指示代名詞",
		}},
	}}
	s := driftedSentence()
	req := &Request{Lang: lang.JA, TierLabel: "premium"}

	if ok := RepairLanguage(context.Background(), gen, s, req); !ok {
		t.Fatal("RepairLanguage = false, want true")
	}
	if lang.IsWrongLanguage(s.JapaneseTranslation, lang.JA) {
		t.Errorf("訳文が直っていない: %q", s.JapaneseTranslation)
	}
	if lang.IsWrongLanguage(s.WordBreakdown[0].Notes, lang.JA) {
		t.Errorf("使い方が直っていない: %q", s.WordBreakdown[0].Notes)
	}
	if s.WordBreakdown[1].Notes != "時を表す名詞" {
		t.Errorf("ずれていない使い方を書き換えた: %q", s.WordBreakdown[1].Notes)
	}
	if gen.calls != 1 {
		t.Fatalf("LLM %d 回, want 1", gen.calls)
	}

	// 語義はずれていないので、書き直しは訳文と語だけを求める。
	properties := gen.schemas[0]["properties"].(map[string]any)
	if len(properties) != 2 {
		t.Fatalf("schema の項目 = %v", properties)
	}
}

func TestRepairLanguageBlanksNotesWhenStillDrifted(t *testing.T) {
	// 書き直しても使い方が韓国語のまま。訳文は直る。
	gen := &repairGenerator{response: map[string]any{
		"japanese_translation": "これは私たちが話す時間です",
		"words": []any{map[string]any{
			"word": "นี่", "meaning": "これ", "notes": "지시 대명사입니다",
		}},
	}}
	s := driftedSentence()

	if ok := RepairLanguage(context.Background(), gen, s,
		&Request{Lang: lang.JA}); !ok {
		t.Fatal("RepairLanguage = false, want true（訳文が直っていれば出す）")
	}
	if s.WordBreakdown[0].Notes != "" {
		t.Errorf("直らない使い方を空にしていない: %q", s.WordBreakdown[0].Notes)
	}
}

func TestRepairLanguageFailsWhenTranslationStillDrifted(t *testing.T) {
	gen := &repairGenerator{response: map[string]any{
		"japanese_translation": "이것은 우리의 시간입니다",
		"words":                []any{},
	}}
	s := driftedSentence()

	if ok := RepairLanguage(context.Background(), gen, s,
		&Request{Lang: lang.JA}); ok {
		t.Fatal("RepairLanguage = true, want false（訳文が直っていない）")
	}
	if gen.calls != 1 {
		t.Fatalf("LLM %d 回, want 1", gen.calls)
	}
}

func TestRepairLanguageSkipsWhenClean(t *testing.T) {
	gen := &repairGenerator{}
	s := &Sentence{
		ThaiText:            "นี่คือเวลาคุยของเรา",
		JapaneseTranslation: "これは私たちが話す時間です",
		WordBreakdown: []Word{
			{Word: "นี่", Meaning: "これ", Notes: "主語の位置に置く指示代名詞"},
		},
	}

	if ok := RepairLanguage(context.Background(), gen, s,
		&Request{Lang: lang.JA}); !ok {
		t.Fatal("RepairLanguage = false, want true")
	}
	if gen.calls != 0 {
		t.Fatalf("ずれていないのに %d 回叩いた", gen.calls)
	}
}

func TestLanguageDriftEN(t *testing.T) {
	s := &Sentence{
		JapaneseTranslation: "This is our time to talk.",
		WordBreakdown: []Word{
			{Word: "นี่", Meaning: "this", Notes: "a demonstrative in the subject slot"},
			// 語義の補完（wordgap）は日本語で返るため en ではずれる。
			{Word: "เวลา", Meaning: "時間", Notes: ""},
		},
	}
	drift := LanguageDrift(s, lang.EN)
	if drift.Translation {
		t.Error("英訳を誤って弾いた")
	}
	if len(drift.Meanings) != 1 || drift.Meanings[0] != 1 {
		t.Errorf("drift.Meanings = %v, want [1]", drift.Meanings)
	}
}
