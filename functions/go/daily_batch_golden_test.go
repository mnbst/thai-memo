package function

import (
	"encoding/json"
	"os"
	"reflect"
	"sort"
	"testing"
	"time"

	"cloud.google.com/go/firestore"
)

// quotaGoldenNow は genQuotaGolden.ts の NOW_MS と一致させること。
const quotaGoldenNow = "2026-08-27T15:30:00Z"

type quotaGoldenCase struct {
	UID      string         `json:"uid"`
	Data     map[string]any `json:"data"`
	Expected map[string]any `json:"expected"`
}

// TestQuotaResetPayloadGolden は JS 実装（dailyBatch.ts:resetQuota）が
// Firestore へ書こうとした内容と、Go 版 quotaResetPayload の結果を突き合わせる。
//
// golden は本物の src/dailyBatch.ts を firebase-admin スタブ付きで実行して
// 生成している（scripts/genQuotaGolden.ts）ので、移植漏れがあれば必ず落ちる。
func TestQuotaResetPayloadGolden(t *testing.T) {
	raw, err := os.ReadFile("../javascript/scripts/quota_golden.json")
	if err != nil {
		t.Fatalf("golden の読み込みに失敗: %v", err)
	}
	var cases []quotaGoldenCase
	if err := json.Unmarshal(raw, &cases); err != nil {
		t.Fatal(err)
	}
	if len(cases) == 0 {
		t.Fatal("golden が空")
	}

	now, err := time.Parse(time.RFC3339, quotaGoldenNow)
	if err != nil {
		t.Fatal(err)
	}

	// 分岐がどれだけ踏まれたかを数える。golden が退化したら気付けるように。
	seen := map[string]int{}

	for _, c := range cases {
		data, _ := decodeGolden(c.Data).(map[string]any)
		want, _ := decodeGolden(c.Expected).(map[string]any)
		got := normalizeGoPayload(quotaResetPayload(c.UID, data, now))

		for k := range want {
			seen[k]++
		}

		if !reflect.DeepEqual(got, want) {
			t.Errorf("%s: 入力 %v\n  JS = %v\n  Go = %v", c.UID, c.Data, want, got)
		}
	}

	keys := make([]string, 0, len(seen))
	for k := range seen {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	for _, k := range keys {
		t.Logf("  %-26s %4d 件", k, seen[k])
		if seen[k] == 0 {
			t.Errorf("%s の分岐が1件も踏まれていない", k)
		}
	}
	t.Logf("%d ケース一致", len(cases))
}

// TestQuotaResetPayloadOmitsUtcHourOnDstGap は DST 春の飛び時刻で
// notify_utc_hour を書かない（既存値を維持する）ことを確かめる。
//
// golden の基準日が夏なのでこの分岐だけは踏まれない。単体で押さえる。
func TestQuotaResetPayloadOmitsUtcHourOnDstGap(t *testing.T) {
	now := time.Date(2026, 3, 8, 0, 0, 0, 0, time.UTC)
	data := map[string]any{
		"timezone":                  "America/Los_Angeles",
		"preferred_generation_hour": int64(2), // この日 2:00 は存在しない
	}

	payload := quotaResetPayload("dst", data, now)
	if _, ok := payload["notify_utc_hour"]; ok {
		t.Errorf("存在しない現地時刻なのに notify_utc_hour を書いている: %v",
			payload["notify_utc_hour"])
	}

	// 隣の時刻なら書かれることも確認（無条件に省いているわけではない）
	data["preferred_generation_hour"] = int64(3)
	if _, ok := quotaResetPayload("dst", data, now)["notify_utc_hour"]; !ok {
		t.Error("3:00 は存在するのに notify_utc_hour が書かれていない")
	}
}

// decodeGolden はタグ付き JSON（$timestamp_ms / $server_timestamp）を
// Firestore から返ってくるのと同じ形へ戻す。
func decodeGolden(v any) any {
	m, ok := v.(map[string]any)
	if !ok {
		return v
	}
	if ms, ok := m["$timestamp_ms"].(float64); ok {
		return time.UnixMilli(int64(ms)).UTC()
	}
	if b, ok := m["$server_timestamp"].(bool); ok && b {
		return "SERVER_TIMESTAMP"
	}
	out := map[string]any{}
	for k, val := range m {
		out[k] = decodeGolden(val)
	}
	return out
}

// normalizeGoPayload は Go 側の値を golden と比較できる形へ揃える。
// 数値は JSON 由来の float64 に、sentinel と時刻は decodeGolden と同じ表現にする。
func normalizeGoPayload(v any) any {
	switch x := v.(type) {
	case map[string]any:
		out := map[string]any{}
		for k, val := range x {
			out[k] = normalizeGoPayload(val)
		}
		return out
	case int:
		return float64(x)
	case int64:
		return float64(x)
	case time.Time:
		return x.UTC()
	}
	if v == firestore.ServerTimestamp {
		return "SERVER_TIMESTAMP"
	}
	return v
}

type dupTokenGoldenCase struct {
	Users []struct {
		ID   string         `json:"id"`
		Data map[string]any `json:"data"`
	} `json:"users"`
	Expected []string `json:"expected"`
}

// TestDuplicateTokenUidsGolden は JS 実装（dailyBatch.ts:duplicateTokenUids）と
// 突き合わせる。どの doc を残すかは「活動時刻の降順、同着は uid の昇順」で
// 決まるので、同着を踏むケースを含めて比べる。
func TestDuplicateTokenUidsGolden(t *testing.T) {
	raw, err := os.ReadFile("../javascript/scripts/dup_token_golden.json")
	if err != nil {
		t.Fatalf("golden の読み込みに失敗: %v", err)
	}
	var cases []dupTokenGoldenCase
	if err := json.Unmarshal(raw, &cases); err != nil {
		t.Fatal(err)
	}
	if len(cases) == 0 {
		t.Fatal("golden が空")
	}

	var withDuplicates, staleTotal int
	for i, c := range cases {
		owners := make([]tokenOwner, 0, len(c.Users))
		for _, u := range c.Users {
			data, _ := decodeGolden(u.Data).(map[string]any)
			owners = append(owners, tokenOwner{ID: u.ID, Data: data})
		}

		got := duplicateTokenUids(owners)
		want := c.Expected
		if len(want) > 0 {
			withDuplicates++
			staleTotal += len(want)
		}

		// nil と空スライスの差は意味を持たないので長さで揃える
		if len(got) == 0 && len(want) == 0 {
			continue
		}
		if !reflect.DeepEqual(got, want) {
			t.Errorf("case %d: JS=%v Go=%v\n  入力=%v", i, want, got, c.Users)
		}
	}

	t.Logf("%d ケース一致（重複あり %d 件 / 解除対象 %d 件）",
		len(cases), withDuplicates, staleTotal)
	if withDuplicates == 0 {
		t.Error("重複が1件も無い。golden が退化している")
	}
}

// TestOldSentenceCutoff は削除境界が「JST 0:00 の30日前」になることを確かめる。
//
// JS 側は nowJST() と setHours() の組み合わせで、実行環境の TZ が UTC である
// ことに暗黙に依存していた。Go 版はそれを明示した式なので、境界そのものを
// 直接押さえておく。
func TestOldSentenceCutoff(t *testing.T) {
	tests := []struct {
		name string
		now  string
		want string
	}{
		// 期待値は TZ=UTC の node で JS 実装の式をそのまま流して確かめたもの。
		// JST の暦日から30日引き、その日の JST 0:00（= UTC で前日15:00）が境界。
		{"JST 昼", "2026-08-27T06:00:00Z", "2026-07-27T15:00:00Z"},
		// UTC 23:00 は JST では翌日 8:00。JST の暦日が繰り上がるぶん境界も1日ずれる
		{"UTC 深夜（JST は翌日）", "2026-08-27T23:00:00Z", "2026-07-28T15:00:00Z"},
		// UTC 14:59 はまだ JST 同日 23:59
		{"JST 日付境界の直前", "2026-08-27T14:59:59Z", "2026-07-27T15:00:00Z"},
		// UTC 15:00 ちょうどで JST 翌日 0:00
		{"JST 日付境界ちょうど", "2026-08-27T15:00:00Z", "2026-07-28T15:00:00Z"},
		{"月またぎ", "2026-03-05T00:00:00Z", "2026-02-02T15:00:00Z"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			now, err := time.Parse(time.RFC3339, tt.now)
			if err != nil {
				t.Fatal(err)
			}
			want, err := time.Parse(time.RFC3339, tt.want)
			if err != nil {
				t.Fatal(err)
			}
			if got := oldSentenceCutoff(now); !got.Equal(want) {
				t.Errorf("now=%s: want %s, got %s", tt.now, want, got.UTC())
			}
		})
	}
}
