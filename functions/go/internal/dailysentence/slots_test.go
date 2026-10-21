package dailysentence

import (
	"reflect"
	"testing"
	"time"
)

var jst = time.FixedZone("JST", 9*60*60)

func jstAt(day, hour, minute int) time.Time {
	return time.Date(2026, 10, day, hour, minute, 0, 0, jst)
}

// multiSlotUser は 10時・20時の2つを設定した配信対象（段階0）。
func multiSlotUser(overrides map[string]any) map[string]any {
	data := map[string]any{
		"last_sentence_generated_at": jstAt(1, 9, 0),
		"fcm_token":                  "token",
		"remaining_sentences":        int64(9999),
		"timezone":                   "Asia/Tokyo",
		"preferred_generation_hour":  int64(10),
		"notify_hours":               []any{int64(10), int64(20)},
	}
	for k, v := range overrides {
		data[k] = v
	}
	return data
}

func TestNotifyHours(t *testing.T) {
	cases := []struct {
		name string
		data map[string]any
		want []int
	}{
		{"未設定は preferred の1つ", map[string]any{"preferred_generation_hour": int64(8)}, []int{8}},
		{"どちらも無ければ既定", map[string]any{}, []int{DefaultGenerationHour}},
		{"昇順・重複なしにそろえる",
			map[string]any{"notify_hours": []any{int64(20), int64(7), int64(20)}}, []int{7, 20}},
		{"範囲外は捨てる",
			map[string]any{"notify_hours": []any{int64(25), int64(9)}}, []int{9}},
		{"上限を超えたぶんは捨てる",
			map[string]any{"notify_hours": []any{int64(1), int64(2), int64(3), int64(4)}}, []int{1, 2, 3}},
		{"壊れていれば preferred",
			map[string]any{"notify_hours": []any{"x"}, "preferred_generation_hour": int64(6)}, []int{6}},
	}
	for _, c := range cases {
		if got := NotifyHours(c.data); !reflect.DeepEqual(got, c.want) {
			t.Errorf("%s: got %v, want %v", c.name, got, c.want)
		}
	}
}

func TestDeliverySkipReasonMultiSlot(t *testing.T) {
	cases := []struct {
		name      string
		overrides map[string]any
		now       time.Time
		want      string
	}{
		{"朝の配信の印が立っていても夜は届く",
			map[string]any{"daily_sentence_generated": true, "last_notified_at": jstAt(2, 10, 0)},
			jstAt(2, 20, 0), ""},
		{"前日の夜に届いていても翌朝は届く",
			map[string]any{"last_notified_at": jstAt(1, 20, 0)},
			jstAt(2, 10, 0), ""},
		{"朝は従来どおり当日の生成済みで見送る",
			map[string]any{"daily_sentence_generated": true, "last_notified_at": jstAt(1, 20, 0)},
			jstAt(2, 10, 0), "already_generated"},
		{"同じ時刻の重複起動は送らない",
			map[string]any{"last_notified_at": jstAt(2, 20, 0)},
			jstAt(2, 20, 10), "not_due"},
		{"設定していない時刻",
			nil, jstAt(2, 15, 0), "hour_mismatch"},
		{"間隔を広げた人には2つ目以降を送らない",
			map[string]any{"notify_tier": int64(1), "last_notified_at": jstAt(1, 20, 0)},
			jstAt(4, 20, 0), "backoff_single_slot"},
		{"段階1は現地の日付で3日あける（2日後は見送る）",
			map[string]any{"notify_tier": int64(1), "last_notified_at": jstAt(1, 20, 0)},
			jstAt(3, 10, 0), "not_due"},
		{"段階1は現地の日付で3日あける（3日後の朝に届く）",
			map[string]any{"notify_tier": int64(1), "last_notified_at": jstAt(1, 20, 0)},
			jstAt(4, 10, 0), ""},
	}
	for _, c := range cases {
		got := DeliverySkipReason(multiSlotUser(c.overrides), c.now)
		if got != c.want {
			t.Errorf("%s: got %q, want %q", c.name, got, c.want)
		}
	}
}

func TestSlotIndex(t *testing.T) {
	data := multiSlotUser(nil)
	for _, c := range []struct {
		hour, want int
	}{{10, 0}, {20, 1}, {11, -1}} {
		if got := SlotIndex(data, jstAt(2, c.hour, 0)); got != c.want {
			t.Errorf("%d時: got %d, want %d", c.hour, got, c.want)
		}
	}
}

func TestNotifyHoursRefresh(t *testing.T) {
	now := jstAt(2, 0, 0)
	cases := []struct {
		name    string
		data    map[string]any
		premium bool
		want    map[string]any
	}{
		{"notify_hours が無ければ触らない",
			map[string]any{"preferred_generation_hour": int64(10)}, true, nil},
		{"premium は全部の UTC を作り直す",
			multiSlotUser(nil), true,
			map[string]any{"notify_hours": []int{10, 20}, "notify_utc_hours": []int{1, 11}}},
		{"premium でなくなったら先頭の1つに戻す",
			multiSlotUser(nil), false,
			map[string]any{"notify_hours": []int{10}, "notify_utc_hours": []int{1}}},
		{"旧クライアントが preferred を変えたら消す",
			multiSlotUser(map[string]any{"preferred_generation_hour": int64(8)}), true,
			map[string]any{"notify_hours": nil, "notify_utc_hours": nil}},
	}
	for _, c := range cases {
		got := NotifyHoursRefresh(c.data, c.premium, now)
		if !reflect.DeepEqual(got, c.want) {
			t.Errorf("%s: got %v, want %v", c.name, got, c.want)
		}
	}
}

func TestEvaluateResponseOpenResetsTier(t *testing.T) {
	data := map[string]any{
		"notify_tier":        int64(3),
		"notify_tier_misses": int64(2),
		"last_notified_at":   jstAt(1, 10, 0),
		"last_opened_at":     jstAt(1, 12, 0),
	}
	if got := EvaluateResponse(data); got != (TierUpdate{0, 0}) {
		t.Errorf("開いたのに段階0に戻らない: %+v", got)
	}
}

// 無反応は先頭の時刻の配信でだけ数える（1日1回）。
func TestEvaluateResponseAtCountsOncePerDay(t *testing.T) {
	data := multiSlotUser(map[string]any{
		"notify_tier_misses": int64(2),
		"last_notified_at":   jstAt(2, 10, 0),
		"last_opened_at":     jstAt(1, 12, 0),
	})
	if got := EvaluateResponseAt(data, jstAt(2, 20, 0)); got != (TierUpdate{0, 2}) {
		t.Errorf("2つ目の時刻で数えている: %+v", got)
	}
	if got := EvaluateResponseAt(data, jstAt(3, 10, 0)); got != (TierUpdate{1, 0}) {
		t.Errorf("先頭の時刻で数えていない: %+v", got)
	}
}
