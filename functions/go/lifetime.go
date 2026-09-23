package function

import (
	"crypto/sha256"
	"encoding/hex"
	"time"

	"cloud.google.com/go/firestore"

	"github.com/mnbst/thai-memo/functions/go/internal/appstore"
	"github.com/mnbst/thai-memo/functions/go/internal/quota"
	"github.com/mnbst/thai-memo/functions/go/internal/subscription"
)

func subscriptionOwnerRef(
	db *firestore.Client, identifierField, identifierValue string,
) *firestore.DocumentRef {
	hash := sha256.Sum256([]byte(identifierField + "\x00" + identifierValue))
	return db.Collection("subscription_owners").Doc(hex.EncodeToString(hash[:]))
}

// 買い切り（premium_lifetime / 月額からの無償移行）の権利をどう残し、どう剥がすか。
//
// 判定が verifySubscription とストア通知に分かれていると、片方だけ直したときに
// 「tier は落としたのに印が残る」「印は外したのに tier が premium のまま」という
// 半端な状態を作る。剥がす条件（lifetimeRevoked）と、剥がすときに書く内容
// （lifetimeReleaseUpdates）はここに集約する。

// lifetimeRevoked は、この通知で買い切りの権利そのものを剥がすかどうか。
//
//   - 買い切りそのものの返金・取消（通知の商品が買い切り）
//   - 無償移行で得た権利（lifetime_source=monthly_migration）の元になった
//     月額の返金・取消。入口が「月額を買って返金する」だけで済む状態にしない。
//
// 買い切りを実際に購入した人が、無関係な月額を返金しただけで買い切りまで
// 失うことはない。
func lifetimeRevoked(sub map[string]any, n *appstore.Notification) bool {
	if !isRevocationNotification(n) {
		return false
	}
	return isLifetimeProduct(n.TransactionInfo.ProductID) ||
		subscription.LifetimeSource(sub) == "monthly_migration"
}

// isRevocationNotification は権利を取り消す通知か（返金・取消）。
//
// 買い切りの権利を剥がしうるのはこの2種だけ。それ以外の通知で買い切り関連の
// 追加クエリを投げないための門番でもある（最頻の DID_RENEW で毎回 users を
// もう1回引くと、更新のたびに無駄な読み取りが1件増える）。
func isRevocationNotification(n *appstore.Notification) bool {
	return n.NotificationType == "REFUND" || n.NotificationType == "REVOKE"
}

// keepPremiumForLifetime は、買い切りの権利を持つユーザーを月額の期限切れで
// 落とさないようにする。あわせて、印そのものを外すかどうかを返す。
//
// 月額を解約すれば EXPIRED が届く。買い切りへ移行した人にとってはそれが正常な
// 流れなので、ここで free に落とすと案内文言（追加料金なしでずっと使える）と
// 食い違う。subscription.status は通知どおり expired に倒したままにして、
// tier だけ残す。
//
// 剥がすとき（lifetimeRevoked）に tier だけ落として印を残すと、そのあと月額を
// 買い直して解約するだけで premium が永久に戻る。tier と印は必ず一緒に動かす。
func keepPremiumForLifetime(
	d appStoreDecision, data map[string]any, n *appstore.Notification,
) (appStoreDecision, bool) {
	sub, _ := data["subscription"].(map[string]any)
	revoked := lifetimeRevoked(sub, n)
	if d.Tier == "free" && !revoked && subscription.IsLifetime(sub) {
		d.Tier = "premium"
	}
	return d, revoked
}

// lifetimeReleaseUpdates は買い切りの印を外す更新内容を組み立てる
// （Firestore に触らない）。
//
// 印を外したうえで、その doc に残っている記録（別に買った月額など）だけで
// premium を維持できるかを見て、維持できなければ free とクォータも落とす。
// 月額側の status / expires_at には触らない。買い切りの返金は月額の解約では
// ないので、通知の内容をそのまま月額の記録へ書き写すと状態が壊れる。
//
// 期限の見逃し幅は dailyBatch と同じ ExpiryDemotionMargin を使う。ここだけ
// 0 にすると、更新の通知がまだ届いていない月額（期限直後）を持つ人が、
// 買い切りの返金に巻き込まれて即 free に落ちる。
func lifetimeReleaseUpdates(data map[string]any, now time.Time) []firestore.Update {
	updates := []firestore.Update{
		{Path: "subscription.lifetime", Value: false},
		{Path: "subscription.lifetime_source", Value: firestore.Delete},
		{Path: "subscription.lifetime_transaction_id", Value: firestore.Delete},
		{Path: "subscription.lifetime_source_transaction_id", Value: firestore.Delete},
		{Path: "subscription.lifetime_source_purchase_token", Value: firestore.Delete},
		{Path: "subscription.updated_at", Value: firestore.ServerTimestamp},
	}

	sub, _ := data["subscription"].(map[string]any)
	stripped := make(map[string]any, len(sub))
	for k, v := range sub {
		stripped[k] = v
	}
	stripped["lifetime"] = false

	if currentTier, _ := data["tier"].(string); currentTier == "premium" &&
		!subscription.Entitled(stripped, now, subscription.ExpiryDemotionMargin) {
		sentences, quizzes := quota.Reset(false)
		updates = append(updates,
			firestore.Update{Path: "tier", Value: "free"},
			firestore.Update{Path: "remaining_sentences", Value: sentences},
			firestore.Update{Path: "remaining_quizzes", Value: quizzes},
		)
	}
	return updates
}

// lifetimeBackfillPayload は、買い切り購入者の doc に返金通知用のキー
// （lifetime_transaction_id）が無ければ補う。dailyBatch から呼ぶ。
//
// このキーは買い切り販売の途中から書き始めたので、それ以前に購入した人の doc に
// は無い。キーが無いと、そのあと月額を検証して original_transaction_id が
// 上書きされた時点で、買い切りの返金・取消がどの doc にも当たらなくなる。
//
// 対象は premium の買い切り所有者だけ。無償移行者は移行後にsubscriptionが
// 更新されていないと確認できる場合だけ移行元IDを補う。product_id / ID が既に
// 別購入で上書きされた doc は推測せず、通知時のowner fallbackに任せる。
// 全 doc が補われたらこの関数は消してよい。
func lifetimeBackfillPayload(userData map[string]any) map[string]any {
	if tier, _ := userData["tier"].(string); tier != "premium" {
		return nil
	}
	sub, _ := userData["subscription"].(map[string]any)
	if !subscription.IsLifetime(sub) {
		return nil
	}

	// 無償移行は、移行時点の月額IDを専用フィールドへ残す。既存データは
	// migrated_at より後に subscription が更新されていない場合だけ、現在のIDを
	// 移行元とみなせる。更新済みなら別購入のIDかもしれないので推測しない。
	if subscription.LifetimeSource(sub) == "monthly_migration" {
		platform, _ := sub["platform"].(string)
		migratedAt, migratedOK := sub["lifetime_migrated_at"].(time.Time)
		updatedAt, updatedOK := sub["updated_at"].(time.Time)
		if !migratedOK || !updatedOK || updatedAt.After(migratedAt) {
			return nil
		}
		switch platform {
		case "ios":
			if existing, _ := sub["lifetime_source_transaction_id"].(string); existing != "" {
				return nil
			}
			if id, _ := sub["original_transaction_id"].(string); id != "" {
				return map[string]any{"lifetime_source_transaction_id": id}
			}
		case "android":
			if existing, _ := sub["lifetime_source_purchase_token"].(string); existing != "" {
				return nil
			}
			if token, _ := sub["purchase_token"].(string); token != "" {
				return map[string]any{"lifetime_source_purchase_token": token}
			}
		}
		return nil
	}

	if subscription.LifetimeTransactionID(sub) != "" {
		return nil
	}
	productID, _ := sub["product_id"].(string)
	if !isLifetimeProduct(productID) {
		return nil
	}
	originalTxID, _ := sub["original_transaction_id"].(string)
	if originalTxID == "" {
		return nil
	}
	return map[string]any{"lifetime_transaction_id": originalTxID}
}
