package function

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net/http"
	"slices"
	"time"

	"cloud.google.com/go/firestore"
	"google.golang.org/api/iterator"

	"github.com/mnbst/thai-memo/functions/go/internal/applejws"
	"github.com/mnbst/thai-memo/functions/go/internal/appstore"
	"github.com/mnbst/thai-memo/functions/go/internal/fbapp"
	"github.com/mnbst/thai-memo/functions/go/internal/quota"
	"github.com/mnbst/thai-memo/functions/go/internal/subscription"
)

const appStoreNotificationMaxBodyBytes int64 = 1 << 20

// handleAppStoreNotification は
// functions/javascript/src/handleAppStoreNotification.ts の移植。
//
// Apple の App Store Server Notifications V2 からのサーバー間通知を受信し、
// サブスクリプション状態の変更を Firestore に反映する。
// 通知ペイロードは JWS 形式で署名されており、internal/applejws で検証する。
//
// 署名不正など再試行しても直らない入力は 200 で破棄する。
// Firestore 等の一時障害は 5xx を返し、Apple に再送させる。

func handleAppStoreNotificationHTTP(w http.ResponseWriter, r *http.Request) {
	handleAppStoreNotificationWithProcessor(w, r, processAppStoreNotification)
}

type appStoreNotificationProcessor func(context.Context, string) error

func handleAppStoreNotificationWithProcessor(
	w http.ResponseWriter, r *http.Request, process appStoreNotificationProcessor,
) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method Not Allowed", http.StatusMethodNotAllowed)
		return
	}

	r.Body = http.MaxBytesReader(w, r.Body, appStoreNotificationMaxBodyBytes)
	decoder := json.NewDecoder(r.Body)
	var body struct {
		SignedPayload string `json:"signedPayload"`
	}
	if err := decoder.Decode(&body); err != nil || body.SignedPayload == "" {
		log.Print("Missing signedPayload")
		http.Error(w, "Missing signedPayload", http.StatusBadRequest)
		return
	}
	if err := decoder.Decode(&struct{}{}); err != io.EOF {
		http.Error(w, "Invalid JSON", http.StatusBadRequest)
		return
	}

	if err := process(r.Context(), body.SignedPayload); err != nil {
		var rejected *applejws.RejectedError
		if errors.As(err, &rejected) {
			// 署名検証で弾いた。偽装通知なら正常な動作だが、本物を誤って弾いていると
			// 課金状態が一切更新されない障害になる。200 を返す以上ログでしか気付けない
			// ので、専用のイベント名で出して監視できるようにする。
			log.Printf("appstore_notification_signature_rejected reason=%q", rejected.Error())
			_, _ = w.Write([]byte("OK"))
			return
		} else {
			log.Printf("Error processing App Store notification: %v", err)
			http.Error(w, "internal", http.StatusInternalServerError)
			return
		}
	}
	_, _ = w.Write([]byte("OK"))
}

func processAppStoreNotification(ctx context.Context, signedPayload string) error {
	notification, err := appstore.Default.ParseNotification(signedPayload)
	if err != nil {
		return err
	}
	// 販売商品を特定できない（GCLOUD_PROJECT 欠落・設定漏れ）のは通知側の
	// 問題ではない。ここで RejectedError にすると 200 で捨てられ Apple が
	// 再送しないまま課金状態が永久にずれるので、5xx を返して再送させる。
	allowedProducts, resolved := subscriptionProductAllowlist()
	if !resolved {
		return fmt.Errorf(
			"subscription_product_allowlist_unresolved project=%q", fbapp.ProjectID())
	}
	if !slices.Contains(allowedProducts, notification.TransactionInfo.ProductID) {
		return &applejws.RejectedError{Err: fmt.Errorf(
			"App Store notification product mismatch: %q",
			notification.TransactionInfo.ProductID)}
	}
	if notification.RenewalInfo != nil && notification.RenewalInfo.ProductID != "" &&
		notification.RenewalInfo.ProductID != notification.TransactionInfo.ProductID {
		return &applejws.RejectedError{Err: errors.New(
			"App Store notification transaction/renewal product mismatch")}
	}

	subtype := notification.Subtype
	if subtype == "" {
		subtype = "none"
	}
	log.Printf("App Store Notification: type=%s, subtype=%s, originalTxId=%s",
		notification.NotificationType, subtype,
		notification.TransactionInfo.OriginalTransactionID)

	db, err := fbapp.Firestore(ctx)
	if err != nil {
		return err
	}

	// originalTransactionId でユーザーを検索。
	// 匿名ユーザーの再インストール等で同一サブスクの doc が複数残る可能性が
	// あるため limit(1) にせず、該当する全 doc を更新する。
	originalTxID := notification.TransactionInfo.OriginalTransactionID
	docs, err := findUsersBySubscriptionField(
		ctx, db, "subscription.original_transaction_id", originalTxID)
	if err != nil {
		return err
	}

	// 買い切りのあとに月額を検証すると original_transaction_id は月額側で
	// 上書きされる。買い切りぶんの返金・取消がどの doc にも当たらなくなるので、
	// 検証時に残した lifetime_transaction_id でも引く。
	// 権利を剥がす通知でしか使わないので、それ以外では引かない（更新通知の
	// たびに users をもう1回読むのを避ける）。
	var lifetimeOnly []*firestore.DocumentSnapshot
	if isRevocationNotification(notification) {
		lifetimeOnly, err = findLifetimeOnlyUsers(
			ctx, db, originalTxID, notification.TransactionInfo.ProductID, docs)
		if err != nil {
			return err
		}
	}

	if len(docs) == 0 && len(lifetimeOnly) == 0 {
		// 初回購入前の通知など
		log.Printf("No user found for originalTransactionId: %s", originalTxID)
		return nil
	}

	if err := revokeLifetimeForUsers(
		ctx, lifetimeOnly, notification, time.Now()); err != nil {
		return err
	}

	decision := decideAppStoreNotification(notification)
	if !decision.Handled {
		log.Printf("Unhandled notification type: %s", notification.NotificationType)
		return nil
	}

	for _, doc := range docs {
		if !isNewerAppStoreNotification(doc.Data(), notification.SignedDate) {
			log.Printf("Skipping stale App Store notification for user %s", doc.Ref.ID)
			continue
		}
		currentTier, _ := doc.Data()["tier"].(string)
		d, lifetimeRevoked := keepPremiumForLifetime(decision, doc.Data(), notification)
		updates := appStoreUpdates(
			notification, d, currentTier, doc.Ref.ID, lifetimeRevoked)

		// 読み取り後に新しい通知が反映されていた場合は上書きせず、Apple の
		// リトライで最新スナップショットから判定し直す。
		if _, err := doc.Ref.Update(ctx, updates,
			firestore.LastUpdateTime(doc.UpdateTime)); err != nil {
			return err
		}
		log.Printf("Updated user %s: tier=%s, status=%s",
			doc.Ref.ID, d.Tier, d.Status)
	}
	return nil
}

// findUsersBySubscriptionField は subscription の識別子で users を引く。
func findUsersBySubscriptionField(
	ctx context.Context, db *firestore.Client, field, value string,
) ([]*firestore.DocumentSnapshot, error) {
	if value == "" {
		return nil, nil
	}
	it := db.Collection("users").Where(field, "==", value).Documents(ctx)
	defer it.Stop()

	var docs []*firestore.DocumentSnapshot
	for {
		doc, err := it.Next()
		if err == iterator.Done {
			break
		}
		if err != nil {
			return nil, err
		}
		docs = append(docs, doc)
	}
	return docs, nil
}

// findLifetimeOnlyUsers は「買い切りの記録は持つが、いまの
// original_transaction_id は別（月額を後から検証した）」doc を返す。
// 購入した買い切りIDと、無償移行の根拠になった月額IDの両方を引く。
func findLifetimeOnlyUsers(
	ctx context.Context, db *firestore.Client, originalTxID, productID string,
	primary []*firestore.DocumentSnapshot,
) ([]*firestore.DocumentSnapshot, error) {
	if originalTxID == "" {
		return nil, nil
	}
	seen := make(map[string]bool, len(primary))
	for _, doc := range primary {
		seen[doc.Ref.ID] = true
	}
	var out []*firestore.DocumentSnapshot
	for _, field := range []string{
		"subscription.lifetime_transaction_id",
		"subscription.lifetime_source_transaction_id",
	} {
		docs, err := findUsersBySubscriptionField(ctx, db, field, originalTxID)
		if err != nil {
			return nil, err
		}
		for _, doc := range docs {
			if !seen[doc.Ref.ID] {
				seen[doc.Ref.ID] = true
				out = append(out, doc)
			}
		}
	}

	// フィールド導入前にIDを別の月額で上書き済みでも、購入検証時の
	// subscription_owners には元のID→uidが残る。返金通知でそのuidを最後の
	// フォールバックとして引き、旧データでも権利を剥がせるようにする。
	ownerDoc, err := subscriptionOwnerRef(
		db, "subscription.original_transaction_id", originalTxID).Get(ctx)
	if err == nil && ownerDoc.Exists() {
		uid, _ := ownerDoc.Data()["uid"].(string)
		if uid != "" && !seen[uid] {
			userDoc, err := db.Collection("users").Doc(uid).Get(ctx)
			if err == nil && userDoc.Exists() {
				sub, _ := userDoc.Data()["subscription"].(map[string]any)
				lifetimeID, _ := sub["lifetime_transaction_id"].(string)
				sourceID, _ := sub["lifetime_source_transaction_id"].(string)
				matchesDirect := isLifetimeProduct(productID) &&
					subscription.LifetimeSource(sub) != "monthly_migration" &&
					(lifetimeID == "" || lifetimeID == originalTxID)
				// 無償移行の旧データでsourceIDが無い場合、ownerRefが移行後に
				// 検証した別月額を指す可能性がある。空IDからは推測して剥がさない。
				matchesMigration := !isLifetimeProduct(productID) &&
					subscription.LifetimeSource(sub) == "monthly_migration" &&
					sourceID == originalTxID
				if subscription.IsLifetime(sub) && (matchesDirect || matchesMigration) {
					out = append(out, userDoc)
				}
			} else if err != nil && !isNotFoundErr(err) {
				return nil, err
			}
		}
	} else if err != nil && !isNotFoundErr(err) {
		return nil, err
	}
	return out, nil
}

// revokeLifetimeForUsers は買い切りの返金・取消を、いまは月額の記録を持って
// いる doc へ適用する。
//
// 通知は買い切りについてのものなので、月額側の status / expires_at には触らない。
// 買い切りの印だけを外し、月額の権利が残っていなければ free に落とす。
// 冪等なので、順序逆転を見る notification_signed_at の判定は通さない
// （通す場合、あとから届いた月額の通知に隠されて印が外れないままになる）。
func revokeLifetimeForUsers(
	ctx context.Context, docs []*firestore.DocumentSnapshot,
	n *appstore.Notification, now time.Time,
) error {
	if len(docs) == 0 {
		return nil
	}
	if !isRevocationNotification(n) {
		return nil
	}
	for _, doc := range docs {
		sub, _ := doc.Data()["subscription"].(map[string]any)
		if !subscription.IsLifetime(sub) || !lifetimeRevoked(sub, n) {
			continue
		}
		updates := lifetimeReleaseUpdates(doc.Data(), now)
		if _, err := doc.Ref.Update(ctx, updates,
			firestore.LastUpdateTime(doc.UpdateTime)); err != nil {
			return err
		}
		log.Printf("Revoked lifetime for user %s (%s)", doc.Ref.ID, n.NotificationType)
	}
	return nil
}

// appStoreUpdates は1ユーザーぶんの更新内容を組み立てる（Firestore に触らない）。
//
// ドット記法で subscription のサブフィールドのみ更新し、
// original_transaction_id 等を保持する。
func appStoreUpdates(
	n *appstore.Notification, decision appStoreDecision, currentTier, uid string,
	lifetimeRevoked bool,
) []firestore.Update {
	isFree := decision.Tier == "free"

	updates := []firestore.Update{
		{Path: "tier", Value: decision.Tier},
		{Path: "subscription.status", Value: decision.Status},
		{Path: "subscription.auto_renewing", Value: decision.AutoRenewing},
		{Path: "subscription.updated_at", Value: firestore.ServerTimestamp},
	}
	if n.SignedDate != nil {
		updates = append(updates, firestore.Update{
			Path:  "subscription.notification_signed_at",
			Value: millisToTime(*n.SignedDate),
		})
	}

	// expires_at は premium の期限切れフォールバック（dailyBatch /
	// subscriptionStatus）の判定材料。premium のまま null で上書きすると
	// 期限判定が効かなくなるため、値が無い premium 通知では既存値を残す。
	switch {
	case n.TransactionInfo.ExpiresDate != nil:
		updates = append(updates, firestore.Update{
			Path:  "subscription.expires_at",
			Value: millisToTime(*n.TransactionInfo.ExpiresDate),
		})
	case isFree:
		updates = append(updates, firestore.Update{
			Path: "subscription.expires_at", Value: nil,
		})
	default:
		log.Printf("No expiresDate in %s notification; keeping existing expires_at for user %s",
			n.NotificationType, uid)
	}

	// 権利を剥がすときは印も一緒に消す（判定は lifetimeRevoked）。tier だけ
	// 落として印を残すと、そのあと月額を買い直して解約するだけで premium が
	// 永久に戻る。
	if lifetimeRevoked {
		updates = append(updates,
			firestore.Update{Path: "subscription.lifetime", Value: false},
			firestore.Update{Path: "subscription.lifetime_source", Value: firestore.Delete},
			firestore.Update{
				Path: "subscription.lifetime_transaction_id", Value: firestore.Delete},
			firestore.Update{
				Path: "subscription.lifetime_source_transaction_id", Value: firestore.Delete},
			firestore.Update{
				Path: "subscription.lifetime_source_purchase_token", Value: firestore.Delete},
		)
	}

	// クォータはティアが変わる時のみリセット（同一 tier の更新通知でリセットしない）
	if currentTier != decision.Tier {
		sentences, quizzes := quota.Reset(!isFree)
		updates = append(updates,
			firestore.Update{Path: "remaining_sentences", Value: sentences},
			firestore.Update{Path: "remaining_quizzes", Value: quizzes},
		)
	}

	return updates
}

// isNewerAppStoreNotification は再送・順序逆転した通知で新しい状態を巻き戻さない。
// 既存データや古いテスト通知に signedDate が無い場合は互換性のため処理する。
func isNewerAppStoreNotification(data map[string]any, incoming *int64) bool {
	if incoming == nil {
		return true
	}
	subscription, _ := data["subscription"].(map[string]any)
	last, ok := subscription["notification_signed_at"].(time.Time)
	if !ok {
		return true
	}
	return *incoming > last.UnixMilli()
}

// appStoreDecision は通知タイプから決まるサブスクリプション状態。
type appStoreDecision struct {
	Tier         string // premium / free
	Status       string // active / canceled / expired / grace_period
	AutoRenewing bool
	// Handled が false なら未対応の通知タイプ（何も書かずに 200 を返す）。
	Handled bool
}

// decideAppStoreNotification は通知タイプに応じてサブスクリプション状態を決める。
//
// 対応する通知タイプ:
//   - SUBSCRIBED               : 新規登録 → premium / active
//   - DID_RENEW                : 自動更新成功 → premium / active
//   - BILLING_RECOVERY         : 猶予期間後の課金回復 → premium / active
//   - DID_CHANGE_RENEWAL_INFO  : 更新情報変更 → premium、autoRenewStatus=0 なら canceled
//   - DID_CHANGE_RENEWAL_STATUS: 自動更新ON/OFF → premium / active or canceled
//   - EXPIRED / REVOKE / REFUND: → free / expired
//   - GRACE_PERIOD_EXPIRED     : 猶予期間終了 → free / expired
//   - DID_FAIL_TO_RENEW        : GRACE_PERIOD なら premium / grace_period、他は free / expired
func decideAppStoreNotification(n *appstore.Notification) appStoreDecision {
	autoRenewing := n.RenewalInfo != nil && n.RenewalInfo.AutoRenewStatus == 1
	autoRenewOff := n.RenewalInfo != nil && n.RenewalInfo.AutoRenewStatus == 0

	d := appStoreDecision{AutoRenewing: autoRenewing, Handled: true}

	switch n.NotificationType {
	case "DID_RENEW", "BILLING_RECOVERY", "SUBSCRIBED":
		d.Tier, d.Status = "premium", "active"

	case "EXPIRED", "REVOKE", "REFUND", "GRACE_PERIOD_EXPIRED":
		d.Tier, d.Status = "free", "expired"

	case "DID_CHANGE_RENEWAL_STATUS":
		// 自動更新OFF → 現在の期限まで premium を維持、期限後に free になる
		d.Tier = "premium"
		if autoRenewOff {
			d.Status = "canceled"
		} else {
			d.Status = "active"
		}

	case "DID_CHANGE_RENEWAL_INFO":
		// 解約後にも届くため、autoRenewStatus を見て canceled を維持する
		d.Tier = "premium"
		if autoRenewOff {
			d.Status = "canceled"
		} else {
			d.Status = "active"
		}

	case "DID_FAIL_TO_RENEW":
		if n.Subtype == "GRACE_PERIOD" {
			// 猶予期間中 → まだ premium を維持（支払い回復の可能性あり）
			d.Tier, d.Status = "premium", "grace_period"
		} else {
			d.Tier, d.Status = "free", "expired"
		}

	default:
		d.Handled = false
	}

	return d
}
