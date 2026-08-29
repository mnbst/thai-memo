package function

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"strings"
	"testing"
	"time"

	"cloud.google.com/go/firestore"

	"github.com/mnbst/thai-memo/functions/go/internal/callable"
	"github.com/mnbst/thai-memo/functions/go/internal/playbilling"
)

// verifySubscription を dev の実 Firestore に対して確かめる。
// ストア API は差し替える（本物の購入トークンは持てないため）。
//
//	GCLOUD_PROJECT=thai-memo-dev LIVE_FIRESTORE_TEST=1 \
//	  go test -run TestVerifySubscription -v .

// playStub は Play API のレスポンスを固定で返す。
type playStub struct{ body string }

func (p *playStub) RoundTrip(req *http.Request) (*http.Response, error) {
	return &http.Response{
		StatusCode: http.StatusOK,
		Body:       io.NopCloser(strings.NewReader(p.body)),
		Header:     http.Header{},
		Request:    req,
	}, nil
}

// usePlayStub は playbilling.Default を差し替え、テスト終了時に戻す。
func usePlayStub(t *testing.T, body string) {
	t.Helper()
	original := playbilling.Default
	playbilling.Default = &playbilling.Client{
		HTTP: &http.Client{Transport: &playStub{body: body}},
	}
	t.Cleanup(func() { playbilling.Default = original })
}

func playResponse(state, expiryTime string, autoRenew bool) string {
	body := map[string]any{
		"kind":              "androidpublisher#subscriptionPurchaseV2",
		"subscriptionState": state,
		"lineItems": []any{map[string]any{
			"productId":        "premium_monthly",
			"expiryTime":       expiryTime,
			"autoRenewingPlan": map[string]any{"autoRenewEnabled": autoRenew},
		}},
	}
	b, _ := json.Marshal(body)
	return string(b)
}

// TestVerifySubscriptionValidation は認証・引数のバリデーションを確かめる。
// Firestore にもストアにも触れないので、実行に外部依存がない。
func TestVerifySubscriptionValidation(t *testing.T) {
	ctx := context.Background()
	setProjectEnv(t, "thai-memo-dev")
	t.Setenv("SUBSCRIPTION_PRODUCT_IDS", "")

	cases := []struct {
		name     string
		req      *callable.Request
		wantCode callable.Code
		wantMsg  string
	}{
		{
			"未認証",
			&callable.Request{Data: json.RawMessage(`{}`)},
			callable.Unauthenticated, "認証が必要です",
		},
		{
			"platform 欠落",
			authedRequest(`{"purchase_token":"t","product_id":"p"}`),
			callable.InvalidArgument, "platform, purchase_token, product_id は必須です",
		},
		{
			"purchase_token 欠落",
			authedRequest(`{"platform":"ios","product_id":"p"}`),
			callable.InvalidArgument, "platform, purchase_token, product_id は必須です",
		},
		{
			"product_id 欠落",
			authedRequest(`{"platform":"ios","purchase_token":"t"}`),
			callable.InvalidArgument, "platform, purchase_token, product_id は必須です",
		},
		{
			"空文字は欠落と同じ",
			authedRequest(`{"platform":"","purchase_token":"t","product_id":"p"}`),
			callable.InvalidArgument, "platform, purchase_token, product_id は必須です",
		},
		{
			"未知の platform",
			authedRequest(`{"platform":"web","purchase_token":"t","product_id":"p"}`),
			callable.InvalidArgument, "platform は android または ios を指定してください",
		},
		{
			"未知の商品",
			authedRequest(`{"platform":"ios","purchase_token":"t","product_id":"other_subscription"}`),
			callable.InvalidArgument, "許可されていないサブスクリプション商品です",
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			_, err := verifySubscription(ctx, tc.req)
			assertCallableError(t, err, tc.wantCode, tc.wantMsg)
		})
	}
}

// setProjectEnv は fbapp.ProjectID() が見る 3 つの環境変数をまとめて上書きする。
// 1 つだけ設定すると、実行環境に残った別の変数で結果が変わる。
func setProjectEnv(t *testing.T, projectID string) {
	t.Helper()
	for _, k := range []string{"GCLOUD_PROJECT", "GCP_PROJECT", "GOOGLE_CLOUD_PROJECT"} {
		t.Setenv(k, projectID)
	}
}

func TestAllowedSubscriptionProducts(t *testing.T) {
	t.Run("prod は本番商品のみ", func(t *testing.T) {
		setProjectEnv(t, "thai-memo-prod")
		t.Setenv("SUBSCRIPTION_PRODUCT_IDS", "")
		if !isAllowedSubscriptionProduct("premium_monthly") {
			t.Fatal("本番商品が拒否された")
		}
		if isAllowedSubscriptionProduct("premium_monthly_test") {
			t.Fatal("prod で tester 商品が許可された")
		}
	})

	t.Run("tester はテスト商品のみ", func(t *testing.T) {
		setProjectEnv(t, "thai-memo-67139")
		t.Setenv("SUBSCRIPTION_PRODUCT_IDS", "")
		if !isAllowedSubscriptionProduct("premium_monthly_test") {
			t.Fatal("tester 商品が拒否された")
		}
		if isAllowedSubscriptionProduct("premium_monthly") {
			t.Fatal("tester で本番商品が許可された")
		}
	})

	t.Run("dev は両方許可", func(t *testing.T) {
		setProjectEnv(t, "thai-memo-dev")
		t.Setenv("SUBSCRIPTION_PRODUCT_IDS", "")
		if !isAllowedSubscriptionProduct("premium_monthly") ||
			!isAllowedSubscriptionProduct("premium_monthly_test") {
			t.Fatal("dev で商品が拒否された")
		}
	})

	// 2nd gen では GCLOUD_PROJECT が無く GOOGLE_CLOUD_PROJECT だけのことがある。
	// そこで prod と判定できないと tester 商品が prod で通ってしまう。
	t.Run("GCLOUD_PROJECT が無くても prod と判定する", func(t *testing.T) {
		t.Setenv("GCLOUD_PROJECT", "")
		t.Setenv("GCP_PROJECT", "")
		t.Setenv("GOOGLE_CLOUD_PROJECT", "thai-memo-prod")
		t.Setenv("SUBSCRIPTION_PRODUCT_IDS", "")
		if isAllowedSubscriptionProduct("premium_monthly_test") {
			t.Fatal("prod で tester 商品が許可された")
		}
		if !isAllowedSubscriptionProduct("premium_monthly") {
			t.Fatal("本番商品が拒否された")
		}
	})

	t.Run("環境を特定できなければ拒否する", func(t *testing.T) {
		setProjectEnv(t, "")
		t.Setenv("SUBSCRIPTION_PRODUCT_IDS", "")
		if isAllowedSubscriptionProduct("premium_monthly") {
			t.Fatal("未知の環境で商品が許可された")
		}
	})

	t.Run("明示 allowlist を優先", func(t *testing.T) {
		setProjectEnv(t, "thai-memo-prod")
		t.Setenv("SUBSCRIPTION_PRODUCT_IDS", " custom_a,custom_b ")
		if !isAllowedSubscriptionProduct("custom_b") ||
			isAllowedSubscriptionProduct("premium_monthly") {
			t.Fatal("明示 allowlist が適用されていない")
		}
	})
}

// TestVerifySubscriptionRejectsAnonymous は匿名ユーザーを拒否することを確かめる。
//
// プレミアムの所有権は uid に紐づく。匿名 uid は再インストールで失われるため、
// ここを通すと購入が迷子になる。
func TestVerifySubscriptionRejectsAnonymous(t *testing.T) {
	req := authedRequest(`{"platform":"ios","purchase_token":"t","product_id":"p"}`)
	req.Auth.Token.Firebase.SignInProvider = "anonymous"

	_, err := verifySubscription(context.Background(), req)
	assertCallableError(t, err, callable.FailedPrecondition,
		"プレミアムのご利用にはサインインが必要です")
}

// TestVerifySubscriptionWrites は検証結果の書き込みを実 Firestore で確かめる。
func TestVerifySubscriptionWrites(t *testing.T) {
	db, ctx := liveFirestore(t)

	const uid = "go-port-verifysub-throwaway"
	ref := db.Collection("users").Doc(uid)
	t.Cleanup(func() { _, _ = ref.Delete(ctx) })

	expiry := time.Now().Add(20 * 24 * time.Hour).UTC().
		Format("2006-01-02T15:04:05.000Z")

	t.Run("free から premium へ上がるときはクォータもリセットする", func(t *testing.T) {
		usePlayStub(t, playResponse("SUBSCRIPTION_STATE_ACTIVE", expiry, true))

		if _, err := ref.Set(ctx, map[string]any{
			"tier":                "free",
			"remaining_sentences": int64(0),
			"nickname":            "keep-me",
		}); err != nil {
			t.Fatal(err)
		}

		out, err := runVerification(ctx, uid, "android", "token-abc", "premium_monthly")
		if err != nil {
			t.Fatal(err)
		}
		result, _ := out.(map[string]any)
		if result["plan"] != "premium" {
			t.Errorf("plan: want premium, got %v", result["plan"])
		}
		if result["status"] != "active" {
			t.Errorf("status: want active, got %v", result["status"])
		}
		if result["expires_at"] != expiry {
			t.Errorf("expires_at: want %s, got %v", expiry, result["expires_at"])
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
		if data["nickname"] != "keep-me" {
			t.Errorf("merge されていない: %v", data["nickname"])
		}
		sub, _ := data["subscription"].(map[string]any)
		if sub["platform"] != "android" || sub["purchase_token"] != "token-abc" {
			t.Errorf("subscription: %v", sub)
		}
		if _, ok := sub["expires_at"].(time.Time); !ok {
			t.Errorf("expires_at が Timestamp で入っていない: %#v", sub["expires_at"])
		}
	})

	t.Run("ティアが変わらないならクォータを触らない", func(t *testing.T) {
		usePlayStub(t, playResponse("SUBSCRIPTION_STATE_ACTIVE", expiry, true))

		// 既に premium。残り回数を減らした状態で復元検証を走らせる。
		if _, err := ref.Set(ctx, map[string]any{
			"tier":                "premium",
			"remaining_sentences": int64(3),
		}, firestore.MergeAll); err != nil {
			t.Fatal(err)
		}

		if _, err := runVerification(ctx, uid, "android", "token-abc", "premium_monthly"); err != nil {
			t.Fatal(err)
		}

		doc, err := ref.Get(ctx)
		if err != nil {
			t.Fatal(err)
		}
		if got := doc.Data()["remaining_sentences"]; got != int64(3) {
			t.Errorf("復元検証でクォータがリセットされている: want 3, got %v", got)
		}
	})

	t.Run("期限切れなら free に落としてクォータもリセットする", func(t *testing.T) {
		usePlayStub(t, playResponse("SUBSCRIPTION_STATE_EXPIRED", expiry, false))

		out, err := runVerification(ctx, uid, "android", "token-abc", "premium_monthly")
		if err != nil {
			t.Fatal(err)
		}
		result, _ := out.(map[string]any)
		if result["plan"] != "free" || result["status"] != "expired" {
			t.Errorf("want free/expired, got %v", result)
		}

		doc, err := ref.Get(ctx)
		if err != nil {
			t.Fatal(err)
		}
		if doc.Data()["remaining_sentences"] != int64(5) {
			t.Errorf("remaining_sentences: want 5, got %v",
				doc.Data()["remaining_sentences"])
		}
	})

	t.Run("expiryTime が無ければ expires_at は null", func(t *testing.T) {
		usePlayStub(t, playResponse("SUBSCRIPTION_STATE_ACTIVE", "", true))

		out, err := runVerification(ctx, uid, "android", "token-abc", "premium_monthly")
		if err != nil {
			t.Fatal(err)
		}
		result, _ := out.(map[string]any)
		if result["expires_at"] != nil {
			t.Errorf("expires_at: want null, got %v", result["expires_at"])
		}
		// expiryTime 無しは期限判定が働かないので expired 扱い
		if result["plan"] != "free" {
			t.Errorf("plan: want free, got %v", result["plan"])
		}
	})
}

// TestVerifySubscriptionReleasesOtherUsers は同じ購入トークンを持つ
// 旧 doc から premium を剥奪することを確かめる。
//
// ここが漏れるとストア通知の検索が旧 doc に当たり、現役 doc の解約が
// 効かずに premium が永久に残る。
func TestVerifySubscriptionReleasesOtherUsers(t *testing.T) {
	db, ctx := liveFirestore(t)

	const newUID = "go-port-release-new-throwaway"
	const oldUID = "go-port-release-old-throwaway"
	const otherUID = "go-port-release-other-throwaway"
	const token = "go-port-shared-purchase-token"

	t.Cleanup(func() {
		for _, uid := range []string{newUID, oldUID, otherUID} {
			_, _ = db.Collection("users").Doc(uid).Delete(ctx)
		}
	})

	// 同じトークンを握ったまま残っている旧 doc
	if _, err := db.Collection("users").Doc(oldUID).Set(ctx, map[string]any{
		"tier":                "premium",
		"remaining_sentences": int64(20),
		"subscription": map[string]any{
			"platform": "android", "purchase_token": token, "status": "active",
		},
	}); err != nil {
		t.Fatal(err)
	}
	// 別のトークンを持つ無関係な doc（巻き添えにしてはいけない）
	if _, err := db.Collection("users").Doc(otherUID).Set(ctx, map[string]any{
		"tier": "premium",
		"subscription": map[string]any{
			"platform": "android", "purchase_token": "different-token",
		},
	}); err != nil {
		t.Fatal(err)
	}

	usePlayStub(t, playResponse("SUBSCRIPTION_STATE_ACTIVE",
		time.Now().Add(20*24*time.Hour).UTC().Format("2006-01-02T15:04:05.000Z"), true))

	if _, err := runVerification(ctx, newUID, "android", token, "premium_monthly"); err != nil {
		t.Fatal(err)
	}

	oldDoc, err := db.Collection("users").Doc(oldUID).Get(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if oldDoc.Data()["tier"] != "free" {
		t.Errorf("旧 doc が premium のまま: %v", oldDoc.Data()["tier"])
	}
	if oldDoc.Data()["remaining_sentences"] != int64(5) {
		t.Errorf("旧 doc のクォータ: want 5, got %v",
			oldDoc.Data()["remaining_sentences"])
	}
	if _, ok := oldDoc.Data()["subscription"]; ok {
		t.Errorf("旧 doc の subscription が消えていない: %v", oldDoc.Data()["subscription"])
	}

	newDoc, err := db.Collection("users").Doc(newUID).Get(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if newDoc.Data()["tier"] != "premium" {
		t.Errorf("新 doc が premium になっていない: %v", newDoc.Data()["tier"])
	}

	otherDoc, err := db.Collection("users").Doc(otherUID).Get(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if otherDoc.Data()["tier"] != "premium" {
		t.Errorf("無関係な doc が巻き添えで free になった")
	}
}
