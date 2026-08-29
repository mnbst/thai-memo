package function

import (
	"context"
	"fmt"
	"log"
	"os"
	"slices"
	"strings"
	"time"

	"cloud.google.com/go/firestore"
	"google.golang.org/api/iterator"

	"github.com/mnbst/thai-memo/functions/go/internal/appstore"
	"github.com/mnbst/thai-memo/functions/go/internal/callable"
	"github.com/mnbst/thai-memo/functions/go/internal/fbapp"
	"github.com/mnbst/thai-memo/functions/go/internal/playbilling"
	"github.com/mnbst/thai-memo/functions/go/internal/quota"
)

// verifySubscription は functions/javascript/src/verifySubscription.ts の移植。
//
// クライアント（iOS/Android）から購入トークンまたはレシートを受け取り、
// 各ストア API（App Store Server API / Google Play Developer API）で
// 購入の正当性を検証したうえで、Firestore にサブスクリプション状態を保存する。

// defaultAndroidPackageName は ANDROID_PACKAGE_NAME 未設定時のパッケージ名。
const defaultAndroidPackageName = "com.thaimemo.thai_memo"

const (
	productIDPremiumMonthly     = "premium_monthly"
	productIDPremiumMonthlyTest = "premium_monthly_test"
)

// isoMillisLayout は JS の Date#toISOString() と同じ表記。
const isoMillisLayout = "2006-01-02T15:04:05.000Z"

func verifySubscription(ctx context.Context, req *callable.Request) (any, error) {
	uid, err := req.RequireAuth()
	if err != nil {
		return nil, err
	}

	// プレミアムはサインイン（Google/Apple連携済み）時のみ利用可能。
	// 匿名 uid は再インストールで失われ premium の所有権が迷子になるため、
	// 匿名ユーザーへの付与自体をサーバー側で拒否する。
	if req.Auth != nil && req.Auth.Token != nil &&
		req.Auth.Token.Firebase.SignInProvider == "anonymous" {
		return nil, callable.Errorf(callable.FailedPrecondition,
			"プレミアムのご利用にはサインインが必要です")
	}

	var in struct {
		Platform      string `json:"platform"`
		PurchaseToken string `json:"purchase_token"`
		ProductID     string `json:"product_id"`
	}
	if err := req.Bind(&in); err != nil {
		return nil, err
	}

	if in.Platform == "" || in.PurchaseToken == "" || in.ProductID == "" {
		return nil, callable.Errorf(callable.InvalidArgument,
			"platform, purchase_token, product_id は必須です")
	}
	if in.Platform != "android" && in.Platform != "ios" {
		return nil, callable.Errorf(callable.InvalidArgument,
			"platform は android または ios を指定してください")
	}
	if !isAllowedSubscriptionProduct(in.ProductID) {
		return nil, callable.Errorf(callable.InvalidArgument,
			"許可されていないサブスクリプション商品です")
	}

	result, err := runVerification(ctx, uid, in.Platform, in.PurchaseToken, in.ProductID)
	if err != nil {
		// JS 版は検証本体を try/catch でまとめて包み、中で起きた例外の中身を
		// クライアントへ出さない。同じ扱いにする。
		log.Printf("Subscription verification failed: %v", err)
		return nil, callable.Errorf(callable.Internal,
			"サブスクリプションの検証に失敗しました")
	}
	return result, nil
}

// runVerification は JS 版の try ブロックに相当する。
func runVerification(
	ctx context.Context, uid, platform, purchaseToken, productID string,
) (any, error) {
	db, err := fbapp.Firestore(ctx)
	if err != nil {
		return nil, err
	}

	userRef := db.Collection("users").Doc(uid)
	userDoc, err := userRef.Get(ctx)
	if err != nil && !isNotFoundErr(err) {
		return nil, err
	}
	currentTier := "free"
	if userDoc != nil && userDoc.Exists() {
		if t, ok := userDoc.Data()["tier"].(string); ok && t != "" {
			currentTier = t
		}
	}

	var (
		status       string
		expiresAt    *time.Time
		autoRenewing bool
		// ストア通知でユーザーを引くためのキー
		identifierField string
		identifierValue string
		subscription    map[string]any
	)

	if platform == "android" {
		packageName := os.Getenv("ANDROID_PACKAGE_NAME")
		if packageName == "" {
			packageName = defaultAndroidPackageName
		}
		res, err := playbilling.Default.VerifyPurchase(
			ctx, packageName, productID, purchaseToken)
		if err != nil {
			return nil, err
		}
		if res.ProductID != productID {
			return nil, fmt.Errorf("Play product mismatch: requested=%q verified=%q",
				productID, res.ProductID)
		}
		status = string(res.Status)
		expiresAt = res.ExpiresAt
		autoRenewing = res.AutoRenewing
		identifierField = "subscription.purchase_token"
		identifierValue = purchaseToken
		subscription = map[string]any{
			"product_id": productID,
			"platform":   "android",
			// RTDN（Google Play通知）での検索に使用
			"purchase_token": purchaseToken,
		}
	} else {
		res, err := appstore.Default.VerifyPurchase(ctx, purchaseToken)
		if err != nil {
			return nil, err
		}
		if res.ProductID != productID {
			return nil, fmt.Errorf("App Store product mismatch: requested=%q verified=%q",
				productID, res.ProductID)
		}
		status = string(res.Status)
		if res.ExpiresAt != nil {
			t := time.UnixMilli(*res.ExpiresAt).UTC()
			expiresAt = &t
		}
		autoRenewing = res.AutoRenewing
		identifierField = "subscription.original_transaction_id"
		identifierValue = res.OriginalTransactionID
		subscription = map[string]any{
			"product_id": productID,
			"platform":   "ios",
			// App Store通知での検索に使用
			"original_transaction_id": res.OriginalTransactionID,
		}
	}

	newTier := "premium"
	if status == "expired" {
		newTier = "free"
	}

	subscription["status"] = status
	subscription["auto_renewing"] = autoRenewing
	subscription["updated_at"] = firestore.ServerTimestamp
	if expiresAt != nil {
		subscription["expires_at"] = *expiresAt
	} else {
		subscription["expires_at"] = nil
	}

	payload := map[string]any{
		"tier":         newTier,
		"subscription": subscription,
	}
	// クォータはティアが変わる時のみリセット（復元検証で誤リセットしない）
	if currentTier != newTier {
		if newTier == "premium" {
			payload["remaining_sentences"] = quota.PremiumDailySentences
			payload["remaining_quizzes"] = quota.PremiumDailyQuizzes
		} else {
			payload["remaining_sentences"] = quota.FreeDailySentences
			payload["remaining_quizzes"] = quota.FreeDailyQuizzes
		}
	}

	if _, err := userRef.Set(ctx, payload, firestore.MergeAll); err != nil {
		return nil, err
	}

	if err := releaseSubscriptionFromOtherUsers(
		ctx, db, identifierField, identifierValue, uid,
	); err != nil {
		return nil, err
	}

	out := map[string]any{
		"plan":       newTier,
		"expires_at": nil,
		"status":     status,
	}
	if expiresAt != nil {
		out["expires_at"] = expiresAt.UTC().Format(isoMillisLayout)
	}
	return out, nil
}

// projectIDPremiumProducts は環境（GCP プロジェクト）ごとに販売している商品 ID。
// dev は両ストア設定を検証するため両方を許可する。
var projectIDPremiumProducts = map[string][]string{
	"thai-memo-prod":  {productIDPremiumMonthly},
	"thai-memo-67139": {productIDPremiumMonthlyTest},
	"thai-memo-dev":   {productIDPremiumMonthly, productIDPremiumMonthlyTest},
}

// isAllowedSubscriptionProduct は、この環境が販売する商品だけを許可する。
// デプロイ時に SUBSCRIPTION_PRODUCT_IDS（カンマ区切り）を指定すれば明示値を優先する。
//
// プロジェクト ID は fbapp.ProjectID() で引く。2nd gen では GCLOUD_PROJECT が
// 無いことがあり、単独で見ると prod でも「未知の環境」に落ちてしまう。
// 未知の環境は拒否する（fail-closed）。tester 商品が prod で通る状態を作らない。
func isAllowedSubscriptionProduct(productID string) bool {
	configured := strings.TrimSpace(os.Getenv("SUBSCRIPTION_PRODUCT_IDS"))
	if configured != "" {
		for _, allowed := range strings.Split(configured, ",") {
			if strings.TrimSpace(allowed) == productID {
				return true
			}
		}
		return false
	}

	projectID := fbapp.ProjectID()
	allowed, ok := projectIDPremiumProducts[projectID]
	if !ok {
		// 環境を特定できないと商品の妥当性を判断できない。全購入が
		// InvalidArgument で落ちる状態なので、専用イベント名で気付けるようにする。
		log.Printf("subscription_product_allowlist_unresolved project=%q product=%q",
			projectID, productID)
		return false
	}
	return slices.Contains(allowed, productID)
}

// releaseSubscriptionFromOtherUsers は同一サブスクリプションを保持する
// 他ユーザーの doc から premium を剥奪する。
//
// 匿名ユーザーの再インストール等で uid が変わると、旧 uid の doc に
// premium とサブスク情報が残ったままになる。放置するとストア通知の
// ユーザー検索が旧 doc にヒットし、現役 doc の解約処理が漏れて
// premium が永久に残る。サブスクは常に最後に検証した uid のみに紐づける。
func releaseSubscriptionFromOtherUsers(
	ctx context.Context, db *firestore.Client,
	identifierField, identifierValue, currentUID string,
) error {
	it := db.Collection("users").
		Where(identifierField, "==", identifierValue).
		Documents(ctx)
	defer it.Stop()

	for {
		doc, err := it.Next()
		if err == iterator.Done {
			return nil
		}
		if err != nil {
			return err
		}
		if doc.Ref.ID == currentUID {
			continue
		}
		if _, err := doc.Ref.Update(ctx, []firestore.Update{
			{Path: "tier", Value: "free"},
			{Path: "remaining_sentences", Value: quota.FreeDailySentences},
			{Path: "remaining_quizzes", Value: quota.FreeDailyQuizzes},
			{Path: "subscription", Value: firestore.Delete},
		}); err != nil {
			return err
		}
		log.Printf("Released subscription from user %s (now owned by %s)",
			doc.Ref.ID, currentUID)
	}
}
