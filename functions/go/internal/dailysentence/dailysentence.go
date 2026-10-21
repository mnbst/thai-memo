// Package dailysentence は毎日例文の配信判定（純粋ロジック）。
// functions/python/daily_sentence.py の移植。
//
// Cloud Functions のエントリポイントは別（daily_sentence.go）。
// テスト容易性のため、判定ロジックはここに副作用なしで置く。
package dailysentence

import (
	"sort"
	"time"

	"github.com/mnbst/thai-memo/functions/go/internal/appver"
	"github.com/mnbst/thai-memo/functions/go/internal/notify"
	"github.com/mnbst/thai-memo/functions/go/internal/sentence"
)

// TierIntervalDays は段階ごとの配信間隔（日）。
// notify_tier == len(TierIntervalDays) で配信停止。
//
// 反応が無いまま進むと、毎日×3回 → 3日ごと×3回 → 10日ごと×3回 →
// 30日ごと×3回 → 停止。アプリを開けば段階0（毎日）に戻る
// （クライアントが開いた時点で戻し、サーバーも次の配信の評価で戻す）。
var TierIntervalDays = []int{1, 3, 10, 30}

// TierStopped は配信停止に達した段階。
var TierStopped = len(TierIntervalDays)

const (
	// TierMaxMisses は同じ段階で無反応がこの回数たまると次の段階へ落とす。
	// 複数時刻の人も数えるのは先頭の時刻の配信だけ（1日1回）。
	TierMaxMisses = 3

	// DefaultTimezone はタイムゾーン未設定・不正時のフォールバック。
	DefaultTimezone = "Asia/Tokyo"

	// DefaultGenerationHour は配信希望時刻のデフォルト。
	DefaultGenerationHour = 10

	// MaxTargetWordRetry はキャッシュヒットするまでターゲット語を引き直す回数。
	MaxTargetWordRetry = 5

	// DueSlack は配信期日の前倒し幅（IsDue）。
	//
	// 毎時起動の開始時刻と、その回で対象ユーザーに辿り着くまでの時間は日ごとに
	// 揺れる。この揺れを吸収しないと、前日より数秒早い起動が not_due になって
	// 1日飛ぶ。対象時刻の起動は日に1回なので、揺れより十分大きく、かつ最短
	// 間隔（1日）より十分小さい値にする。
	DueSlack = time.Hour

	// MaxNotifyHours は1日に設定できる配信時刻の数（premium）。free は1つ。
	MaxNotifyHours = 3

	// SlotMinGap は複数時刻の配信で、前回の配信から最低限あける間隔。
	//
	// 時刻は1時間単位で重複しないので、別の時刻どうしは1時間以上離れる。
	// 同じ時刻の起動が重複して走ったときに二重に送らないための下限。
	SlotMinGap = 30 * time.Minute
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

// NotifyHours は配信時刻（現地の時）を早い順に返す。
//
// notify_hours は複数時刻に対応したクライアント（premium は最大3つ）が書く。
// 無い・壊れているときは従来どおり preferred_generation_hour の1つだけ。
// 先頭（いちばん早い時刻）が preferred_generation_hour と同じ値になるよう
// クライアントと dailyBatch がそろえる。
func NotifyHours(userData map[string]any) []int {
	if hours, ok := parseNotifyHours(userData["notify_hours"]); ok {
		return hours
	}
	return []int{numField(userData["preferred_generation_hour"], DefaultGenerationHour)}
}

// parseNotifyHours は notify_hours を0〜23の重複なし昇順にする。
// 1つも読めなければ ok=false。
func parseNotifyHours(value any) ([]int, bool) {
	raw, ok := value.([]any)
	if !ok {
		return nil, false
	}
	seen := map[int]bool{}
	hours := make([]int, 0, len(raw))
	for _, v := range raw {
		h := numField(v, -1)
		if h < 0 || h > 23 || seen[h] {
			continue
		}
		seen[h] = true
		hours = append(hours, h)
	}
	if len(hours) == 0 {
		return nil, false
	}
	sort.Ints(hours)
	if len(hours) > MaxNotifyHours {
		hours = hours[:MaxNotifyHours]
	}
	return hours, true
}

// SlotIndex は今の現地時刻が配信時刻の何番目か（0始まり）。該当しなければ -1。
//
// 0番目（いちばん早い時刻）だけが従来の1日1回の配信で、free はここだけ届く。
func SlotIndex(userData map[string]any, now time.Time) int {
	hour := LocalHour(userData["timezone"], now)
	for i, h := range NotifyHours(userData) {
		if h == hour {
			return i
		}
	}
	return -1
}

// NotifyHoursRefresh は dailyBatch が毎日書き直す配信時刻まわりの値。
//
// - 旧クライアントが preferred_generation_hour だけを変えた（先頭と食い違う）
//   ときは notify_hours を捨てて1つに戻す。そのままだと変えた時刻に届かない。
// - premium でなくなった人は先頭の1つに戻す（プランが変わったら時刻はリセット）。
// - notify_utc_hours を現地時刻から作り直す（端末の移動・DST に追従）。
//   算出できない時刻（DST春の飛び時刻）はその日だけ外す。
//
// notify_hours を持たない人には何も返さない（notify_utc_hour は呼び出し側）。
func NotifyHoursRefresh(
	userData map[string]any, effectivePremium bool, now time.Time,
) map[string]any {
	if _, present := userData["notify_hours"]; !present {
		return nil
	}
	hours, ok := parseNotifyHours(userData["notify_hours"])
	preferred := numField(userData["preferred_generation_hour"], DefaultGenerationHour)
	if !ok || hours[0] != preferred {
		return map[string]any{"notify_hours": nil, "notify_utc_hours": nil}
	}
	if !effectivePremium {
		hours = hours[:1]
	}
	utcHours := make([]int, 0, len(hours))
	for _, h := range hours {
		if u, ok := notify.UTCHour(userData["timezone"], h, now); ok {
			utcHours = append(utcHours, u)
		}
	}
	return map[string]any{"notify_hours": hours, "notify_utc_hours": utcHours}
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
//
// 期日は DueSlack ぶん早める。前回の配信時刻ちょうどを期日にすると、起動が
// 数秒でも早い日に丸1日ぶん見送ってしまう（2026-09-20、01:00:11 に配信した
// 翌日の起動が 01:00:03 で not_due。対象時刻の起動は日に1回なので、その
// ユーザーはその日の配信を丸ごと失う）。
func IsDue(userData map[string]any, now time.Time) bool {
	tier := numField(userData["notify_tier"], 0)
	if tier >= TierStopped {
		return false
	}
	lastNotified, ok := asDatetime(userData["last_notified_at"])
	if !ok {
		return true
	}
	if len(NotifyHours(userData)) > 1 {
		return isDueMulti(userData, tier, lastNotified, now)
	}
	due := lastNotified.AddDate(0, 0, TierIntervalDays[tier]).Add(-DueSlack)
	return !now.Before(due)
}

// isDueMulti は複数時刻を設定した人の期日判定。
//
// 前回の配信は前日の遅い時刻であることが多く、「前回から1日」で測ると翌日の
// 早い時刻が丸ごと not_due になる。そこで段階0は前回から SlotMinGap あいて
// いれば届け、段階1以降（呼び出し側で先頭の時刻に限る）は現地の日付で
// 間隔日数を数える。
func isDueMulti(
	userData map[string]any, tier int, lastNotified, now time.Time,
) bool {
	if tier == 0 {
		return now.Sub(lastNotified) >= SlotMinGap
	}
	lastDay := local(userData["timezone"], lastNotified)
	today := local(userData["timezone"], now)
	from := time.Date(lastDay.Year(), lastDay.Month(), lastDay.Day(), 0, 0, 0, 0, time.UTC)
	to := time.Date(today.Year(), today.Month(), today.Day(), 0, 0, 0, 0, time.UTC)
	return int(to.Sub(from).Hours()/24) >= TierIntervalDays[tier]
}

// TierUpdate は反応評価の結果（Firestore へ書く内容）。
type TierUpdate struct {
	NotifyTier   int
	NotifyMisses int
}

// EvaluateResponse は前回通知への反応を評価し、更新後の段階を返す。
//
// 前回の通知のあとに例文を進めた（last_sentence_generated_at）か、アプリを
// 開いた（last_opened_at）なら段階0に戻す。どちらも動いていない場合だけ
// 無反応を1つ数え、TierMaxMisses たまると次の段階へ進める。
//
// 新しいクライアントは開いた時点で自分で段階0に戻すので、ここで戻すのは
// その書き込みに失敗したときと旧版の端末のため。
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
		return TierUpdate{NotifyTier: 0, NotifyMisses: 0}
	}

	misses++
	if misses >= TierMaxMisses {
		tier++
		misses = 0
	}
	return TierUpdate{NotifyTier: tier, NotifyMisses: misses}
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
	slot := SlotIndex(userData, now)
	// 2つ目以降の時刻は、その日の1回目の配信で立った印を見ない。
	if generated, ok := userData["daily_sentence_generated"].(bool); ok && generated && slot <= 0 {
		return "already_generated"
	}
	if numField(userData["remaining_sentences"], 0) <= 0 {
		return "quota_exhausted"
	}
	if numField(userData["notify_tier"], 0) >= TierStopped {
		return "backoff_stopped"
	}

	if slot < 0 {
		// notify_utc_hour(s) で絞ってから呼ぶので、これが出るのは非正規化値が古いとき。
		return "hour_mismatch"
	}
	// 反応が途絶えて間隔を広げた人には、先頭の時刻だけ届ける。
	if slot > 0 && numField(userData["notify_tier"], 0) > 0 {
		return "backoff_single_slot"
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
// それ以外はアプリからの生成と同じセット本数（入門者は2〜4本）。
func BatchSize(userData map[string]any) int {
	if !appver.AtLeast(userData, DailyBatchMinVersion) {
		return 1
	}
	return sentence.SetSizeFor(userData)
}

// EvaluateResponseAt は配信するときの反応評価。
//
// 無反応は1日1回、先頭の時刻の配信でだけ数える。2つ目以降の時刻で数えると、
// 3つの時刻を設定した人は1日で次の段階へ進んでしまい、「毎日×3回」と合わない。
func EvaluateResponseAt(userData map[string]any, now time.Time) TierUpdate {
	if SlotIndex(userData, now) > 0 {
		return TierUpdate{
			NotifyTier:   numField(userData["notify_tier"], 0),
			NotifyMisses: numField(userData["notify_tier_misses"], 0),
		}
	}
	return EvaluateResponse(userData)
}
