package sentence

import (
	"strings"
	"testing"
	"unicode"

	"github.com/mnbst/thai-memo/functions/go/internal/lang"
)

func hasHangul(s string) bool {
	for _, r := range s {
		if unicode.Is(unicode.Hangul, r) {
			return true
		}
	}
	return false
}

// TestKoreanPromptsDoNotFallBackToJA は ko が ja のプロンプトに倒れていないこと。
// 倒れると韓国語のユーザーに日本語訳が返る。
func TestKoreanPromptsDoNotFallBackToJA(t *testing.T) {
	for _, premium := range []bool{true, false} {
		ko := SystemPrompt(premium, lang.KO)
		if ko == SystemPrompt(premium, lang.JA) || !strings.Contains(ko, "韓国語") {
			t.Errorf("premium=%v: ko のシステムプロンプトが無い", premium)
		}
	}
	if !strings.Contains(stepsFor(lang.KO), "韓国語") {
		t.Error("ko の訳文の手順が無い")
	}
	schema := BuildResponseSchema([]string{"style", "emotion"}, lang.KO)
	props := schema["properties"].(map[string]any)
	desc := props["japanese_translation"].(map[string]any)["description"].(string)
	if !strings.Contains(desc, "韓国語") {
		t.Errorf("japanese_translation の description が韓国語指定でない: %s", desc)
	}
	style := props["context"].(map[string]any)["properties"].(map[string]any)["style"].(map[string]any)
	if !strings.Contains(style["description"].(string), "韓国語") {
		t.Errorf("style の description が韓国語指定でない: %v", style["description"])
	}
}

// TestKoreanLabelsCoverEnglish は ko のラベル表が en と同じキーを持つこと。
// 欠けたラベルは日本語のまま画面に出る。
func TestKoreanLabelsCoverEnglish(t *testing.T) {
	en, ko := contextLabelsByLang[lang.EN], contextLabelsByLang[lang.KO]
	check := func(name string, en, ko map[string]string) {
		for k := range en {
			// BTS・Grab・SNS のような固有名はラテン文字のまま訳すので、有無だけ見る。
			if strings.TrimSpace(ko[k]) == "" {
				t.Errorf("%s: %q の ko ラベルが無い", name, k)
			}
		}
	}
	check("topic", en.topics, ko.topics)
	check("style", en.styles, ko.styles)
	check("timeFrame", en.timeFrames, ko.timeFrames)
	for topic, subs := range en.subThemes {
		check("subTheme "+topic, subs, ko.subThemes[topic])
	}
}

func TestLocalizeContextKO(t *testing.T) {
	topic := Topics[1]
	got := LocalizeContext(map[string]any{"topic": topic, "style": Styles[1]}, lang.KO)
	if !hasHangul(got["topic"].(string)) || !hasHangul(got["style"].(string)) {
		t.Errorf("ko に差し替わっていない: %v", got)
	}
	// LLM が ko のラベルで返したテーマも正式名へ戻せる。
	head, _, _ := strings.Cut(got["topic"].(string), " (")
	if CanonicalTopic(head) != topic {
		t.Errorf("CanonicalTopic(%q) = %q, want %q", head, CanonicalTopic(head), topic)
	}
}
