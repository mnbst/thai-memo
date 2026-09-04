package callable

import (
	"encoding/json"
	"testing"
)

func TestInt(t *testing.T) {
	cases := []struct {
		name string
		in   any
		want int
		ok   bool
	}{
		{"素の数値（JS SDK）", float64(3), 3, true},
		{"文字列", "42", 42, true},
		{"bool", true, 1, true},
		{"Int64ラッパー（Flutter）", map[string]any{
			"@type": "type.googleapis.com/google.protobuf.Int64Value",
			"value": "3",
		}, 3, true},
		{"ラッパーの中が数値", map[string]any{"value": float64(-1)}, -1, true},
		{"value の無いオブジェクト", map[string]any{"x": 1}, 0, false},
		{"nil", nil, 0, false},
		{"配列", []any{1}, 0, false},
	}
	for _, c := range cases {
		got, ok := Int(c.in)
		if got != c.want || ok != c.ok {
			t.Errorf("%s: Int(%v) = (%d, %v), want (%d, %v)",
				c.name, c.in, got, ok, c.want, c.ok)
		}
	}
}

// 実際に Flutter から届く電文の形で読めること。
func TestIntFromCallablePayload(t *testing.T) {
	const body = `{"answers":[
		{"@type":"type.googleapis.com/google.protobuf.Int64Value","value":"0"},
		{"@type":"type.googleapis.com/google.protobuf.Int64Value","value":"-1"},
		2
	]}`
	var payload struct {
		Answers []any `json:"answers"`
	}
	if err := json.Unmarshal([]byte(body), &payload); err != nil {
		t.Fatal(err)
	}
	want := []int{0, -1, 2}
	for i, raw := range payload.Answers {
		got, ok := Int(raw)
		if !ok || got != want[i] {
			t.Errorf("answers[%d] = (%d, %v), want %d", i, got, ok, want[i])
		}
	}
}
