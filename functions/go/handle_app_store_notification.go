package function

import (
	"context"
	"encoding/json"
	"errors"
	"log"
	"net/http"

	"cloud.google.com/go/firestore"
	"google.golang.org/api/iterator"

	"github.com/mnbst/thai-memo/functions/go/internal/applejws"
	"github.com/mnbst/thai-memo/functions/go/internal/appstore"
	"github.com/mnbst/thai-memo/functions/go/internal/fbapp"
	"github.com/mnbst/thai-memo/functions/go/internal/quota"
)

// handleAppStoreNotification は
// functions/javascript/src/handleAppStoreNotification.ts の移植。
//
// Apple の App Store Server Notifications V2 からのサーバー間通知を受信し、
// サブスクリプション状態の変更を Firestore に反映する。
// 通知ペイロードは JWS 形式で署名されており、internal/applejws で検証する。
//
// **Apple は 200 レスポンスを期待するため、処理エラーでも 200 を返す。**
// 200 以外を返すとリトライが発生し、通知が重複処理される可能性がある。

func handleAppStoreNotificationHTTP(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method Not Allowed", http.StatusMethodNotAllowed)
		return
	}

	var body struct {
		SignedPayload string `json:"signedPayload"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil || body.SignedPayload == "" {
		log.Print("Missing signedPayload")
		http.Error(w, "Missing signedPayload", http.StatusBadRequest)
		return
	}

	if err := processAppStoreNotification(r.Context(), body.SignedPayload); err != nil {
		var rejected *applejws.RejectedError
		if errors.As(err, &rejected) {
			// 署名検証で弾いた。偽装通知なら正常な動作だが、本物を誤って弾いていると
			// 課金状態が一切更新されない障害になる。200 を返す以上ログでしか気付けない
			// ので、専用のイベント名で出して監視できるようにする。
			log.Printf("appstore_notification_signature_rejected reason=%q", rejected.Error())
		} else {
			log.Printf("Error processing App Store notification: %v", err)
		}
		// エラーでも200を返す（Apple のリトライを防ぐため）
	}
	_, _ = w.Write([]byte("OK"))
}

func processAppStoreNotification(ctx context.Context, signedPayload string) error {
	notification, err := appstore.Default.ParseNotification(signedPayload)
	if err != nil {
		return err
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
	it := db.Collection("users").
		Where("subscription.original_transaction_id", "==",
			notification.TransactionInfo.OriginalTransactionID).
		Documents(ctx)
	defer it.Stop()

	var docs []*firestore.DocumentSnapshot
	for {
		doc, err := it.Next()
		if err == iterator.Done {
			break
		}
		if err != nil {
			return err
		}
		docs = append(docs, doc)
	}

	if len(docs) == 0 {
		// 初回購入前の通知など
		log.Printf("No user found for originalTransactionId: %s",
			notification.TransactionInfo.OriginalTransactionID)
		return nil
	}

	decision := decideAppStoreNotification(notification)
	if !decision.Handled {
		log.Printf("Unhandled notification type: %s", notification.NotificationType)
		return nil
	}

	for _, doc := range docs {
		currentTier, _ := doc.Data()["tier"].(string)
		updates := appStoreUpdates(notification, decision, currentTier, doc.Ref.ID)

		if _, err := doc.Ref.Update(ctx, updates); err != nil {
			return err
		}
		log.Printf("Updated user %s: tier=%s, status=%s",
			doc.Ref.ID, decision.Tier, decision.Status)
	}
	return nil
}

// appStoreUpdates は1ユーザーぶんの更新内容を組み立てる（Firestore に触らない）。
//
// ドット記法で subscription のサブフィールドのみ更新し、
// original_transaction_id 等を保持する。
func appStoreUpdates(
	n *appstore.Notification, decision appStoreDecision, currentTier, uid string,
) []firestore.Update {
	isFree := decision.Tier == "free"

	updates := []firestore.Update{
		{Path: "tier", Value: decision.Tier},
		{Path: "subscription.status", Value: decision.Status},
		{Path: "subscription.auto_renewing", Value: decision.AutoRenewing},
		{Path: "subscription.updated_at", Value: firestore.ServerTimestamp},
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

	// クォータはティアが変わる時のみリセット（同一 tier の更新通知でリセットしない）
	if currentTier != decision.Tier {
		sentences, quizzes := quota.PremiumDailySentences, quota.PremiumDailyQuizzes
		if isFree {
			sentences, quizzes = quota.FreeDailySentences, quota.FreeDailyQuizzes
		}
		updates = append(updates,
			firestore.Update{Path: "remaining_sentences", Value: sentences},
			firestore.Update{Path: "remaining_quizzes", Value: quizzes},
		)
	}

	return updates
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
