package function

import "testing"

// hint_level は Flutter の SDK から Int64 ラッパーで届く。素の数値しか見て
// いなかった頃は常に 0 になり、HintMultiplier が効いていなかった。
func TestParseResultHintLevel(t *testing.T) {
	cases := []struct {
		name string
		raw  any
		want int
	}{
		{"Flutter（Int64ラッパー）", map[string]any{
			"@type": "type.googleapis.com/google.protobuf.Int64Value",
			"value": "2",
		}, 2},
		{"JS SDK（素の数値）", float64(1), 1},
		{"未送信", nil, 0},
		{"数値でない", "abc", 0},
	}
	for _, c := range cases {
		got, err := parseResult(map[string]any{
			"word":       "คำ",
			"is_correct": true,
			"hint_level": c.raw,
		})
		if err != nil {
			t.Fatalf("%s: %v", c.name, err)
		}
		if got.HintLevel != c.want {
			t.Errorf("%s: HintLevel = %d, want %d", c.name, got.HintLevel, c.want)
		}
	}
}

func TestParseResultRequiresFields(t *testing.T) {
	if _, err := parseResult(map[string]any{"is_correct": true}); err == nil {
		t.Error("word が無くてもエラーにならない")
	}
	if _, err := parseResult(map[string]any{"word": "คำ"}); err == nil {
		t.Error("is_correct が無くてもエラーにならない")
	}
}
