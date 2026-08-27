package function

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"reflect"
	"strings"
	"testing"
	"time"

	"cloud.google.com/go/firestore"

	"github.com/mnbst/thai-memo/functions/go/internal/applejws"
	"github.com/mnbst/thai-memo/functions/go/internal/appstore"
	"github.com/mnbst/thai-memo/functions/go/internal/playbilling"
)

type notificationGolden struct {
	NowMS           int64  `json:"now_ms"`
	RootFingerprint string `json:"root_fingerprint"`
	AppstoreCases   []struct {
		NotificationType string  `json:"notification_type"`
		Subtype          *string `json:"subtype"`
		AutoRenewStatus  *int    `json:"auto_renew_status"`
		ExpiresDate      *int64  `json:"expires_date"`
		CurrentTier      *string `json:"current_tier"`
		SignedPayload    string  `json:"signed_payload"`
		StatusCode       int     `json:"status_code"`
		Body             string  `json:"body"`
		QueriedField     *string `json:"queried_field"`
		Updates          []struct {
			UID  string         `json:"uid"`
			Data map[string]any `json:"data"`
		} `json:"updates"`
	} `json:"appstore_cases"`
	AppstoreEdgeCases []struct {
		Name          string  `json:"name"`
		SignedPayload *string `json:"signed_payload"`
		StatusCode    int     `json:"status_code"`
		Body          string  `json:"body"`
		Updates       []any   `json:"updates"`
	} `json:"appstore_edge_cases"`
	PlayCases []struct {
		SubscriptionState string  `json:"subscription_state"`
		HasExpiry         bool    `json:"has_expiry"`
		CurrentTier       *string `json:"current_tier"`
		QueriedField      *string `json:"queried_field"`
		Updates           []struct {
			UID  string         `json:"uid"`
			Data map[string]any `json:"data"`
		} `json:"updates"`
	} `json:"play_cases"`
	PlayTestNotificationUpdates int `json:"play_test_notification_updates"`
}

func loadNotificationGolden(t *testing.T) *notificationGolden {
	t.Helper()
	raw, err := os.ReadFile("../javascript/scripts/notification_golden.json")
	if err != nil {
		t.Fatalf("golden の読み込みに失敗: %v", err)
	}
	var golden notificationGolden
	if err := json.Unmarshal(raw, &golden); err != nil {
		t.Fatal(err)
	}
	return &golden
}

// TestAppStoreNotificationUpdatesGolden は通知タイプごとの Firestore 更新内容を
// JS 実装と突き合わせる。
//
// golden は本物の handleAppStoreNotification.ts に firebase-admin をスタブして
// 通し、userDoc.ref.update() に渡された内容を記録したもの
// （scripts/genNotificationGolden.ts）。通知タイプ × subtype ×
// autoRenewStatus × expiresDate の有無 × 現在の tier を全組み合わせで比べる。
func TestAppStoreNotificationUpdatesGolden(t *testing.T) {
	golden := loadNotificationGolden(t)
	if len(golden.AppstoreCases) == 0 {
		t.Fatal("golden が空")
	}

	verifier := &applejws.Verifier{RootFingerprint: golden.RootFingerprint}
	client := &appstore.Client{Verifier: verifier}

	var handled, unhandled, keptExpiry, quotaWritten int

	for _, c := range golden.AppstoreCases {
		name := c.NotificationType + "/" + derefOr(c.Subtype, "-") +
			"/renew=" + intOr(c.AutoRenewStatus) +
			"/exp=" + boolStr(c.ExpiresDate != nil) +
			"/tier=" + derefOr(c.CurrentTier, "-")

		t.Run(name, func(t *testing.T) {
			notification, err := client.ParseNotification(c.SignedPayload)
			if err != nil {
				t.Fatalf("署名検証・パースに失敗: %v", err)
			}

			decision := decideAppStoreNotification(notification)
			if !decision.Handled {
				unhandled++
				if len(c.Updates) != 0 {
					t.Errorf("Go は未対応扱いにしたが JS は更新している: %v", c.Updates)
				}
				return
			}
			handled++

			if len(c.Updates) != 1 {
				t.Fatalf("JS 側の更新件数が想定外: %d", len(c.Updates))
			}
			want := decodeGolden(c.Updates[0].Data).(map[string]any)

			got := updatesToMap(appStoreUpdates(
				notification, decision, derefOr(c.CurrentTier, ""), c.Updates[0].UID,
			))

			if _, ok := want["subscription.expires_at"]; !ok {
				keptExpiry++
			}
			if _, ok := want["remaining_sentences"]; ok {
				quotaWritten++
			}

			if !reflect.DeepEqual(got, want) {
				t.Errorf("更新内容が違う\n  JS = %v\n  Go = %v", want, got)
			}
		})
	}

	t.Logf("%d ケース一致（対応 %d / 未対応 %d、expires_at 保持 %d、クォータ書込 %d）",
		len(golden.AppstoreCases), handled, unhandled, keptExpiry, quotaWritten)
	for label, n := range map[string]int{
		"対応": handled, "未対応": unhandled,
		"expires_at 保持": keptExpiry, "クォータ書込": quotaWritten,
	} {
		if n == 0 {
			t.Errorf("%s の分岐が1件も踏まれていない。golden が退化している", label)
		}
	}
}

// TestAppStoreNotificationHTTPGolden は HTTP 層の応答（ステータスと本文）を
// JS 実装と突き合わせる。
//
// Apple はリトライを避けるため 200 を期待する。署名検証に失敗した通知でも
// 200 を返すこと（ただし Firestore は触らないこと）をここで固定する。
func TestAppStoreNotificationHTTPGolden(t *testing.T) {
	golden := loadNotificationGolden(t)

	for _, c := range golden.AppstoreEdgeCases {
		// 「該当ユーザーなし」は Firestore を引くので live テスト側で見る
		if c.SignedPayload != nil && c.Name == "該当ユーザーなし" {
			continue
		}
		t.Run(c.Name, func(t *testing.T) {
			method := http.MethodPost
			body := "{}"
			switch c.Name {
			case "POST 以外":
				method = http.MethodGet
			case "signedPayload 欠落":
				body = "{}"
			default:
				if c.SignedPayload != nil {
					b, _ := json.Marshal(map[string]string{"signedPayload": *c.SignedPayload})
					body = string(b)
				}
			}

			req := httptest.NewRequest(method, "/", strings.NewReader(body))
			rec := httptest.NewRecorder()
			handleAppStoreNotificationHTTP(rec, req)

			if rec.Code != c.StatusCode {
				t.Errorf("ステータス: want %d, got %d", c.StatusCode, rec.Code)
			}
			if got := strings.TrimSpace(rec.Body.String()); got != c.Body {
				t.Errorf("本文: want %q, got %q", c.Body, got)
			}
		})
	}
}

// TestPlayNotificationUpdatesGolden は RTDN 受信時の Firestore 更新内容を
// JS 実装と突き合わせる。
func TestPlayNotificationUpdatesGolden(t *testing.T) {
	golden := loadNotificationGolden(t)
	if len(golden.PlayCases) == 0 {
		t.Fatal("golden が空")
	}

	var quotaWritten int
	for _, c := range golden.PlayCases {
		name := c.SubscriptionState + "/exp=" + boolStr(c.HasExpiry) +
			"/tier=" + derefOr(c.CurrentTier, "-")

		t.Run(name, func(t *testing.T) {
			if len(c.Updates) != 1 {
				t.Fatalf("JS 側の更新件数が想定外: %d", len(c.Updates))
			}
			want := decodeGolden(c.Updates[0].Data).(map[string]any)

			// JS が返した status と expires_at から検証結果を復元する
			// （playbilling の変換そのものは internal/playbilling の golden で見ている）
			status, _ := want["subscription.status"].(string)
			result := &playbilling.VerificationResult{
				Valid:        true,
				Status:       playbilling.Status(status),
				AutoRenewing: want["subscription.auto_renewing"] == true,
			}
			if ts, ok := want["subscription.expires_at"].(time.Time); ok {
				result.ExpiresAt = &ts
			}

			tier := "premium"
			if result.Status == playbilling.StatusExpired {
				tier = "free"
			}
			if want["tier"] != tier {
				t.Fatalf("tier の決め方が違う: JS=%v Go=%s", want["tier"], tier)
			}

			got := updatesToMap(playUpdates(result, tier, derefOr(c.CurrentTier, "")))
			if _, ok := want["remaining_sentences"]; ok {
				quotaWritten++
			}
			if !reflect.DeepEqual(got, want) {
				t.Errorf("更新内容が違う\n  JS = %v\n  Go = %v", want, got)
			}
		})
	}

	t.Logf("%d ケース一致（クォータ書込 %d）", len(golden.PlayCases), quotaWritten)
	if quotaWritten == 0 {
		t.Error("クォータ書込の分岐が踏まれていない。golden が退化している")
	}
	if golden.PlayTestNotificationUpdates != 0 {
		t.Errorf("テスト通知で JS が更新している: %d", golden.PlayTestNotificationUpdates)
	}
}

// updatesToMap は []firestore.Update を golden と比較できる map に直す。
func updatesToMap(updates []firestore.Update) map[string]any {
	out := map[string]any{}
	for _, u := range updates {
		out[u.Path] = normalizeGoPayload(u.Value)
	}
	return out
}

func derefOr(s *string, fallback string) string {
	if s == nil {
		return fallback
	}
	return *s
}

func intOr(v *int) string {
	if v == nil {
		return "-"
	}
	return []string{"0", "1"}[*v]
}

func boolStr(b bool) string {
	if b {
		return "yes"
	}
	return "no"
}
