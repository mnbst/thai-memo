// Package dailysentence は毎日例文の配信判定（純粋ロジック）。
// functions/python/daily_sentence.py の移植。
//
// Cloud Functions のエントリポイントは別（daily_sentence.go）。
// テスト容易性のため、判定ロジックはここに副作用なしで置く。
package dailysentence

import (
	"strconv"
	"strings"
	"time"

	"github.com/mnbst/thai-memo/functions/go/internal/notify"
	"github.com/mnbst/thai-memo/functions/go/internal/sentence"
)

// TierIntervalDays は段階ごとの配信間隔（日）。
// notify_tier == len(TierIntervalDays) で配信停止。
var TierIntervalDays = []int{1, 3, 10, 30}

// TierStopped は配信停止に達した段階。
var TierStopped = len(TierIntervalDays)

const (
	// TierMaxMisses は同じ段階で無反応がこの回数たまると次の段階へ落とす。
	TierMaxMisses = 3

	// DefaultTimezone はタイムゾーン未設定・不正時のフォールバック。
	DefaultTimezone = "Asia/Tokyo"

	// DefaultGenerationHour は配信希望時刻のデフォルト。
	DefaultGenerationHour = 10

	// MaxTargetWordRetry はキャッシュヒットするまでターゲット語を引き直す回数。
	MaxTargetWordRetry = 5
)

// local は不正・未設定の tz 名を Asia/Tokyo にフォールバックしてローカル時刻へ変換する。
func local(tzName any, now time.Time) time.Time {
	name, ok := tzName.(string)
	if !ok || name == "" {
		name = DefaultTimezone
	}
	loc, err := time.LoadLocation(name)
	if err != nil {
		loc, err = time.LoadLocation(DefaultTimezone)
		if err != nil {
			return now.UTC()
		}
	}
	return now.In(loc)
}

// LocalHour は現地時刻の「時」。
func LocalHour(tzName any, now time.Time) int {
	return local(tzName, now).Hour()
}

// LocalDate は現地時刻の日付を "YYYY-MM-DD" で返す。
func LocalDate(tzName any, now time.Time) string {
	return local(tzName, now).Format("2006-01-02")
}

// NotifyUTCHour は現地の配信希望時刻が UTC の何時の起動に当たるかを求める。
//
// JS 版（utils/notifyUtcHour.ts）と同じ計算で、実装は internal/notify に集約している。
// Python 側とも同じ結果になることは internal/notify の差分テストで確認済み。
func NotifyUTCHour(userData map[string]any, now time.Time) (int, bool) {
	return notify.UTCHour(
		userData["timezone"], userData["preferred_generation_hour"], now)
}

// asDatetime は Firestore の timestamp を time.Time に正規化する。
func asDatetime(value any) (time.Time, bool) {
	t, ok := value.(time.Time)
	return t, ok
}

// numField は Firestore の数値を int にする。整数は int64 で返るため。
func numField(value any, fallback int) int {
	switch n := value.(type) {
	case int64:
		return int(n)
	case float64:
		return int(n)
	case int:
		return n
	}
	return fallback
}

// HasGenerationHistory は一度でも例文を生成したことがあるか。
//
// last_sentence_generated_at が導入される前に生成したきりのユーザーを
// estimated_vocab で救う。
func HasGenerationHistory(userData map[string]any) bool {
	if userData["last_sentence_generated_at"] != nil {
		return true
	}
	return numField(userData["estimated_vocab"], 0) > 0
}

// IsDue は段階ごとの配信間隔を満たしているか。初回（未通知）は常に true。
func IsDue(userData map[string]any, now time.Time) bool {
	tier := numField(userData["notify_tier"], 0)
	if tier >= TierStopped {
		return false
	}
	lastNotified, ok := asDatetime(userData["last_notified_at"])
	if !ok {
		return true
	}
	due := lastNotified.AddDate(0, 0, TierIntervalDays[tier])
	return !now.Before(due)
}

// TierUpdate は反応評価の結果（Firestore へ書く内容）。
type TierUpdate struct {
	NotifyTier   int
	NotifyMisses int
}

// EvaluateResponse は前回通知への反応を評価し、更新後の段階を返す。
//
// 「次へ」押下（last_sentence_generated_at）を主シグナル、開封（last_opened_at）を
// 副シグナルとする。どちらも動いていない場合だけ段階が進む。
//
// 開封は段階（notify_tier）までは戻さないが、無反応の連続カウントは0に戻す。
// 届いた通知に反応している以上、間隔を広げる方向へ進めるべきではないため。
func EvaluateResponse(userData map[string]any) TierUpdate {
	tier := numField(userData["notify_tier"], 0)
	misses := numField(userData["notify_tier_misses"], 0)

	lastNotified, ok := asDatetime(userData["last_notified_at"])
	if !ok {
		return TierUpdate{NotifyTier: tier, NotifyMisses: misses}
	}

	if generatedAt, ok := asDatetime(userData["last_sentence_generated_at"]); ok &&
		generatedAt.After(lastNotified) {
		return TierUpdate{NotifyTier: 0, NotifyMisses: 0}
	}

	if openedAt, ok := asDatetime(userData["last_opened_at"]); ok &&
		openedAt.After(lastNotified) {
		return TierUpdate{NotifyTier: tier, NotifyMisses: 0}
	}

	misses++
	if misses >= TierMaxMisses {
		tier++
		misses = 0
	}
	return TierUpdate{NotifyTier: tier, NotifyMisses: misses}
}

// UsesPremiumTrial はこの配信をプレミアム体験トライアル枠（premium品質）で出すか。
//
// トライアルは期間制なので、期間中の free ユーザーは配信も premium 品質にする。
// 判定は generateThaiSentence 側と同じ期限のみで、消費という概念は無い。
func UsesPremiumTrial(userData map[string]any, now time.Time) bool {
	if userData["tier"] == "premium" {
		return false
	}
	expiresAt, ok := asDatetime(userData["premium_trial_expires_at"])
	if !ok {
		return false
	}
	return now.Before(expiresAt)
}

// DeliverySkipReason は配信を見送る理由。配信対象なら空文字。
//
// 理由を文字列で返すのは、配信バッチのログに内訳を残すため。
// 「通知が届いていない」を調べるたびに Firestore を読んで条件を手で再現するのは
// 非効率なので、判断に使う値は常設ログにしておく。
func DeliverySkipReason(userData map[string]any, now time.Time) string {
	if !HasGenerationHistory(userData) {
		return "no_history"
	}
	// Python の `is False`。未設定は対象外にしない。
	if enabled, ok := userData["daily_reminder_enabled"].(bool); ok && !enabled {
		return "opt_out"
	}
	if token, _ := userData["fcm_token"].(string); token == "" {
		return "no_token"
	}
	if generated, ok := userData["daily_sentence_generated"].(bool); ok && generated {
		return "already_generated"
	}
	if numField(userData["remaining_sentences"], 0) <= 0 {
		return "quota_exhausted"
	}
	if numField(userData["notify_tier"], 0) >= TierStopped {
		return "backoff_stopped"
	}

	hour := LocalHour(userData["timezone"], now)
	if hour != numField(userData["preferred_generation_hour"], DefaultGenerationHour) {
		// notify_utc_hour で絞ってから呼ぶので、これが出るのは非正規化値が古いとき。
		return "hour_mismatch"
	}

	if !IsDue(userData, now) {
		return "not_due"
	}
	return ""
}

// ShouldDeliver は配信対象かどうか。
func ShouldDeliver(userData map[string]any, now time.Time) bool {
	return DeliverySkipReason(userData, now) == ""
}

// DailyBatchSize は1回の配信で作る例文の本数。
//
// 例文→確認クイズ→まとめクイズのサイクルを1日で1周させるため、
// アプリからの生成（generateThaiSentence）と同じ「1セット」の本数を使う。
const DailyBatchSize = sentence.SetSize

// DailyBatchMinVersion は5本セットを扱えるクライアントの最小バージョン。
//
// 旧版は配信済みドキュメントを全部取り込んだうえで最新の1件しか表示しないため、
// 5本送るとクォータだけ消費して4本が履歴に埋もれる。必ず版で絞る。
// ロールアウトはこの値の上げ下げで切り替える。
var DailyBatchMinVersion = [3]int{1, 4, 8}

// BatchSize は配信本数。版が読めない・古い場合は従来どおり1本（安全側）。
//
// app_build_number は使えない。pubspec のビルド番号は 0 固定で、実際の番号は
// CI が --build-number=${{ github.run_number }} で注入しており、tester と prod で
// ワークフローが別＝採番系列が独立しているため大小がリリース順序を表さない。
func BatchSize(userData map[string]any) int {
	version, _ := userData["app_version"].(string)
	if compareVersion(version, DailyBatchMinVersion) < 0 {
		return 1
	}
	return DailyBatchSize
}

// compareVersion は "1.4.8" 形式を major/minor/patch の順に比較する。
// パースできない値は最小扱い（-1）にして安全側へ倒す。
func compareVersion(version string, other [3]int) int {
	parts := strings.SplitN(strings.TrimSpace(version), ".", 4)
	if len(parts) != 3 {
		return -1
	}
	for i, p := range parts {
		n, err := strconv.Atoi(p)
		if err != nil || n < 0 {
			return -1
		}
		if n != other[i] {
			if n < other[i] {
				return -1
			}
			return 1
		}
	}
	return 0
}
