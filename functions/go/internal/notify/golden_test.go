package notify

import (
	"encoding/json"
	"os"
	"testing"
	"time"
)

// goldenCase は functions/javascript/scripts/genNotifyGolden.ts が書き出す形。
type goldenCase struct {
	Timezone      *string `json:"timezone"`
	PreferredHour *int    `json:"preferred_hour"`
	Base          string  `json:"base"`
	Expected      *int    `json:"expected"`
}

// TestUTCHourGolden は JS 実装（utils/notifyUtcHour.ts）が出した期待値と突き合わせる。
// タイムゾーンの扱いは Intl(ICU) と Go の tzdata で実装が全く違うので、
// 分単位オフセットや DST 切り替え日を含む全ケースで一致することを確かめる。
func TestUTCHourGolden(t *testing.T) {
	raw, err := os.ReadFile("../../testdata/javascript/notify_golden.json")
	if err != nil {
		t.Fatalf("golden の読み込みに失敗: %v", err)
	}
	var cases []goldenCase
	if err := json.Unmarshal(raw, &cases); err != nil {
		t.Fatal(err)
	}
	if len(cases) == 0 {
		t.Fatal("golden が空")
	}

	var nullCount int
	for _, c := range cases {
		base, err := time.Parse(time.RFC3339, c.Base)
		if err != nil {
			t.Fatal(err)
		}

		var tz any
		if c.Timezone != nil {
			tz = *c.Timezone
		}
		var hour any
		if c.PreferredHour != nil {
			hour = int64(*c.PreferredHour)
		}

		got, ok := UTCHour(tz, hour, base)
		if c.Expected == nil {
			nullCount++
			if ok {
				t.Errorf("tz=%v hour=%v base=%s: JS は null なのに Go は %d",
					tz, hour, c.Base, got)
			}
			continue
		}
		if !ok {
			t.Errorf("tz=%v hour=%v base=%s: JS は %d なのに Go は null",
				tz, hour, c.Base, *c.Expected)
			continue
		}
		if got != *c.Expected {
			t.Errorf("tz=%v hour=%v base=%s: JS=%d Go=%d",
				tz, hour, c.Base, *c.Expected, got)
		}
	}

	t.Logf("%d ケース一致（うち null %d 件）", len(cases), nullCount)
	if nullCount == 0 {
		t.Error("DST の穴が1件も無い。golden の基準日が退化している")
	}
}
