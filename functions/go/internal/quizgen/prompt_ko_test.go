package quizgen

import (
	"testing"

	"github.com/mnbst/thai-memo/functions/go/internal/lang"
)

// TestKoreanQuizPromptsDoNotFallBackToJA は ko のクイズ指示が ja に倒れていないこと。
func TestKoreanQuizPromptsDoNotFallBackToJA(t *testing.T) {
	if SystemPrompt(lang.KO) == SystemPrompt(lang.JA) {
		t.Error("穴埋めの指示が ja のまま")
	}
	if fixedDummyPrompt(lang.KO) == fixedDummyPrompt(lang.JA) {
		t.Error("ダミー確定版の指示が ja のまま")
	}
	if meaningSystemPrompt[lang.KO] == "" {
		t.Error("意味4択の指示が無い")
	}
	if RepairSystemPrompt([]string{FieldExplanation}, lang.KO) ==
		RepairSystemPrompt([]string{FieldExplanation}, lang.JA) {
		t.Error("書き直しの指示が ja のまま")
	}
}

// TestKoreanReasonFormatKeepsPronunciation は ko の理由の書式から発音を切り出せること。
func TestKoreanReasonFormatKeepsPronunciation(t *testing.T) {
	got := extractDummyPronunciation("แกง (kɛɛng / 카레): 동사가 올 자리에 명사가 와서 문법적으로 어색함", "แกง")
	if got != "kɛɛng" {
		t.Errorf("got %q", got)
	}
}
