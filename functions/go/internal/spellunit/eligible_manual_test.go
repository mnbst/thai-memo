package spellunit

import (
	"encoding/json"
	"math/rand"
	"os"
	"testing"
)

// TestDumpEligible は綴り4択にできる語の一覧を書き出す（調査用）。
// SPELLUNIT_ELIGIBLE_OUT=/path/to.json で実行する。
func TestDumpEligible(t *testing.T) {
	out := os.Getenv("SPELLUNIT_ELIGIBLE_OUT")
	if out == "" {
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
	ix, err := LoadIndex()
	if err != nil {
		t.Fatal(err)
	}
	rnd := rand.New(rand.NewSource(1))
	eligible := map[string]int{}
	for w, rank := range fr {
		if _, ok := ix.Distractors(w, rnd); ok {
			eligible[w] = rank
		}
	}
	buf, _ := json.Marshal(eligible)
	if err := os.WriteFile(out, buf, 0o644); err != nil {
		t.Fatal(err)
	}
	t.Logf("%d 語を書き出した", len(eligible))
}
