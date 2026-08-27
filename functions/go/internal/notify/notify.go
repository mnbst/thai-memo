// Package notify は毎日例文の配信対象を時刻で絞り込むための非正規化フィールドを計算する。
// functions/javascript/src/utils/notifyUtcHour.ts の移植。
//
// deliverDailySentence は毎時起動し、ユーザーのローカル時刻が配信希望時刻と
// 一致する対象だけに配信する。この判定を Firestore クエリ側で行えるよう、
// 「現地の preferred_generation_hour が UTC の何時の起動に当たるか」を
// users/{uid}.notify_utc_hour に持たせる。
package notify

import (
	"sync"
	"time"

	// tzdata を実行ファイルに埋め込む。JS 版は Intl（ICU 同梱）で解決していたが、
	// Go は既定でシステムの zoneinfo を読むため、tzdata を持たないコンテナだと
	// LoadLocation が全部失敗して Asia/Tokyo にフォールバックし続ける。
	// 埋め込めば実行環境に依存しない。
	_ "time/tzdata"
)

const (
	// DefaultGenerationHour は配信希望時刻のデフォルト
	// （daily_sentence.py の DEFAULT_GENERATION_HOUR と一致）。
	DefaultGenerationHour = 10

	// DefaultTimezone はタイムゾーン未設定・不正時のフォールバック。
	DefaultTimezone = "Asia/Tokyo"
)

// locCache は tz ごとの *time.Location。不正な tz の nil も含めてキャッシュし、
// 毎回 zoneinfo を引き直さないようにする（JS 版の formatterCache と同じ意図）。
var (
	locMu    sync.Mutex
	locCache = map[string]*time.Location{}
	locKnown = map[string]bool{}
)

func location(timezone string) *time.Location {
	locMu.Lock()
	defer locMu.Unlock()
	if locKnown[timezone] {
		return locCache[timezone]
	}
	loc, err := time.LoadLocation(timezone)
	if err != nil {
		loc = nil
	}
	locCache[timezone] = loc
	locKnown[timezone] = true
	return loc
}

// UTCHour は現地の preferredHour が UTC の何時の起動に当たるかを求める。
//
// オフセットの引き算ではなく24通りを実際に現地時刻へ変換して探す。
// こうすることで +5:30 / +5:45 のような分単位オフセット（現地 10:30 に配信
// される、というズレはあるが対応は1対1）や DST でも正しい値になる。
//
// DST の春の切り替え日はその現地時刻自体が存在しないため ok=false を返す。
// 呼び出し側は既存値を維持する（その日は配信されない = 従来と同じ挙動）。
//
// timezone / preferredHour は Firestore の生の値をそのまま渡す。JS 版が
// `timezone || DEFAULT` と `typeof preferredHour === 'number'` で緩く受けて
// いたのに合わせ、型が違えば既定値を使う。
func UTCHour(timezone, preferredHour any, base time.Time) (int, bool) {
	tz, ok := timezone.(string)
	if !ok || tz == "" {
		tz = DefaultTimezone
	}

	hour := float64(DefaultGenerationHour)
	switch v := preferredHour.(type) {
	case int64:
		hour = float64(v)
	case float64:
		hour = v
	case int:
		hour = float64(v)
	}

	loc := location(tz)
	if loc == nil {
		loc = location(DefaultTimezone)
	}
	if loc == nil {
		return 0, false
	}

	base = base.UTC()
	day := time.Date(base.Year(), base.Month(), base.Day(), 0, 0, 0, 0, time.UTC)

	for utcHour := 0; utcHour < 24; utcHour++ {
		candidate := day.Add(time.Duration(utcHour) * time.Hour)
		if float64(candidate.In(loc).Hour()) == hour {
			return utcHour, true
		}
	}
	return 0, false
}
