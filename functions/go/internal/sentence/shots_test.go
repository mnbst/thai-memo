package sentence

import (
	"context"
	"errors"
	"strings"
	"testing"
)

type promptCapture struct{ prompt string }

func (g *promptCapture) GenerateSentence(_ context.Context, _, userPrompt string,
	_ bool, _ string, _ map[string]any) (map[string]any, error) {
	g.prompt = userPrompt
	return nil, errors.New("stop")
}

type fixedShots struct{}

func (fixedShots) BuildShotSection(topic string, _ []string, _ string) DramaSection {
	if topic != Topics[1] {
		return DramaSection{}
	}
	return DramaSection{Context: "- 場面: 注文する\n", Required: "- 参考例の丁寧さに合わせる\n"}
}

// 参考例文が付く回は、場面がサブテーマの代わりになる。テーマはカッコ内の
// 下位項目を落として出す。関係の指定は残す。
func TestShotSectionReplacesSubThemeAndRelation(t *testing.T) {
	gen := &promptCapture{}
	svc := &Service{Gen: gen, Resolver: &Resolver{}, Shots: fixedShots{}}
	params := map[string]any{"topic": Topics[1], "medium": Media[0].Name}
	_, _ = svc.GenerateSentence(context.Background(), params, true, []string{"อร่อย"}, 800, "ja")

	for _, want := range []string{"- 場面: 注文する", "- 参考例の丁寧さに合わせる", "- テーマ: 食べ物\n"} {
		if !strings.Contains(gen.prompt, want) {
			t.Errorf("プロンプトに %q が無い", want)
		}
	}
	if strings.Contains(gen.prompt, "- サブテーマ:") {
		t.Error("サブテーマの行が残っている")
	}
	if strings.Contains(gen.prompt, Topics[1]) {
		t.Error("テーマの下位項目が残っている")
	}
	if !strings.Contains(gen.prompt, "【話し手と聞き手】") {
		t.Error("関係の指定が消えた")
	}

	// ショットの無いテーマはそのまま。
	_, _ = svc.GenerateSentence(context.Background(), map[string]any{"topic": Topics[3]}, true, []string{"งาน"}, 800, "ja")
	if strings.Contains(gen.prompt, "- 場面:") {
		t.Error("ショットの無いテーマに場面が付いた")
	}
	if !strings.Contains(gen.prompt, "- テーマ: "+Topics[3]) {
		t.Error("ショットの無いテーマのラベルが変わった")
	}
}

// 相手のいない媒体は参考例文とセットでしか使わない。例文に媒体が付かない回
// （会話のショット・ショットの無いテーマ・テーマ未確定）は対面の会話へ戻す。
func TestSceneSectionFallsBackToConversation(t *testing.T) {
	svc := &Service{Shots: fixedShots{}}
	for _, topic := range []string{Topics[1], Topics[2], ""} {
		r := ResolvedParams{Topic: topic, Medium: Media[1].Name}
		svc.SceneSection(&r, []string{"ไป"})
		if r.Medium != Media[0].Name {
			t.Errorf("topic=%q: medium=%q のまま", topic, r.Medium)
		}
	}
}
