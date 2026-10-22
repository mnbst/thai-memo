package thainlp

import (
	"testing"

	"github.com/mnbst/thai-memo/functions/go/internal/lang"
)

func TestLocalizePOSKO(t *testing.T) {
	for label := range posLabelEN {
		if _, ok := posLabelKO[label]; !ok {
			t.Errorf("%s の ko ラベルが無い", label)
		}
	}
	if got := LocalizePOS("名詞", lang.KO); got != "명사" {
		t.Errorf("got %q", got)
	}
	if got := LocalizePOS("名詞", lang.JA); got != "名詞" {
		t.Errorf("ja は日本語のまま: got %q", got)
	}
}
