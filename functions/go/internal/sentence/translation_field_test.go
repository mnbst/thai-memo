package sentence

import (
	"encoding/json"
	"strings"
	"testing"

	"github.com/mnbst/thai-memo/functions/go/internal/lang"
)

// ja 以外では LLM に見せる訳の欄を translation にし、応答は japanese_translation へ戻す。
func TestNeutralTranslationField(t *testing.T) {
	for _, l := range []lang.Lang{lang.EN, lang.KO} {
		schema := neutralSchema(BuildResponseSchema([]string{"style"}, l))
		b, _ := json.Marshal(schema)
		if strings.Contains(string(b), "japanese_translation") {
			t.Errorf("%s: 応答の形式に japanese_translation が残っている", l)
		}
		props := schema["properties"].(map[string]any)
		if _, ok := props["translation"]; !ok {
			t.Errorf("%s: 応答の形式に translation が無い", l)
		}
		for _, p := range []string{SystemPrompt(true, l), SystemPrompt(false, l), stepsFor(l)} {
			if strings.Contains(neutralTranslationField(p), "japanese_translation") {
				t.Errorf("%s: プロンプトに japanese_translation が残っている", l)
			}
		}
	}
	raw := map[string]any{"thai_text": "ผมกินข้าว", "translation": "I eat rice."}
	restoreTranslationField(raw)
	if raw["japanese_translation"] != "I eat rice." || raw["translation"] != nil {
		t.Errorf("訳が japanese_translation に戻っていない: %v", raw)
	}
}
