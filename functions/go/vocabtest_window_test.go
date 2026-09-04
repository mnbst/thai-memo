package function

import (
	"errors"
	"strings"
	"testing"
	"time"

	"github.com/mnbst/thai-memo/functions/go/internal/callable"
)

var windowAt = time.Date(2026, 9, 3, 12, 0, 0, 0, time.UTC)

// 開始の制限判定。月1回で、中断だけ vocabTestStartsPerWindow までやり直せる。
func TestVocabTestStartCount(t *testing.T) {
	cases := []struct {
		name      string
		elapsed   time.Duration
		inWindow  bool
		measured  bool
		count     int
		want      int
		newWindow bool
		wantErr   string // エラーメッセージの一部。空なら許可
	}{
		{
			name:      "初回（起点が無い）",
			inWindow:  false,
			want:      1,
			newWindow: true,
		},
		{
			name:      "間隔が明けた",
			elapsed:   vocabTestInterval,
			inWindow:  false,
			count:     vocabTestStartsPerWindow,
			want:      1,
			newWindow: true,
		},
		{
			name:     "期間内・測り終えている",
			elapsed:  time.Hour,
			inWindow: true,
			measured: true,
			count:    1,
			wantErr:  "月1回",
		},
		{
			name:     "期間内・測り終えていて回数が残っていても断る",
			elapsed:  6 * 24 * time.Hour,
			inWindow: true,
			measured: true,
			count:    0,
			wantErr:  "月1回",
		},
		{
			name:     "期間内・中断のやり直し",
			elapsed:  time.Minute,
			inWindow: true,
			count:    1,
			want:     2,
		},
		{
			name:     "期間内・やり直しの最後の1回",
			elapsed:  time.Minute,
			inWindow: true,
			count:    vocabTestStartsPerWindow - 1,
			want:     vocabTestStartsPerWindow,
		},
		{
			name:     "期間内・やり直し上限",
			elapsed:  time.Minute,
			inWindow: true,
			count:    vocabTestStartsPerWindow,
			wantErr:  "やり直しは",
		},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			now := windowAt.Add(c.elapsed)
			got, newWindow, err := vocabTestStartCount(now, windowAt, c.inWindow, c.measured, c.count)

			if c.wantErr != "" {
				var ce *callable.Error
				if !errors.As(err, &ce) {
					t.Fatalf("err = %v, want *callable.Error", err)
				}
				if ce.Code != callable.ResourceExhausted {
					t.Errorf("code = %s, want %s", ce.Code, callable.ResourceExhausted)
				}
				if !strings.Contains(ce.Message, c.wantErr) {
					t.Errorf("message = %q, want %q を含む", ce.Message, c.wantErr)
				}
				return
			}
			if err != nil {
				t.Fatalf("err = %v, want nil", err)
			}
			if got != c.want {
				t.Errorf("count = %d, want %d", got, c.want)
			}
			if newWindow != c.newWindow {
				t.Errorf("newWindow = %v, want %v", newWindow, c.newWindow)
			}
		})
	}
}

// やり直しでは起点を据え置く（延ばせると「期限際のやり直し」で間隔が伸びる）。
func TestVocabTestStartCountKeepsWindow(t *testing.T) {
	now := windowAt
	count := 0
	for i := 0; i < vocabTestStartsPerWindow; i++ {
		now = now.Add(48 * time.Hour) // 起点が動けば、ここで間隔を超えられる
		next, newWindow, err := vocabTestStartCount(now, windowAt, true, false, count)
		if err != nil {
			t.Fatalf("%d 回目: %v", i+1, err)
		}
		if newWindow {
			t.Fatalf("%d 回目で起点が置き直された", i+1)
		}
		count = next
	}
	if _, _, err := vocabTestStartCount(now, windowAt, true, false, count); err == nil {
		t.Errorf("%d 回やり直した後も開始できた", vocabTestStartsPerWindow)
	}
}

// 案内文は「あと何日 / 何時間」。間隔ぴったりで空くので、端数は切り上げる。
func TestVocabTestNextAt(t *testing.T) {
	cases := []struct {
		elapsed time.Duration
		want    string
	}{
		{0, "あと30日で受けられます"},
		{29 * 24 * time.Hour, "あと1日で受けられます"},
		{29*24*time.Hour + 30*time.Minute, "あと24時間で受けられます"},
		{30*24*time.Hour - 30*time.Minute, "あと1時間で受けられます"},
		{30 * 24 * time.Hour, "またすぐ受けられます"},
		{31 * 24 * time.Hour, "またすぐ受けられます"},
	}
	for _, c := range cases {
		if got := vocabTestNextAt(windowAt.Add(c.elapsed), windowAt); got != c.want {
			t.Errorf("経過 %v: %q, want %q", c.elapsed, got, c.want)
		}
	}
}
