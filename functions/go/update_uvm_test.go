package function

import (
	"testing"

	"github.com/mnbst/thai-memo/functions/go/internal/quizgen"
	"github.com/mnbst/thai-memo/functions/go/internal/uvm"
)

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

// TestParseResultFormatScale は綴り4択だけ証拠を弱めて受けること。
func TestParseResultFormatScale(t *testing.T) {
	base := map[string]any{"word": "ออก", "is_correct": true}

	r, err := parseResult(base)
	if err != nil {
		t.Fatal(err)
	}
	if r.FormatScale != 0 {
		t.Errorf("形式を送らない回答が等倍でない: %v", r.FormatScale)
	}

	spelling := map[string]any{
		"word": "ออก", "is_correct": true,
		"quiz_format": quizgen.FormatSpellingChoice,
	}
	r, err = parseResult(spelling)
	if err != nil {
		t.Fatal(err)
	}
	if r.FormatScale != uvm.SpellingChoiceScale {
		t.Errorf("FormatScale = %v, want %v", r.FormatScale, uvm.SpellingChoiceScale)
	}
}
