package sentence

import (
	"context"
	"errors"
	"strings"
	"testing"
)

type tierCapture struct {
	system, prompt, tierLabel string
	isPremium                 bool
}

func (g *tierCapture) GenerateSentence(_ context.Context, systemPrompt, userPrompt string,
	isPremium bool, tierLabel string, _ map[string]any) (map[string]any, error) {
	g.system, g.prompt, g.isPremium, g.tierLabel = systemPrompt, userPrompt, isPremium, tierLabel
	return nil, errors.New("stop")
}

// free も premium と同じプロンプト・モデル設定で作る。ラベルだけは実際のティアを残す。
func TestFreeGeneratesWithPremiumPrompt(t *testing.T) {
	for _, isPremium := range []bool{false, true} {
		gen := &tierCapture{}
		svc := &Service{Gen: gen, Resolver: &Resolver{}}
		params := map[string]any{"topic": Topics[2]}
		_, _ = svc.GenerateSentence(context.Background(), params, isPremium, []string{"ไป"}, 50, "ja")

		if gen.system != SystemPrompt(true, "ja") {
			t.Errorf("isPremium=%v: premium のシステムプロンプトになっていない", isPremium)
		}
		if !gen.isPremium {
			t.Errorf("isPremium=%v: premium のモデル設定で呼んでいない", isPremium)
		}
		if !strings.Contains(gen.prompt, "【話し手と聞き手】") {
			t.Errorf("isPremium=%v: 関係の指定（premium のブロック）が無い", isPremium)
		}
		want := "free"
		if isPremium {
			want = "premium"
		}
		if gen.tierLabel != want {
			t.Errorf("isPremium=%v: ラベル %q want %q", isPremium, gen.tierLabel, want)
		}
	}
}
