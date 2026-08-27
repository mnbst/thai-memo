package function

import (
	"context"
	"encoding/json"
	"log"

	"cloud.google.com/go/firestore"
	"github.com/cloudevents/sdk-go/v2/event"
	"google.golang.org/api/iterator"

	"github.com/mnbst/thai-memo/functions/go/internal/fbapp"
	"github.com/mnbst/thai-memo/functions/go/internal/playbilling"
	"github.com/mnbst/thai-memo/functions/go/internal/quota"
)

// handlePlayNotification は
// functions/javascript/src/handlePlayNotification.ts の移植。
//
// Google Play Console で設定した Cloud Pub/Sub テーマに配信される
// サブスクリプション通知（RTDN: Real-time Developer Notifications）を受信し、
// Google Play Developer API で最新のサブスクリプション状態を再検証したうえで、
// Firestore のユーザーデータを更新する。
//
// notificationType に関わらず Play API で再検証するため、
// 個別の通知タイプごとの処理は行わない。

// messagePublishedData は Pub/Sub の CloudEvent データ。
type messagePublishedData struct {
	Message struct {
		// Data は base64 で載ってくる。[]byte は encoding/json が自動で戻す。
		Data       []byte            `json:"data"`
		Attributes map[string]string `json:"attributes"`
		MessageID  string            `json:"messageId"`
	} `json:"message"`
	Subscription string `json:"subscription"`
}

// rtdnMessage は Google Play から Pub/Sub 経由で届く通知メッセージ。
// subscriptionNotification が無い場合はテスト通知等のためスキップする。
type rtdnMessage struct {
	SubscriptionNotification *struct {
		Version          string `json:"version"`
		NotificationType int    `json:"notificationType"`
		// PurchaseToken はユーザー検索に使う
		PurchaseToken  string `json:"purchaseToken"`
		SubscriptionID string `json:"subscriptionId"`
	} `json:"subscriptionNotification"`
	PackageName string `json:"packageName"`
}

func handlePlayNotificationEvent(ctx context.Context, e event.Event) error {
	var data messagePublishedData
	if err := e.DataAs(&data); err != nil {
		return err
	}

	var message rtdnMessage
	if len(data.Message.Data) > 0 {
		if err := json.Unmarshal(data.Message.Data, &message); err != nil {
			return err
		}
	}

	if message.SubscriptionNotification == nil {
		log.Print("Non-subscription notification, skipping")
		return nil
	}
	notification := message.SubscriptionNotification

	log.Printf("RTDN: type=%d, subscriptionId=%s",
		notification.NotificationType, notification.SubscriptionID)

	return processPlayNotification(ctx, message.PackageName,
		notification.SubscriptionID, notification.PurchaseToken)
}

func processPlayNotification(
	ctx context.Context, packageName, subscriptionID, purchaseToken string,
) error {
	db, err := fbapp.Firestore(ctx)
	if err != nil {
		return err
	}

	// purchaseToken で Firestore からユーザーを検索。
	// verifySubscription で保存した purchase_token と照合する。
	// 匿名ユーザーの再インストール等で同一サブスクの doc が複数残る可能性が
	// あるため limit(1) にせず、該当する全 doc を更新する。
	it := db.Collection("users").
		Where("subscription.purchase_token", "==", purchaseToken).
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
		log.Print("No user found for purchaseToken")
		return nil
	}

	result, err := playbilling.Default.VerifyPurchase(
		ctx, packageName, subscriptionID, purchaseToken)
	if err != nil {
		// JS 版は再検証の失敗をログに落として握り潰す（Pub/Sub の再送を招かない）。
		log.Printf("Failed to verify Play purchase on RTDN: %v", err)
		return nil
	}

	// 検証結果に基づいて tier を決定（expired なら free、それ以外は premium）
	tier := "premium"
	if result.Status == playbilling.StatusExpired {
		tier = "free"
	}

	for _, doc := range docs {
		currentTier, _ := doc.Data()["tier"].(string)
		if _, err := doc.Ref.Update(ctx, playUpdates(result, tier, currentTier)); err != nil {
			return err
		}
		log.Printf("Updated user %s: tier=%s, status=%s",
			doc.Ref.ID, tier, result.Status)
	}
	return nil
}

// playUpdates は1ユーザーぶんの更新内容を組み立てる（Firestore に触らない）。
//
// ドット記法で subscription のサブフィールドのみ更新し、purchase_token 等を保持する。
func playUpdates(
	result *playbilling.VerificationResult, tier, currentTier string,
) []firestore.Update {
	isFree := tier == "free"

	updates := []firestore.Update{
		{Path: "tier", Value: tier},
		{Path: "subscription.status", Value: string(result.Status)},
		{Path: "subscription.auto_renewing", Value: result.AutoRenewing},
		{Path: "subscription.updated_at", Value: firestore.ServerTimestamp},
	}
	if result.ExpiresAt != nil {
		updates = append(updates, firestore.Update{
			Path: "subscription.expires_at", Value: *result.ExpiresAt,
		})
	} else {
		updates = append(updates, firestore.Update{
			Path: "subscription.expires_at", Value: nil,
		})
	}

	// クォータはティアが変わる時のみリセット（更新通知で誤リセットしない）
	if currentTier != tier {
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
