package function

import (
	"testing"

	"github.com/mnbst/thai-memo/functions/go/internal/uvm"
)

func TestIsVocabAnswered(t *testing.T) {
	cases := []struct {
		name string
		data map[string]any
		want bool
	}{
		{"例文で見ただけ", map[string]any{"p": uvm.NewWordP, "graded": false}, false},
		{"確認クイズの正解だけ", map[string]any{"p": uvm.NewWordP, "graded": false, "quiz_attempts": int64(1)}, false},
		{"確認クイズの不正解", map[string]any{"p": 0.15, "graded": false, "quiz_attempts": int64(1)}, true},
		{"まとめクイズの回答", map[string]any{"p": 0.62, "graded": true, "quiz_attempts": int64(1)}, true},
		{"graded 導入前の回答", map[string]any{"p": 0.62, "quiz_attempts": int64(1)}, true},
		{"graded 導入前の未回答", map[string]any{"p": uvm.NewWordP}, false},
	}
	for _, c := range cases {
		if got := isVocabAnswered(c.data); got != c.want {
			t.Errorf("%s: got %v, want %v", c.name, got, c.want)
		}
	}
}

func TestVocabProgressRowRank(t *testing.T) {
	ranks := map[string]int{"ไป": 8}
	if got := vocabProgressRow("ไป", map[string]any{"p": 0.8}, ranks)["rank"]; got != 8 {
		t.Errorf("rank = %v", got)
	}
	if got := vocabProgressRow("ไม่มีในตาราง", map[string]any{"p": 0.8}, ranks)["rank"]; got != 0 {
		t.Errorf("頻度表に無い語の rank = %v", got)
	}
}

func TestVocabCursorRoundTrip(t *testing.T) {
	seen, word, ok := parseVocabCursor(formatVocabCursor(1730000000.125, "ไป"))
	if !ok || seen != 1730000000.125 || word != "ไป" {
		t.Errorf("got %v %q %v", seen, word, ok)
	}
	for _, bad := range []string{"", "abc", "abc|ไป", "123|"} {
		if _, _, ok := parseVocabCursor(bad); ok {
			t.Errorf("%q を読めてしまった", bad)
		}
	}
}
