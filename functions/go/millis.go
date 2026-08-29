package function

import "time"

// millisToTime はエポックミリ秒を time.Time にする（JS の new Date(ms) 相当）。
func millisToTime(ms int64) time.Time {
	return time.UnixMilli(ms).UTC()
}
