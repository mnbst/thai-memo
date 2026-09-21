package dailysentence

import (
	"testing"
	"time"
)

// TestIsDueToleratesHourlyJitter は、毎時起動の開始時刻の揺れで丸1日
// 見送られないことを確かめる。
//
// 実際に起きた並び（prod 2026-09-19〜21、notify_utc_hour=1）:
//
//	09-19 01:00:11 配信 → last_notified_at = 01:00:11
//	09-20 01:00:03 起動 → 期日ちょうどだと 8 秒足りず not_due で1日飛ぶ
//	09-21 01:00:16 起動 → ここで復帰
//
// 対象時刻の起動は日に1回なので、1回の見送りがそのまま1日ぶんの欠落になる。
func TestIsDueToleratesHourlyJitter(t *testing.T) {
	lastNotified := time.Date(2026, 9, 19, 1, 0, 11, 0, time.UTC)
	data := map[string]any{"last_notified_at": lastNotified}

	nextRun := time.Date(2026, 9, 20, 1, 0, 3, 0, time.UTC)
	if !IsDue(data, nextRun) {
		t.Errorf("前日より %v 早い起動で見送っている", lastNotified.Add(24*time.Hour).Sub(nextRun))
	}
}

// TestIsDueKeepsInterval は前倒しが間隔そのものを崩さないこと。
// DueSlack を超えて早い起動（＝同じ日の別の周回）は見送る。
func TestIsDueKeepsInterval(t *testing.T) {
	lastNotified := time.Date(2026, 9, 19, 1, 0, 11, 0, time.UTC)
	cases := []struct {
		name string
		tier int
		now  time.Time
		want bool
	}{
		{"配信直後", 0, lastNotified.Add(time.Minute), false},
		{"同日の次の周回", 0, lastNotified.Add(time.Hour), false},
		{"slack の外（2時間前）", 0, lastNotified.Add(22 * time.Hour), false},
		{"slack の内（30分前）", 0, lastNotified.Add(23*time.Hour + 30*time.Minute), true},
		{"翌日", 0, lastNotified.Add(24 * time.Hour), true},
		{"tier1 は3日後まで待つ", 1, lastNotified.Add(48 * time.Hour), false},
		{"tier1 の3日後", 1, lastNotified.Add(72 * time.Hour), true},
		{"配信停止", TierStopped, lastNotified.Add(720 * time.Hour), false},
	}
	for _, c := range cases {
		data := map[string]any{
			"last_notified_at": lastNotified,
			"notify_tier":      int64(c.tier),
		}
		if got := IsDue(data, c.now); got != c.want {
			t.Errorf("%s: IsDue = %v, want %v", c.name, got, c.want)
		}
	}
}
