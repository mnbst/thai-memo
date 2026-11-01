package uvm

import (
	"math/rand"
	"testing"
)

// 枠ごとに寄せ先の合う語を選び、合う語が無い枠だけ残りから選ぶ。同じ語は二度選ばない。
func TestSelectLeaningEach(t *testing.T) {
	s := &SessionSelector{Rand: rand.New(rand.NewSource(1))}
	zeroP := []Candidate{cand("ก", 100), cand("ข", 110), cand("ค", 120), cand("ง", 130)}
	is := func(w string) func(string) bool { return func(x string) bool { return x == w } }
	never := func(string) bool { return false }

	got := s.selectLeaningEach(zeroP, []func(string) bool{is("ค"), is("ค"), is("ก"), never}, 4)
	if len(got) != 4 {
		t.Fatalf("本数 %d, want 4: %v", len(got), words(got))
	}
	if got[0].Word != "ค" || got[2].Word != "ก" {
		t.Errorf("枠の寄せ先を先に選ぶこと: %v", words(got))
	}
	seen := map[string]bool{}
	for _, c := range got {
		if seen[c.Word] {
			t.Errorf("同じ語を二度選んだ: %v", words(got))
		}
		seen[c.Word] = true
	}
}
