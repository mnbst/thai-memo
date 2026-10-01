package sentence

import "testing"

func TestSetSizeFor(t *testing.T) {
	beginner := func(vocab any) map[string]any {
		return map[string]any{
			"interview":       map[string]any{"level": "none"},
			"estimated_vocab": vocab,
		}
	}
	words := func(vocab any) map[string]any {
		return map[string]any{
			"interview":       map[string]any{"level": "words"},
			"estimated_vocab": vocab,
		}
	}
	cases := []struct {
		name     string
		userData map[string]any
		want     int
	}{
		{"ヒアリング未回答", map[string]any{"estimated_vocab": int64(0)}, SetSize},
		{"chars は縮めない", map[string]any{
			"interview":       map[string]any{"level": "chars"},
			"estimated_vocab": int64(0),
		}, SetSize},
		{"入門 語彙なし", beginner(nil), 2},
		{"入門 0", beginner(int64(0)), 2},
		{"入門 16", beginner(int64(16)), 2},
		{"入門 17", beginner(int64(17)), 3},
		{"入門 33", beginner(int64(33)), 3},
		{"入門 34", beginner(int64(34)), 4},
		{"入門 49", beginner(float64(49)), 4},
		{"入門 50", beginner(int64(50)), SetSize},
		{"入門 300", beginner(int64(300)), SetSize},
		{"単語 0", words(int64(0)), 3},
		{"単語 24", words(int64(24)), 3},
		{"単語 25", words(int64(25)), 4},
		{"単語 49", words(int64(49)), 4},
		{"単語 50", words(int64(50)), SetSize},
	}
	for _, c := range cases {
		if got := SetSizeFor(c.userData); got != c.want {
			t.Errorf("%s: SetSizeFor = %d, want %d", c.name, got, c.want)
		}
	}
}
