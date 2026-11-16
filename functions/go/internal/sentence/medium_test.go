package sentence

import (
	"math/rand"
	"testing"
)

func TestDrawMediumWrittenHeavyTopics(t *testing.T) {
	r := &Resolver{Rand: rand.New(rand.NewSource(1))}
	count := func(topic string) float64 {
		written := 0
		for i := 0; i < 4000; i++ {
			if r.DrawMedium(topic) != Media[0].Name {
				written++
			}
		}
		return float64(written) / 4000
	}
	if got := count(Topics[12]); got < 0.45 || got > 0.55 {
		t.Errorf("伝統・祭りの解説文の割合 = %.2f, want 約0.5", got)
	}
	if got := count(Topics[1]); got < 0.2 || got > 0.3 {
		t.Errorf("食べ物の解説文の割合 = %.2f, want 約0.25", got)
	}
}
