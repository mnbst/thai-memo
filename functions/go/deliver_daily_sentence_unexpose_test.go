package function

import (
	"reflect"
	"testing"
)

func TestPurgedKeyWords(t *testing.T) {
	docs := []deliveredDoc{
		{ID: "a", Data: map[string]any{"key_word": "มัน"}},
		{ID: "b", Data: map[string]any{"key_word": "ดี"}},
		{ID: "c", Data: map[string]any{"key_word": "มัน"}},
		{ID: "d", Data: map[string]any{"key_word": "ใช่"}}, // 今回は印を付けていない
		{ID: "e", Data: map[string]any{}},                  // key_word 無し
	}
	purged := map[string]bool{"a": true, "b": true, "c": true, "e": true}
	got := purgedKeyWords(docs, purged)
	want := []string{"ดี", "มัน"}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("purgedKeyWords = %v, want %v", got, want)
	}
}

func TestIsExposureOnlyUVM(t *testing.T) {
	cases := []struct {
		name string
		data map[string]any
		want bool
	}{
		{"露出だけ", map[string]any{"p": 0.4, "quiz_attempts": int64(0), "evidence": 0.0}, true},
		{"露出を重ねただけ", map[string]any{"p": 0.43, "quiz_attempts": int64(0), "evidence": 0.0}, true},
		{"答えたことがある", map[string]any{"p": 0.6, "quiz_attempts": int64(1), "evidence": 1.0}, false},
		{"証拠だけある", map[string]any{"p": 0.4, "quiz_attempts": int64(0), "evidence": 0.1}, false},
		{"回数だけある（evidence 導入前）", map[string]any{"p": 0.6, "quiz_attempts": int64(2)}, false},
	}
	for _, c := range cases {
		if got := isExposureOnlyUVM(c.data); got != c.want {
			t.Errorf("%s: got %v, want %v", c.name, got, c.want)
		}
	}
}

func TestHasLiveSentence(t *testing.T) {
	purged := map[string]bool{"p1": true}
	cases := []struct {
		name string
		docs []deliveredDoc
		want bool
	}{
		{"今回消した doc だけ", []deliveredDoc{{ID: "p1", Data: map[string]any{"deleted": true}}}, false},
		{"前に消した doc だけ", []deliveredDoc{
			{ID: "p1", Data: map[string]any{}},
			{ID: "old", Data: map[string]any{"deleted": true}},
		}, false},
		{"ほかに生きた例文がある", []deliveredDoc{
			{ID: "p1", Data: map[string]any{}},
			{ID: "live", Data: map[string]any{"viewed": true}},
		}, true},
		{"今回配信した未読の例文も生きている", []deliveredDoc{
			{ID: "new", Data: map[string]any{"daily": true, "viewed": false}},
		}, true},
	}
	for _, c := range cases {
		if got := hasLiveSentence(c.docs, purged); got != c.want {
			t.Errorf("%s: got %v, want %v", c.name, got, c.want)
		}
	}
}
