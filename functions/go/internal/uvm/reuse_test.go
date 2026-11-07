package uvm

import "testing"

func TestReusableOrder(t *testing.T) {
	cands := []Candidate{{"new", 1}, {"weak", 2}, {"prior", 3}, {"knownOld", 4}, {"knownNew", 5}, {"zero", 6}}
	pMap := map[string]float64{"weak": 0.15, "prior": ReuseMaxP, "knownOld": 0.7, "knownNew": 0.9, "zero": 0}
	lastSeen := map[string]float64{"knownOld": 10, "knownNew": 20}
	reversed := func(n int, swap func(i, j int)) {
		for i := 0; i < n/2; i++ {
			swap(i, n-1-i)
		}
	}
	got := reusableOrder(cands, pMap, lastSeen, reversed)
	want := []string{"prior", "weak", "knownOld", "knownNew"}
	if len(got) != len(want) {
		t.Fatalf("%v, want %v", got, want)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("%v, want %v", got, want)
		}
	}
}
