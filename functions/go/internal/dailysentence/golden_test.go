package dailysentence

import (
	"encoding/json"
	"os"
	"sort"
	"testing"
	"time"
)

type dailyGolden struct {
	TzCases []struct {
		Timezone  *string `json:"timezone"`
		Now       int64   `json:"now"`
		LocalHour int     `json:"local_hour"`
		LocalDate string  `json:"local_date"`
	} `json:"tz_cases"`
	Cases []struct {
		Now             int64          `json:"now"`
		Data            map[string]any `json:"data"`
		TimestampFields []string       `json:"timestamp_fields"`
		HasHistory      bool           `json:"has_generation_history"`
		IsDue           bool           `json:"is_due"`
		Evaluate        struct {
			NotifyTier   int `json:"notify_tier"`
			NotifyMisses int `json:"notify_tier_misses"`
		} `json:"evaluate_response"`
		UsesPremiumTrial bool    `json:"uses_premium_trial"`
		SkipReason       *string `json:"delivery_skip_reason"`
	} `json:"cases"`
}

func loadDailyGolden(t *testing.T) *dailyGolden {
	t.Helper()
	raw, err := os.ReadFile("../../testdata/python/daily_golden/golden.json")
	if err != nil {
		t.Fatalf("golden の読み込みに失敗: %v", err)
	}
	var golden dailyGolden
	if err := json.Unmarshal(raw, &golden); err != nil {
		t.Fatal(err)
	}
	return &golden
}

// TestLocalTimeGolden は現地時刻の変換を Python 実装と突き合わせる。
//
// Python は zoneinfo、Go は tzdata と実装系が違うので、DST 切り替え日や
// 分単位オフセットのタイムゾーンを含めて比べる。
func TestLocalTimeGolden(t *testing.T) {
	golden := loadDailyGolden(t)
	if len(golden.TzCases) == 0 {
		t.Fatal("golden が空")
	}

	for _, c := range golden.TzCases {
		now := time.UnixMilli(c.Now).UTC()
		var tz any
		if c.Timezone != nil {
			tz = *c.Timezone
		}

		if got := LocalHour(tz, now); got != c.LocalHour {
			t.Errorf("LocalHour(%v, %s): Python=%d Go=%d",
				tz, now.Format(time.RFC3339), c.LocalHour, got)
		}
		if got := LocalDate(tz, now); got != c.LocalDate {
			t.Errorf("LocalDate(%v, %s): Python=%s Go=%s",
				tz, now.Format(time.RFC3339), c.LocalDate, got)
		}
	}
	t.Logf("%d ケース一致", len(golden.TzCases))
}

// TestDeliveryDecisionGolden は配信判定を Python 実装と突き合わせる。
//
// golden は本物の daily_sentence.py を実行して作っている
// （scripts/daily_golden/gen_golden.py）。見送り理由の文字列まで比べるので、
// 判定順序が入れ替わっただけでも落ちる。
func TestDeliveryDecisionGolden(t *testing.T) {
	golden := loadDailyGolden(t)
	if len(golden.Cases) == 0 {
		t.Fatal("golden が空")
	}

	reasonCount := map[string]int{}

	for i, c := range golden.Cases {
		now := time.UnixMilli(c.Now).UTC()

		// timestamp として書き出したフィールドを time.Time に戻す
		data := map[string]any{}
		isTimestamp := map[string]bool{}
		for _, f := range c.TimestampFields {
			isTimestamp[f] = true
		}
		for k, v := range c.Data {
			if isTimestamp[k] {
				ms, ok := v.(float64)
				if !ok {
					t.Fatalf("case %d: %s が数値でない", i, k)
				}
				data[k] = time.UnixMilli(int64(ms)).UTC()
				continue
			}
			// JSON の数値は float64 で来る。Firestore は整数を int64 で返すので揃える。
			if n, ok := v.(float64); ok && n == float64(int64(n)) {
				data[k] = int64(n)
				continue
			}
			data[k] = v
		}

		if got := HasGenerationHistory(data); got != c.HasHistory {
			t.Errorf("case %d: HasGenerationHistory Python=%v Go=%v\n  %v",
				i, c.HasHistory, got, c.Data)
		}
		if got := IsDue(data, now); got != c.IsDue {
			t.Errorf("case %d: IsDue Python=%v Go=%v\n  %v", i, c.IsDue, got, c.Data)
		}
		if got := EvaluateResponse(data); got.NotifyTier != c.Evaluate.NotifyTier ||
			got.NotifyMisses != c.Evaluate.NotifyMisses {
			t.Errorf("case %d: EvaluateResponse Python=(%d,%d) Go=(%d,%d)\n  %v",
				i, c.Evaluate.NotifyTier, c.Evaluate.NotifyMisses,
				got.NotifyTier, got.NotifyMisses, c.Data)
		}
		if got := UsesPremiumTrial(data, now); got != c.UsesPremiumTrial {
			t.Errorf("case %d: UsesPremiumTrial Python=%v Go=%v\n  %v",
				i, c.UsesPremiumTrial, got, c.Data)
		}

		wantReason := ""
		if c.SkipReason != nil {
			wantReason = *c.SkipReason
		}
		reasonCount[wantReason]++
		if got := DeliverySkipReason(data, now); got != wantReason {
			t.Errorf("case %d: DeliverySkipReason Python=%q Go=%q\n  %v",
				i, wantReason, got, c.Data)
		}
	}

	keys := make([]string, 0, len(reasonCount))
	for k := range reasonCount {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	for _, k := range keys {
		label := k
		if label == "" {
			label = "(配信する)"
		}
		t.Logf("  %-20s %d", label, reasonCount[k])
	}
	t.Logf("%d ケース一致", len(golden.Cases))

	// 全ての見送り理由と「配信する」が踏まれていること
	for _, want := range []string{
		"", "no_history", "opt_out", "no_token", "already_generated",
		"quota_exhausted", "backoff_stopped", "hour_mismatch", "not_due",
	} {
		if reasonCount[want] == 0 {
			label := want
			if label == "" {
				label = "(配信する)"
			}
			t.Errorf("%s のケースが無い。golden が退化している", label)
		}
	}
}
