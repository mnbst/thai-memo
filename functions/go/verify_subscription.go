package function

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
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

	// 買い切り（非消費型）。期限を持たず、返金・取消でのみ無効になる。
	// 現状 iOS のみ販売する（Play の一時購入は purchases.products API が別で未対応）。
	productIDPremiumLifetime     = "premium_lifetime"
	productIDPremiumLifetimeTest = "premium_lifetime_test"
)

// isLifetimeProduct は買い切り商品かどうか。
func isLifetimeProduct(productID string) bool {
	return productID == productIDPremiumLifetime ||
		productID == productIDPremiumLifetimeTest
}

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
	if len(in.PurchaseToken) > 32<<10 || len(in.ProductID) > 128 {
		return nil, callable.Errorf(callable.InvalidArgument,
			"購入情報のサイズが上限を超えています")
	}
	if in.Platform != "android" && in.Platform != "ios" {
		return nil, callable.Errorf(callable.InvalidArgument,
			"platform は android または ios を指定してください")
	}
	if !isAllowedSubscriptionProduct(in.ProductID) {
		return nil, callable.Errorf(callable.InvalidArgument,
			"許可されていないサブスクリプション商品です")
	}
	// 買い切りは Play の一時購入 API（purchases.products）が未実装なので iOS のみ。
	if isLifetimeProduct(in.ProductID) && in.Platform != "ios" {
		return nil, callable.Errorf(callable.InvalidArgument,
			"この商品は iOS でのみご利用いただけます")
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
			"lifetime":       false,
		}
	} else {
		lifetime := isLifetimeProduct(productID)

		// 買い切りは期限が無いのが正常なので、期限で判定する経路を通さない。
		verify := appstore.Default.VerifyPurchase
		if lifetime {
			verify = appstore.Default.VerifyOneTimePurchase
		}
		res, err := verify(ctx, purchaseToken)
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
			// 期限切れフォールバック（dailyBatch / subscriptionStatus）に
			// 「expires_at が無くても落とすな」と伝える目印。
			// 月額へ戻ったときに残らないよう、常に書く。
			"lifetime": lifetime,
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

	if err := persistSubscriptionOwnership(ctx, db, userRef, subscription, newTier,
		identifierField, identifierValue); err != nil {
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
	"thai-memo-prod":  {productIDPremiumMonthly, productIDPremiumLifetime},
	"thai-memo-67139": {productIDPremiumMonthlyTest, productIDPremiumLifetimeTest},
	"thai-memo-dev": {
		productIDPremiumMonthly, productIDPremiumMonthlyTest,
		productIDPremiumLifetime, productIDPremiumLifetimeTest,
	},
}

// isAllowedSubscriptionProduct は、この環境が販売する商品だけを許可する。
// デプロイ時に SUBSCRIPTION_PRODUCT_IDS（カンマ区切り）を指定すれば明示値を優先する。
//
// プロジェクト ID は fbapp.ProjectID() で引く。2nd gen では GCLOUD_PROJECT が
// 無いことがあり、単独で見ると prod でも「未知の環境」に落ちてしまう。
// 未知の環境は拒否する（fail-closed）。tester 商品が prod で通る状態を作らない。
func isAllowedSubscriptionProduct(productID string) bool {
	allowed, ok := subscriptionProductAllowlist()
	if !ok {
		// 環境を特定できないと商品の妥当性を判断できない。全購入が
		// InvalidArgument で落ちる状態なので、専用イベント名で気付けるようにする。
		log.Printf("subscription_product_allowlist_unresolved project=%q product=%q",
			fbapp.ProjectID(), productID)
		return false
	}
	return slices.Contains(allowed, productID)
}

// subscriptionProductAllowlist はこの環境が販売する商品 ID の一覧を返す。
//
// ok=false は「環境を特定できず、許可・不許可を判断できない」を表す。
// 判断できないことと「不正な商品」は区別する必要がある。ストア通知の経路では
// 前者を 200 で捨てると Apple が再送しないまま課金状態がずれ続けるため、
// 呼び出し側は再試行可能なエラーとして扱う。
func subscriptionProductAllowlist() ([]string, bool) {
	configured := strings.TrimSpace(os.Getenv("SUBSCRIPTION_PRODUCT_IDS"))
	if configured != "" {
		var out []string
		for _, allowed := range strings.Split(configured, ",") {
			if v := strings.TrimSpace(allowed); v != "" {
				out = append(out, v)
			}
		}
		return out, true
	}
	allowed, ok := projectIDPremiumProducts[fbapp.ProjectID()]
	return allowed, ok
}

// persistSubscriptionOwnership は現在ユーザーへの付与と旧所有者からの剥奪を
// 1トランザクションで行い、同一サブスクリプションの所有者を一意にする。
//
// 匿名ユーザーの再インストール等で uid が変わると、旧 uid の doc に
// premium とサブスク情報が残ったままになる。放置するとストア通知の
// ユーザー検索が旧 doc にヒットし、現役 doc の解約処理が漏れて
// premium が永久に残る。サブスクは常に最後に検証した uid のみに紐づける。
func persistSubscriptionOwnership(
	ctx context.Context, db *firestore.Client, userRef *firestore.DocumentRef,
	subscription map[string]any, newTier, identifierField, identifierValue string,
) error {
	ownerHash := sha256.Sum256([]byte(identifierField + "\x00" + identifierValue))
	ownerRef := db.Collection("subscription_owners").Doc(hex.EncodeToString(ownerHash[:]))
	return db.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		currentTier := "free"
		userDoc, err := tx.Get(userRef)
		if err == nil && userDoc.Exists() {
			if tier, ok := userDoc.Data()["tier"].(string); ok && tier != "" {
				currentTier = tier
			}
		} else if err != nil && !isNotFoundErr(err) {
			return err
		}
		// 同じ購入IDを検証する全トランザクションが必ず同じdocを読むため、
		// 検索結果がまだ0件でも同時付与の一方を再試行させられる。
		if _, err := tx.Get(ownerRef); err != nil && !isNotFoundErr(err) {
			return err
		}

		it := tx.Documents(db.Collection("users").Where(identifierField, "==", identifierValue))
		defer it.Stop()
		var previous []*firestore.DocumentSnapshot
		for {
			doc, err := it.Next()
			if err == iterator.Done {
				break
			}
			if err != nil {
				return err
			}
			if doc.Ref.ID != userRef.ID {
				previous = append(previous, doc)
			}
		}

		payload := map[string]any{"tier": newTier, "subscription": subscription}
		if currentTier != newTier {
			if newTier == "premium" {
				payload["remaining_sentences"] = quota.PremiumDailySentences
				payload["remaining_quizzes"] = quota.PremiumDailyQuizzes
			} else {
				payload["remaining_sentences"] = quota.FreeDailySentences
				payload["remaining_quizzes"] = quota.FreeDailyQuizzes
			}
		}
		if err := tx.Set(userRef, payload, firestore.MergeAll); err != nil {
			return err
		}
		if err := tx.Set(ownerRef, map[string]any{
			"uid": userRef.ID, "updated_at": firestore.ServerTimestamp,
		}); err != nil {
			return err
		}
		for _, doc := range previous {
			if err := tx.Update(doc.Ref, []firestore.Update{
				{Path: "tier", Value: "free"},
				{Path: "remaining_sentences", Value: quota.FreeDailySentences},
				{Path: "remaining_quizzes", Value: quota.FreeDailyQuizzes},
				{Path: "subscription", Value: firestore.Delete},
			}); err != nil {
				return err
			}
			log.Printf("Released subscription from user %s (now owned by %s)",
				doc.Ref.ID, userRef.ID)
		}
		return nil
	})
}
