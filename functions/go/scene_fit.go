package function

import (
	"context"
	"log"

	"github.com/mnbst/thai-memo/functions/go/internal/quality"
	"github.com/mnbst/thai-memo/functions/go/internal/secrets"
	"github.com/mnbst/thai-memo/functions/go/internal/sentence"
	"github.com/mnbst/thai-memo/functions/go/internal/themeshots"
)

// newSceneFitter は場面の候補の採点器（Gemini Decisions）を組み立てる。
// SCENE_FIT_CHECK=0 か、キーが読めなければ nil を返し、場面は従来どおり一様に選ぶ。
func newSceneFitter(ctx context.Context) sentence.SceneFitter {
	if envOr("SCENE_FIT_CHECK", "1") == "0" {
		return nil
	}
	key, err := secrets.Get(ctx, "gemini-api-key")
	if err != nil {
		log.Printf("sceneFit: disabled (key unavailable): %v", err)
		return nil
	}
	return &themeshots.FitScorer{Asker: &quality.Gemini{APIKey: key}}
}
