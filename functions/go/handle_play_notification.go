package function

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"time"

	"cloud.google.com/go/firestore"
	"github.com/cloudevents/sdk-go/v2/event"

	"github.com/mnbst/thai-memo/functions/go/internal/fbapp"
	"github.com/mnbst/thai-memo/functions/go/internal/playbilling"
	"github.com/mnbst/thai-memo/functions/go/internal/quota"
	"github.com/mnbst/thai-memo/functions/go/internal/subscription"
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
	// VoidedPurchaseNotification は返金・取消。買い切りの権利を剥がすのに使う。
	VoidedPurchaseNotification *voidedPurchase `json:"voidedPurchaseNotification"`
	PackageName                string          `json:"packageName"`
}

// voidedPurchase は返金・取消された購入。ProductType は 1=定期購入, 2=一時購入。
type voidedPurchase struct {
	PurchaseToken string `json:"purchaseToken"`
	ProductType   int    `json:"productType"`
}

const playProductTypeOneTime = 2

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

	if v := message.VoidedPurchaseNotification; v != nil {
		log.Printf("RTDN voided: productType=%d", v.ProductType)
		return revokePlayLifetime(ctx, v)
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
	docs, err := findUsersBySubscriptionField(
		ctx, db, "subscription.purchase_token", purchaseToken)
	if err != nil {
		return err
	}

	result, err := playbilling.Default.VerifyPurchase(
		ctx, packageName, subscriptionID, purchaseToken)
	if err != nil {
		log.Printf("Failed to verify Play purchase on RTDN: %v", err)
		// エラーを Eventarc/Pub/Sub へ返し、一時的な Play API 障害なら再送させる。
		return fmt.Errorf("Play purchase verification failed: %w", err)
	}

	// 月額↔年額の切り替えでは新しいトークンが発行され、linkedPurchaseToken が
	// 元のトークンを指す。アプリが新しいトークンを検証する前（または検証に
	// 失敗したまま）でも、元のトークンの持ち主を新しい購読へ付け替える。
	// 付け替えないと、元のトークンの失効通知で free に落ちたまま戻らない。
	replaced := false
	if len(docs) == 0 && result.LinkedPurchaseToken != "" {
		docs, err = findUsersBySubscriptionField(
			ctx, db, "subscription.purchase_token", result.LinkedPurchaseToken)
		if err != nil {
			return err
		}
		replaced = len(docs) > 0
	}
	if len(docs) == 0 {
		// 初回購入の検証前に届いた通知など
		log.Print("No user found for purchaseToken")
		return nil
	}

	// 検証結果に基づいて tier を決定（expired なら free、それ以外は premium）
	tier := "premium"
	if result.Status == playbilling.StatusExpired {
		tier = "free"
	}

	for _, doc := range docs {
		currentTier, _ := doc.Data()["tier"].(string)
		// 買い切りへ移行済みなら、月額の期限切れでは落とさない。
		// Play の通知は返金と期限切れを status で区別できない（どちらも
		// expired になる）ので、Android は期限切れ側に寄せて維持する。
		userTier := tier
		if userTier == "free" {
			sub, _ := doc.Data()["subscription"].(map[string]any)
			if subscription.IsLifetime(sub) {
				userTier = "premium"
			}
		}
		updates := playUpdates(result, userTier, currentTier)
		if replaced {
			updates = append(updates,
				firestore.Update{Path: "subscription.purchase_token", Value: purchaseToken},
				firestore.Update{Path: "subscription.product_id", Value: subscriptionID},
			)
		}
		if _, err := doc.Ref.Update(ctx, updates,
			firestore.LastUpdateTime(doc.UpdateTime)); err != nil {
			return err
		}
		log.Printf("Updated user %s: tier=%s, status=%s",
			doc.Ref.ID, userTier, result.Status)
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
		sentences, quizzes := quota.Reset(!isFree)
		updates = append(updates,
			firestore.Update{Path: "remaining_sentences", Value: sentences},
			firestore.Update{Path: "remaining_quizzes", Value: quizzes},
		)
	}

	return updates
}

// revokePlayLifetime は返金・取消された購入に紐づく買い切りの権利を剥がす。
//
// App Store の REFUND / REVOKE と同じ扱いにそろえる（lifetimeRevoked 参照）。
//   - 一時購入: 買い切りそのものの返金
//   - 定期購入: 無償移行（monthly_migration）の元になった月額の返金
//
// 定期購入そのものの失効は SUBSCRIPTION_REVOKED が別に届き、
// processPlayNotification が再検証して落とす。
func revokePlayLifetime(ctx context.Context, v *voidedPurchase) error {
	if v.PurchaseToken == "" {
		return nil
	}
	db, err := fbapp.Firestore(ctx)
	if err != nil {
		return err
	}

	oneTime := v.ProductType == playProductTypeOneTime
	field := "subscription.lifetime_source_purchase_token"
	if oneTime {
		field = "subscription.lifetime_transaction_id"
	}
	docs, err := findUsersBySubscriptionField(ctx, db, field, v.PurchaseToken)
	if err != nil {
		return err
	}

	now := time.Now()
	for _, doc := range docs {
		sub, _ := doc.Data()["subscription"].(map[string]any)
		migrated := subscription.LifetimeSource(sub) == "monthly_migration"
		if !subscription.IsLifetime(sub) || migrated == oneTime {
			continue
		}
		if _, err := doc.Ref.Update(ctx, lifetimeReleaseUpdates(doc.Data(), now),
			firestore.LastUpdateTime(doc.UpdateTime)); err != nil {
			return err
		}
		log.Printf("Revoked Play lifetime for user %s", doc.Ref.ID)
	}
	return nil
}
