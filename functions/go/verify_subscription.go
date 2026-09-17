package function

import (
	"context"
	"errors"
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
	"github.com/mnbst/thai-memo/functions/go/internal/subscription"
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
		subscription = subscriptionRecord("android", productID, purchaseToken)
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
		if res.OriginalTransactionID == "" {
			return nil, errors.New("App Store originalTransactionId is empty")
		}
		status = string(res.Status)
		if res.ExpiresAt != nil {
			t := time.UnixMilli(*res.ExpiresAt).UTC()
			expiresAt = &t
		}
		autoRenewing = res.AutoRenewing
		identifierField = "subscription.original_transaction_id"
		identifierValue = res.OriginalTransactionID
		subscription = subscriptionRecord("ios", productID, res.OriginalTransactionID)
	}

	newTier := "premium"
	if status == "expired" {
		newTier = "free"
	}
	verifiedLifetime := isLifetimeProduct(productID)
	applyVerifiedLifetimeState(subscription, verifiedLifetime, newTier)

	subscription["status"] = status
	subscription["auto_renewing"] = autoRenewing
	subscription["updated_at"] = firestore.ServerTimestamp
	if expiresAt != nil {
		subscription["expires_at"] = *expiresAt
	} else {
		subscription["expires_at"] = nil
	}

	appliedTier, err := persistSubscriptionOwnership(ctx, db, userRef, subscription,
		newTier, verifiedLifetime, identifierField, identifierValue)
	if err != nil {
		return nil, err
	}

	out := map[string]any{
		"plan":       appliedTier,
		"expires_at": nil,
		"status":     status,
	}
	if expiresAt != nil {
		out["expires_at"] = expiresAt.UTC().Format(isoMillisLayout)
	}
	return out, nil
}

// verifiedTier は検証結果の tier に、doc に残っている権利を重ねて最終的な
// tier を決める。
//
// 買い切りを持っている人は、月額（期限切れ）の検証では free に落とさない。
// 復元では買い切りと過去の月額が同時に流れてきて検証の順序が定まらず、月額が
// 後着すると買い切り購入者が free で固定される（free から premium へ戻す経路は
// この関数だけで、日次バッチでもストア通知でも戻らない）。
// ストア通知側の keepPremiumForLifetime と同じ扱いに揃える。
func verifiedTier(newTier string, verifiedLifetime bool, currentSub map[string]any) string {
	if newTier == "free" && !verifiedLifetime && subscription.IsLifetime(currentSub) {
		return "premium"
	}
	return newTier
}

// subscriptionRecord は verifySubscription が Firestore へ書くサブスク記録。
// identifier はストア通知でユーザーを引くためのキー（Play は purchaseToken、
// App Store は originalTransactionId）。
//
// lifetime（期限切れフォールバックに「expires_at が無くても落とすな」と
// 伝える目印）は、買い切りを検証したときだけ true を書く。月額の検証で
// false を書くと、買い切り購入者・無償移行者の自動更新ぶんが検証された
// 時点で印が消え、そのあと解約したときに free へ落ちてしまう。印を外すのは
// 買い切りそのものの返金・取消（REFUND / REVOKE 通知）だけ。
func subscriptionRecord(platform, productID, identifier string) map[string]any {
	record := map[string]any{
		"product_id": productID,
		"platform":   platform,
	}
	if platform == "android" {
		record["purchase_token"] = identifier
	} else {
		record["original_transaction_id"] = identifier
	}
	if isLifetimeProduct(productID) {
		record["lifetime"] = true
		// 買い切りの返金・取消（REFUND / REVOKE）通知を引くためのキー。
		// original_transaction_id はそのあと月額を検証すると上書きされるので、
		// 買い切りぶんは別フィールドに残しておかないと通知がどの doc にも
		// ヒットせず、返金しても印が外れないまま premium が残る。
		record["lifetime_transaction_id"] = identifier
	}
	return record
}

func applyVerifiedLifetimeState(record map[string]any, lifetime bool, tier string) {
	if !lifetime || tier != "free" {
		return
	}
	// 返金済みの買い切りを再検証しても、権利の印を復活させない。
	// 月額を後から検証すると MergeAll で未指定フィールドが残るため、
	// false / nil を明示しないと月額終了時に永久 premium へ戻ってしまう。
	record["lifetime"] = false
	record["lifetime_source"] = nil
	record["lifetime_transaction_id"] = nil
}

// combineLifetimeVerification は、買い切り検証と別に有効な月額レコードがある場合、
// 月額側を主レコードとして残し、買い切りの印だけを重ねる。
// 単一 subscription map でも検証順（monthly→lifetime / lifetime→monthly）に
// よって片方の権利が消えないようにする。
func combineLifetimeVerification(
	record map[string]any, newTier string, currentSub map[string]any, now time.Time,
) (map[string]any, string) {
	productID, _ := currentSub["product_id"].(string)
	if productID == "" || isLifetimeProduct(productID) ||
		!subscription.IsStorePlatform(currentSub["platform"]) {
		return record, newTier
	}

	out := make(map[string]any, len(currentSub)+4)
	for k, v := range currentSub {
		out[k] = v
	}
	incomingID, _ := record["lifetime_transaction_id"].(string)
	if incomingID == "" {
		// 無効な買い切りは applyVerifiedLifetimeState が印を消しているため、
		// 照合には検証済み original_transaction_id を使う。
		incomingID, _ = record["original_transaction_id"].(string)
	}
	if newTier == "premium" {
		out["lifetime"] = true
		out["lifetime_transaction_id"] = incomingID
		// 実購入を持つようになったので、無償移行由来ではなく購入由来にする。
		out["lifetime_source"] = nil
		out["lifetime_source_transaction_id"] = nil
		out["lifetime_source_purchase_token"] = nil
		return out, "premium"
	}

	// 無効な買い切りを検証した場合も、同じ取引の印だけを外す。別の買い切りや
	// 無償移行の権利を、無関係なトークンで巻き添えにしない。
	currentID, _ := currentSub["lifetime_transaction_id"].(string)
	if incomingID != "" && currentID == incomingID {
		out["lifetime"] = false
		out["lifetime_transaction_id"] = nil
	}
	if subscription.IsLifetime(out) ||
		subscription.Entitled(out, now, subscription.ExpiryDemotionMargin) {
		return out, "premium"
	}
	return out, "free"
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
	record map[string]any, newTier string, verifiedLifetime bool,
	identifierField, identifierValue string,
) (string, error) {
	ownerRef := subscriptionOwnerRef(db, identifierField, identifierValue)
	appliedTier := newTier
	err := db.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		appliedTier = newTier
		currentTier := "free"
		var currentSub map[string]any
		userDoc, err := tx.Get(userRef)
		if err == nil && userDoc.Exists() {
			if tier, ok := userDoc.Data()["tier"].(string); ok && tier != "" {
				currentTier = tier
			}
			currentSub, _ = userDoc.Data()["subscription"].(map[string]any)
		} else if err != nil && !isNotFoundErr(err) {
			return err
		}

		recordToWrite := record
		appliedTier = verifiedTier(newTier, verifiedLifetime, currentSub)
		if verifiedLifetime {
			recordToWrite, appliedTier = combineLifetimeVerification(
				record, newTier, currentSub, time.Now())
		}
		// 同じ購入IDを検証する全トランザクションが必ず同じdocを読むため、
		// 検索結果がまだ0件でも同時付与の一方を再試行させられる。
		var previousOwnerUID string
		ownerDoc, err := tx.Get(ownerRef)
		if err == nil && ownerDoc.Exists() {
			previousOwnerUID, _ = ownerDoc.Data()["uid"].(string)
		} else if err != nil && !isNotFoundErr(err) {
			return err
		}

		it := tx.Documents(db.Collection("users").Where(identifierField, "==", identifierValue))
		defer it.Stop()
		var previous []*firestore.DocumentSnapshot
		previousIDs := map[string]bool{}
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
				previousIDs[doc.Ref.ID] = true
			}
		}

		// 買い切りのあとに月額を検証すると original_transaction_id は月額側に
		// 上書きされる。その状態の旧所有者も lifetime_transaction_id で拾う。
		// 月額レコード自体はその人の別の購入なので、下では買い切り印だけ外す。
		var lifetimePrevious []*firestore.DocumentSnapshot
		if verifiedLifetime {
			lifetimeIt := tx.Documents(db.Collection("users").Where(
				"subscription.lifetime_transaction_id", "==", identifierValue))
			defer lifetimeIt.Stop()
			for {
				doc, err := lifetimeIt.Next()
				if err == iterator.Done {
					break
				}
				if err != nil {
					return err
				}
				if doc.Ref.ID != userRef.ID && !previousIDs[doc.Ref.ID] {
					lifetimePrevious = append(lifetimePrevious, doc)
				}
			}

			// フィールド導入前に買い切りIDを月額で上書き済みの旧docは、上の
			// 2クエリでは見つからない。所有権docのuidを最後の手掛かりにする。
			if previousOwnerUID != "" && previousOwnerUID != userRef.ID &&
				!previousIDs[previousOwnerUID] {
				alreadyFound := false
				for _, doc := range lifetimePrevious {
					alreadyFound = alreadyFound || doc.Ref.ID == previousOwnerUID
				}
				if !alreadyFound {
					oldDoc, err := tx.Get(db.Collection("users").Doc(previousOwnerUID))
					if err == nil && oldDoc.Exists() {
						oldSub, _ := oldDoc.Data()["subscription"].(map[string]any)
						oldID, _ := oldSub["lifetime_transaction_id"].(string)
						if subscription.IsLifetime(oldSub) &&
							subscription.LifetimeSource(oldSub) != "monthly_migration" &&
							(oldID == "" || oldID == identifierValue) {
							lifetimePrevious = append(lifetimePrevious, oldDoc)
						}
					} else if err != nil && !isNotFoundErr(err) {
						return err
					}
				}
			}
		}

		payload := map[string]any{"tier": appliedTier, "subscription": recordToWrite}
		if currentTier != appliedTier {
			payload["remaining_sentences"], payload["remaining_quizzes"] =
				quota.Reset(appliedTier == "premium")
		}
		if err := tx.Set(userRef, payload, firestore.MergeAll); err != nil {
			return err
		}
		// 返金済み買い切りの再検証で owner を呼出元へ付け替えない。
		// 付け替えると、後続の返金通知が呼出元の別の買い切り権利を誤って剥がす。
		if !(verifiedLifetime && newTier == "free") {
			if err := tx.Set(ownerRef, map[string]any{
				"uid": userRef.ID, "updated_at": firestore.ServerTimestamp,
			}); err != nil {
				return err
			}
		}
		for _, doc := range previous {
			freeSentences, freeQuizzes := quota.Reset(false)
			if err := tx.Update(doc.Ref, []firestore.Update{
				{Path: "tier", Value: "free"},
				{Path: "remaining_sentences", Value: freeSentences},
				{Path: "remaining_quizzes", Value: freeQuizzes},
				{Path: "subscription", Value: firestore.Delete},
			}); err != nil {
				return err
			}
			log.Printf("Released subscription from user %s (now owned by %s)",
				doc.Ref.ID, userRef.ID)
		}
		for _, doc := range lifetimePrevious {
			if err := tx.Update(doc.Ref, lifetimeReleaseUpdates(doc.Data(), time.Now())); err != nil {
				return err
			}
			log.Printf("Released lifetime purchase from user %s (now owned by %s)",
				doc.Ref.ID, userRef.ID)
		}
		return nil
	})
	if err != nil {
		return "", err
	}
	return appliedTier, nil
}
