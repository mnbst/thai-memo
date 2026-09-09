package dailysentence

import (
	"testing"

	"github.com/mnbst/thai-memo/functions/go/internal/lang"
)

func TestBatchSize(t *testing.T) {
	cases := []struct {
		version string
		want    int
	}{
		{"1.4.8", DailyBatchSize},
		{"1.4.9", DailyBatchSize},
		{"1.5.0", DailyBatchSize},
		{"2.0.0", DailyBatchSize},
		{"1.4.10", DailyBatchSize},
		{"1.4.7", 1},
		{"1.3.99", 1},
		{"0.9.9", 1},
		// パースできない値は安全側（1本）。旧版に5本送ると4本が履歴に埋もれる。
		{"", 1},
		{"1.4", 1},
		{"1.4.8+12", 1},
		{"1.4.8-beta", 1},
		{"v1.4.8", 1},
	}
	for _, c := range cases {
		if got := BatchSize(map[string]any{"app_version": c.version}); got != c.want {
			t.Errorf("BatchSize(%q) = %d, want %d", c.version, got, c.want)
		}
	}
	// 未報告ユーザー（起動時ミラー前）も1本。
	if got := BatchSize(map[string]any{}); got != 1 {
		t.Errorf("app_version 未設定 = %d, want 1", got)
	}
}

// TestNotificationSetSize は5本セットの本数がタイトルに載ることを確かめる。
func TestNotificationSetSize(t *testing.T) {
	withWord := map[string]any{"key_word": "กิน", "key_word_meaning": "食べる"}
	noWord := map[string]any{"thai_text": "ฉันกินข้าว"}
	cases := []struct {
		sentence map[string]any
		size     int
		l        lang.Lang
		want     string
	}{
		{withWord, 1, lang.JA, "🇹🇭 今日のタイ語 · กิน（食べる）"},
		{withWord, 5, lang.JA, "🇹🇭 今日のタイ語 · กิน（食べる） ほか4本"},
		{withWord, 5, lang.EN, "🇹🇭 Thai of the Day · กิน (食べる) +4 more"},
		// key_word が無ければ「ほか」の起点が無いので総数を出す。
		{noWord, 5, lang.JA, "🇹🇭 今日のタイ語 · 5本"},
		{noWord, 5, lang.EN, "🇹🇭 Thai of the Day · 5 sentences"},
	}
	for _, c := range cases {
		got, _ := BuildNotificationText(c.sentence, c.size, c.l)
		if got != c.want {
			t.Errorf("size=%d lang=%s\n got: %q\nwant: %q", c.size, c.l, got, c.want)
		}
	}
}
