// Package premium は「実効プレミアム」の判定。
// functions/javascript/src/utils/premium.ts の移植。
//
// 課金中の premium と、新規ユーザーのプレミアム体験トライアル中を同じものとして
// 扱うための唯一の判定。トライアル中は完全に premium と同じ機能・同じ回数を出す
// 方針なので、tier だけを見る分岐を各所に書かない。
//
// トライアルは期間制（premium_trial_expires_at）。
package premium

import (
	"time"

	"github.com/mnbst/thai-memo/functions/go/internal/subscription"
)

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

// IsEffectivePremium は premium の機能を出してよいユーザーか。
//
// 例文生成・毎日配信・クイズ・語彙テストは全てこの1本で判定する。経路ごとに
// tier やトライアル期限を直接見ると「回数は premium 扱いなのに中身は free 品質」
// のような食い違いが出るため、実効権利の解釈はここだけに置く。
//
// 含むもの: tier=premium / 体験トライアル中 / 猶予期間（支払い回復待ち）/
// 反映待ちのストア購入。購入・復元直後は subscription の検証結果より tier の
// 反映が遅れることがあるので、有効期限内のストア購入と買い切りも実効権利として
// 扱う。期限切れ情報だけで premium を延命はしない。
func IsEffectivePremium(userData map[string]any, now time.Time) bool {
	if userData["tier"] == "premium" || IsTrialActive(userData, now) {
		return true
	}
	sub, _ := userData["subscription"].(map[string]any)
	status, _ := sub["status"].(string)
	// REFUND / REVOKE は tier=free, status=expired にする一方、過去の
	// lifetime 印や将来の expires_at が doc に残ることがある。状態を先に
	// 確認しないと、取り消した権利をここで再び premium にしてしまう。
	if status == "expired" || status == "revoked" || status == "refunded" {
		return false
	}
	if subscription.IsLifetime(sub) && status == "active" {
		return true
	}
	if status != "active" && status != "canceled" && status != "grace_period" {
		return false
	}
	expiresAt, ok := sub["expires_at"].(time.Time)
	if !ok {
		return false
	}
	if now.Before(expiresAt) {
		return true
	}
	return status == "grace_period" && now.Sub(expiresAt) <= subscription.GracePeriodMax
}
