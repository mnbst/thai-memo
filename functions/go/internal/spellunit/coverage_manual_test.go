package spellunit

import (
	"encoding/json"
	"math/rand"
	"os"
	"sort"
	"testing"
)

// TestCoverageByBand は出題可能率の調査用。SPELLUNIT_COVERAGE=1 で実行する。
func TestCoverageByBand(t *testing.T) {
	if os.Getenv("SPELLUNIT_COVERAGE") == "" {
		t.Skip("調査用")
	}
	raw, err := os.ReadFile("../../../../scripts/corpus/freq_rank_top10000.json")
	if err != nil {
		t.Fatal(err)
	}
	var fr map[string]int
	if err := json.Unmarshal(raw, &fr); err != nil {
		t.Fatal(err)
	}
	words := make([]string, 0, len(fr))
	for w := range fr {
		words = append(words, w)
	}
	sort.Slice(words, func(i, j int) bool { return fr[words[i]] < fr[words[j]] })

	ix, err := LoadIndex()
	if err != nil {
		t.Fatal(err)
	}
	rnd := rand.New(rand.NewSource(1))
	for _, n := range []int{100, 300, 600, 1000, 2000} {
		ok := 0
		for _, w := range words[:n] {
			if _, good := ix.Distractors(w, rnd); good {
				ok++
			}
		}
		t.Logf("top%-5d 出題可能 %3d (%.1f%%) 5問中 %.1f問",
			n, ok, 100*float64(ok)/float64(n), 5*float64(ok)/float64(n))
	}
}
