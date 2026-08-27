package function

import (
	"testing"
	"time"

	"github.com/mnbst/thai-memo/functions/go/internal/applejws"
	"github.com/mnbst/thai-memo/functions/go/internal/appstore"
)

// ストア通知ハンドラの Firestore 部分を dev の実 Firestore で確かめる。
// 更新内容そのものは golden テストで JS と突き合わせているので、ここで見るのは
// 「クエリが当たるか」「複数 doc に効くか」「無関係な doc を触らないか」。
//
//	GCLOUD_PROJECT=thai-memo-dev LIVE_FIRESTORE_TEST=1 \
//	  go test -run TestNotification -v .

// TestNotificationPlayUpdatesAllMatchingDocs は同じ purchase_token を持つ
// 全 doc が更新されることを確かめる。
//
// 匿名ユーザーの再インストール等で同一サブスクの doc が複数残るため、
// limit(1) にせず全件を更新する必要がある。
func TestNotificationPlayUpdatesAllMatchingDocs(t *testing.T) {
	db, ctx := liveFirestore(t)

	const token = "go-port-rtdn-token"
	uids := []string{
		"go-port-rtdn-a-throwaway",
		"go-port-rtdn-b-throwaway",
		"go-port-rtdn-other-throwaway",
	}
	t.Cleanup(func() {
		for _, uid := range uids {
			_, _ = db.Collection("users").Doc(uid).Delete(ctx)
		}
	})

	// 同じトークンを持つ2件（片方は既に premium、片方は free）
	for i, uid := range uids[:2] {
		tier := "free"
		if i == 1 {
			tier = "premium"
		}
		if _, err := db.Collection("users").Doc(uid).Set(ctx, map[string]any{
			"tier":                tier,
			"remaining_sentences": int64(1),
			"subscription": map[string]any{
				"platform": "android", "purchase_token": token,
				"status": "active", "product_id": "premium_monthly",
			},
		}); err != nil {
			t.Fatal(err)
		}
	}
	// 別トークン（触ってはいけない）
	if _, err := db.Collection("users").Doc(uids[2]).Set(ctx, map[string]any{
		"tier": "premium",
		"subscription": map[string]any{
			"platform": "android", "purchase_token": "go-port-rtdn-other-token",
			"status": "active",
		},
	}); err != nil {
		t.Fatal(err)
	}

	expiry := time.Now().Add(20 * 24 * time.Hour).UTC().
		Format("2006-01-02T15:04:05.000Z")
	usePlayStub(t, playResponse("SUBSCRIPTION_STATE_CANCELED", expiry, false))

	if err := processPlayNotification(ctx,
		"com.thaimemo.thai_memo", "premium_monthly", token); err != nil {
		t.Fatal(err)
	}

	for i, uid := range uids[:2] {
		doc, err := db.Collection("users").Doc(uid).Get(ctx)
		if err != nil {
			t.Fatal(err)
		}
		data := doc.Data()
		if data["tier"] != "premium" {
			t.Errorf("%s: tier want premium, got %v", uid, data["tier"])
		}
		sub, _ := data["subscription"].(map[string]any)
		if sub["status"] != "canceled" {
			t.Errorf("%s: status want canceled, got %v", uid, sub["status"])
		}
		// ドット記法の更新なので、通知に含まれないフィールドは残る
		if sub["purchase_token"] != token || sub["product_id"] != "premium_monthly" {
			t.Errorf("%s: subscription が上書きされている: %v", uid, sub)
		}
		// free だった方だけクォータがリセットされる
		wantRemaining := int64(20)
		if i == 1 {
			wantRemaining = int64(1) // 既に premium なので触らない
		}
		if data["remaining_sentences"] != wantRemaining {
			t.Errorf("%s: remaining_sentences want %d, got %v",
				uid, wantRemaining, data["remaining_sentences"])
		}
	}

	other, err := db.Collection("users").Doc(uids[2]).Get(ctx)
	if err != nil {
		t.Fatal(err)
	}
	otherSub, _ := other.Data()["subscription"].(map[string]any)
	if otherSub["status"] != "active" {
		t.Errorf("別トークンの doc が巻き添えで更新された: %v", otherSub)
	}
}

// TestNotificationPlayNoUser は該当ユーザーが居なければ何もせず正常終了する
// ことを確かめる（初回購入前の通知など）。
func TestNotificationPlayNoUser(t *testing.T) {
	_, ctx := liveFirestore(t)

	usePlayStub(t, playResponse("SUBSCRIPTION_STATE_ACTIVE", "", true))

	err := processPlayNotification(ctx, "com.thaimemo.thai_memo",
		"premium_monthly", "go-port-nonexistent-token-xyz")
	if err != nil {
		t.Errorf("該当なしはエラーにしない: %v", err)
	}
}

// TestNotificationAppStoreEndToEnd は署名検証からFirestore更新までを通す。
func TestNotificationAppStoreEndToEnd(t *testing.T) {
	db, ctx := liveFirestore(t)
	golden := loadNotificationGolden(t)

	// golden はテスト用ルート CA で署名されているので、ピン留めを差し替える。
	original := appstore.Default
	appstore.Default = &appstore.Client{
		Verifier: &applejws.Verifier{RootFingerprint: golden.RootFingerprint},
	}
	t.Cleanup(func() { appstore.Default = original })

	// golden から「DID_FAIL_TO_RENEW / GRACE_PERIOD」の通知を借りる。
	// premium を維持しつつ grace_period にする、判定が一番込み入ったケース。
	var signedPayload string
	var wantExpires *int64
	for _, c := range golden.AppstoreCases {
		if c.NotificationType == "DID_FAIL_TO_RENEW" &&
			c.Subtype != nil && *c.Subtype == "GRACE_PERIOD" &&
			c.ExpiresDate != nil && c.CurrentTier != nil && *c.CurrentTier == "free" {
			signedPayload = c.SignedPayload
			wantExpires = c.ExpiresDate
			break
		}
	}
	if signedPayload == "" {
		t.Fatal("golden に該当する通知が無い")
	}

	// golden の通知が指す originalTransactionId を持つ doc を作る
	notification, err := appstore.Default.ParseNotification(signedPayload)
	if err != nil {
		t.Fatal(err)
	}

	const uid = "go-port-appstore-notif-throwaway"
	ref := db.Collection("users").Doc(uid)
	t.Cleanup(func() { _, _ = ref.Delete(ctx) })

	if _, err := ref.Set(ctx, map[string]any{
		"tier":                "free",
		"remaining_sentences": int64(0),
		"subscription": map[string]any{
			"platform":                "ios",
			"original_transaction_id": notification.TransactionInfo.OriginalTransactionID,
			"status":                  "expired",
			"product_id":              "com.thaimemo.monthly",
		},
	}); err != nil {
		t.Fatal(err)
	}

	if err := processAppStoreNotification(ctx, signedPayload); err != nil {
		t.Fatal(err)
	}

	doc, err := ref.Get(ctx)
	if err != nil {
		t.Fatal(err)
	}
	data := doc.Data()
	if data["tier"] != "premium" {
		t.Errorf("tier: want premium, got %v", data["tier"])
	}
	if data["remaining_sentences"] != int64(20) {
		t.Errorf("remaining_sentences: want 20, got %v", data["remaining_sentences"])
	}
	sub, _ := data["subscription"].(map[string]any)
	if sub["status"] != "grace_period" {
		t.Errorf("status: want grace_period, got %v", sub["status"])
	}
	if sub["product_id"] != "com.thaimemo.monthly" {
		t.Errorf("subscription が上書きされている: %v", sub)
	}
	if ts, ok := sub["expires_at"].(time.Time); !ok {
		t.Errorf("expires_at が Timestamp で入っていない: %#v", sub["expires_at"])
	} else if ts.UnixMilli() != *wantExpires {
		t.Errorf("expires_at: want %d, got %d", *wantExpires, ts.UnixMilli())
	}
}

// TestNotificationAppStoreNoUser は該当ユーザーが居なければ何もしないことを確かめる。
func TestNotificationAppStoreNoUser(t *testing.T) {
	_, ctx := liveFirestore(t)
	golden := loadNotificationGolden(t)

	original := appstore.Default
	appstore.Default = &appstore.Client{
		Verifier: &applejws.Verifier{RootFingerprint: golden.RootFingerprint},
	}
	t.Cleanup(func() { appstore.Default = original })

	// 該当 doc を作らないまま流す
	for _, c := range golden.AppstoreCases {
		if c.NotificationType == "DID_RENEW" {
			if err := processAppStoreNotification(ctx, c.SignedPayload); err != nil {
				t.Errorf("該当なしはエラーにしない: %v", err)
			}
			return
		}
	}
	t.Fatal("golden に DID_RENEW が無い")
}
