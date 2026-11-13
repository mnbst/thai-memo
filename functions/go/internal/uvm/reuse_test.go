package uvm

import "testing"

func TestReusableOrder(t *testing.T) {
	cands := []Candidate{
		{"new", 1}, {"priorA", 2}, {"weak", 3}, {"priorB", 4}, {"shown", 5},
		{"knownHigh", 6}, {"knownLow", 7}, {"zero", 8},
	}
	pMap := map[string]float64{
		"weak": 0.15, "priorA": NewWordP, "priorB": NewWordP,
		"shown":     KeyWordExposureP(NewWordP),
		"knownHigh": 0.9, "knownLow": 0.7, "zero": 0,
	}
	reversed := func(n int, swap func(i, j int)) {
		for i := 0; i < n/2; i++ {
			swap(i, n-1-i)
		}
	}
	got := reusableOrder(cands, pMap, reversed)
	// P の小さい順、同点は shuffle の順。出したばかりの語（shown）は同じ P だった語の後ろ。
	want := []string{"weak", "priorB", "priorA", "shown", "knownLow", "knownHigh"}
	if len(got) != len(want) {
		t.Fatalf("%v, want %v", got, want)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("%v, want %v", got, want)
		}
	}
}

// TestKeyWordExposureSteps は key_word の露出だけで P がどこまで速く動くかを固定する。
// 未回答の語が「覚えた」側（LearnedP）へ入るまでの回数。幅を広げるとここで落ちる。
func TestKeyWordExposureSteps(t *testing.T) {
	p, n := NewWordP, 0
	for p <= LearnedP {
		p = KeyWordExposureP(p)
		n++
	}
	if n < 10 {
		t.Errorf("未回答の語が %d 回の露出で LearnedP を超える（10 回以上にする）", n)
	}
}
