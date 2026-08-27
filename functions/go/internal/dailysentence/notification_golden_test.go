package dailysentence

import (
	"encoding/json"
	"os"
	"testing"

	"github.com/mnbst/thai-memo/functions/go/internal/lang"
)

// TestNotificationGolden は通知の文面が Python 実装と一致することを確かめる。
// golden は scripts/daily_golden/gen_notification_golden.py が生成する。
func TestNotificationGolden(t *testing.T) {
	raw, err := os.ReadFile("../../../python/scripts/daily_golden/notification_golden.json")
	if err != nil {
		t.Fatalf("golden を読めない: %v", err)
	}
	var golden struct {
		Cases []struct {
			Sentence map[string]any `json:"sentence"`
			Lang     string         `json:"lang"`
			Title    string         `json:"title"`
			Body     string         `json:"body"`
		} `json:"cases"`
	}
	if err := json.Unmarshal(raw, &golden); err != nil {
		t.Fatalf("golden を parse できない: %v", err)
	}
	if len(golden.Cases) == 0 {
		t.Fatal("golden が空")
	}

	bodyLines := map[int]int{}
	titleKinds := map[string]int{}
	for _, c := range golden.Cases {
		title, body := BuildNotificationText(c.Sentence, lang.Lang(c.Lang))
		if title != c.Title {
			t.Errorf("title 不一致 lang=%q sentence=%v\n got: %q\nwant: %q",
				c.Lang, c.Sentence, title, c.Title)
		}
		if body != c.Body {
			t.Errorf("body 不一致 lang=%q sentence=%v\n got: %q\nwant: %q",
				c.Lang, c.Sentence, body, c.Body)
		}
		bodyLines[countLines(body)]++
		titleKinds[titleKind(c.Sentence)]++
	}
	t.Logf("%d ケース一致", len(golden.Cases))

	// タイトルの3分岐と、本文の行数 0〜3 が全て踏まれていること。
	for _, k := range []string{"none", "word_only", "word_and_meaning"} {
		if titleKinds[k] == 0 {
			t.Errorf("タイトル %s のケースが無い。golden が退化している", k)
		}
	}
	for n := 0; n <= 3; n++ {
		if bodyLines[n] == 0 {
			t.Errorf("本文 %d 行のケースが無い。golden が退化している", n)
		}
	}
}

func countLines(body string) int {
	if body == "" {
		return 0
	}
	n := 1
	for _, r := range body {
		if r == '\n' {
			n++
		}
	}
	return n
}

func titleKind(sentence map[string]any) string {
	switch {
	case trimmedField(sentence, "key_word") == "":
		return "none"
	case trimmedField(sentence, "key_word_meaning") == "":
		return "word_only"
	default:
		return "word_and_meaning"
	}
}
