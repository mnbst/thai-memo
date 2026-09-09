package function

import (
	"testing"

	"github.com/mnbst/thai-memo/functions/go/internal/sentence"
)

// TestRequestedSetSize は本数指定の解釈を確かめる。
// 旧クライアントは count を送らないので、必ず従来どおり1本になること。
func TestRequestedSetSize(t *testing.T) {
	cases := []struct {
		name   string
		params map[string]any
		want   int
	}{
		{"旧クライアント（未指定）", map[string]any{}, 1},
		{"nil", map[string]any{"count": nil}, 1},
		{"1本", map[string]any{"count": int64(1)}, 1},
		{"セット", map[string]any{"count": int64(5)}, sentence.SetSize},
		{"JSON の数値は float64", map[string]any{"count": float64(5)}, sentence.SetSize},
		{"上限を超えても増やさない", map[string]any{"count": int64(50)}, sentence.SetSize},
		{"0 以下は1本", map[string]any{"count": int64(0)}, 1},
		{"負値も1本", map[string]any{"count": int64(-3)}, 1},
		{"文字列でも数なら読む", map[string]any{"count": "5"}, sentence.SetSize},
		{"読めない値は1本", map[string]any{"count": "many"}, 1},
		// Flutter の Firebase SDK は Dart の int をこの形で送る。
		// ここを素の数値だと思って読むと、常に1本に落ちる。
		{
			"Dart の int（Int64 ラッパー）",
			map[string]any{"count": map[string]any{
				"@type": "type.googleapis.com/google.protobuf.Int64Value",
				"value": float64(5),
			}},
			sentence.SetSize,
		},
		{
			"ラッパーの value が文字列でも読む",
			map[string]any{"count": map[string]any{
				"@type": "type.googleapis.com/google.protobuf.Int64Value",
				"value": "5",
			}},
			sentence.SetSize,
		},
	}
	for _, c := range cases {
		if got := requestedSetSize(c.params); got != c.want {
			t.Errorf("%s: requestedSetSize = %d, want %d", c.name, got, c.want)
		}
	}
}
