// Package premium は「実効プレミアム」の判定。
// functions/javascript/src/utils/premium.ts の移植。
//
// 課金中の premium と、新規ユーザーのプレミアム体験トライアル中を同じものとして
// 扱うための唯一の判定。トライアル中は完全に premium と同じ機能・同じ回数を出す
// 方針なので、tier だけを見る分岐を各所に書かない。
//
// トライアルは期間制（premium_trial_expires_at）。
package premium

import "time"

const (
	dayMS       = 24 * 60 * 60 * 1000
	jstOffsetMS = 9 * 60 * 60 * 1000
)

// CeilToJSTMidnight は与えた時刻以降で最初の JST 0:00 に切り上げる
// （ちょうど 0:00 ならそのまま）。単位はエポックミリ秒。
//
// トライアルの期限をクォータのリセット境界（dailyBatch, JST 0:00）に揃えるため。
// 揃えないと「期限は切れたが、その日のぶんの premium の回数はまだ残っている」
// 半端な時間帯ができ、体験終了の案内と実際に使える回数がずれる。
func CeilToJSTMidnight(ms int64) int64 {
	return ceilDiv(ms+jstOffsetMS, dayMS)*dayMS - jstOffsetMS
}

// ceilDiv は Math.ceil(a / b)（b > 0）。Go の整数除算は 0 方向へ切り捨てるので、
// 負数はそのままで切り上げになる。JS は浮動小数の Math.ceil なので符号で分ける。
func ceilDiv(a, b int64) int64 {
	if a >= 0 {
		return (a + b - 1) / b
	}
	return a / b
}

// TrialExpiresAtMsFrom は登録時刻から数えたトライアル期限（JST 0:00 に切り上げ済み）。
func TrialExpiresAtMsFrom(nowMS int64, days int) int64 {
	return CeilToJSTMidnight(nowMS + int64(days)*dayMS)
}

// TrialExpiresAtMs は users/{uid}.premium_trial_expires_at をミリ秒で返す。
// JS の `value?.toMillis?.()` 相当で、未設定や Timestamp 以外なら ok=false。
func TrialExpiresAtMs(userData map[string]any) (int64, bool) {
	t, ok := userData["premium_trial_expires_at"].(time.Time)
	if !ok {
		return 0, false
	}
	return t.UnixMilli(), true
}

// IsTrialActive はプレミアム体験トライアルが有効か。
func IsTrialActive(userData map[string]any, now time.Time) bool {
	expiresAt, ok := TrialExpiresAtMs(userData)
	return ok && now.UnixMilli() < expiresAt
}

// IsTrialExpired はトライアルを持っていて、既に期限が切れているか。
func IsTrialExpired(userData map[string]any, now time.Time) bool {
	expiresAt, ok := TrialExpiresAtMs(userData)
	return ok && now.UnixMilli() >= expiresAt
}

// IsEffectivePremium は課金 premium もしくはトライアル中か。
func IsEffectivePremium(userData map[string]any, now time.Time) bool {
	return userData["tier"] == "premium" || IsTrialActive(userData, now)
}
