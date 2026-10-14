package uvm

import "testing"

// TestDecayP は等倍で下がり、下限で止まることを確かめる。
func TestDecayP(t *testing.T) {
	cases := []struct {
		name    string
		p, want float64
	}{
		{"等倍で下がる", 0.8, 0.799},
		{"下限で止まる", PFloor + 0.0005, PFloor},
		{"下限以下は触らない", 0.1, 0.1},
	}
	for _, c := range cases {
		got := DecayP(c.p)
		if diff := got - c.want; diff > 1e-9 || diff < -1e-9 {
			t.Errorf("%s: want %v, got %v", c.name, c.want, got)
		}
	}
}
