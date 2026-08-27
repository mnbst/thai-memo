package function

import (
	"context"
	"log"
	"net/http"
	"sync"
	"time"

	"cloud.google.com/go/firestore"
	"google.golang.org/api/iterator"

	"github.com/mnbst/thai-memo/functions/go/internal/fbapp"
)

// subscriptionStatus は functions/javascript/src/subscriptionStatus.ts の移植。
//
// 1日1回実行し、有効期限が過ぎた premium ユーザーを free に更新する。
// Apple / Google Play の通知が遅延・未着だった場合のフォールバック。
//
// JS 版は dev だけ onRequest、tester/prod は onSchedule と関数の形自体を
// 分けていた。Go 版は常に HTTP のままで、tester/prod では Cloud Scheduler の
// ジョブ（Terraform 管理）が OIDC トークン付きで叩く。dev はジョブを作らない
// ので、手で叩いたときだけ動く点は JS 版と変わらない。

// gracePeriodMaxMs は grace_period を premium のまま維持する上限
// （constants/subscription.ts:GRACE_PERIOD_MAX_MS）。
//
// 猶予期間は Apple が最長16日、Google Play が最長30日。
// GRACE_PERIOD_EXPIRED / EXPIRED 通知を取りこぼしても、期限からこの期間を
// 過ぎた grace_period は free に落とす。
const gracePeriodMax = 30 * 24 * time.Hour

// subscriptionStatusConcurrency は JS 版の CONCURRENCY。
const subscriptionStatusConcurrency = 5

func subscriptionStatusHTTP(w http.ResponseWriter, r *http.Request) {
	if err := runSubscriptionStatus(r.Context()); err != nil {
		log.Printf("subscriptionStatus failed: %v", err)
		http.Error(w, "internal", http.StatusInternalServerError)
		return
	}
	_, _ = w.Write([]byte("ok"))
}

func runSubscriptionStatus(ctx context.Context) error {
	log.Print("subscriptionStatus started")

	db, err := fbapp.Firestore(ctx)
	if err != nil {
		return err
	}

	now := time.Now()

	// 期限切れ対象: premium かつ expires_at が過去
	it := db.Collection("users").
		Where("tier", "==", "premium").
		Where("subscription.expires_at", "<", now).
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
		log.Print("No expired subscriptions found")
		return nil
	}
	log.Printf("Found %d expired users", len(docs))

	var (
		mu      sync.Mutex
		updated int
	)

	for i := 0; i < len(docs); i += subscriptionStatusConcurrency {
		end := min(i+subscriptionStatusConcurrency, len(docs))

		var wg sync.WaitGroup
		for _, doc := range docs[i:end] {
			wg.Add(1)
			go func(doc *firestore.DocumentSnapshot) {
				defer wg.Done()
				// JS の Promise.allSettled と同じく、1件の失敗で全体を止めない。
				if err := expireUser(ctx, doc, now); err != nil {
					log.Printf("Failed to update uid=%s: %v", doc.Ref.ID, err)
					return
				}
				mu.Lock()
				updated++
				mu.Unlock()
			}(doc)
		}
		wg.Wait()
	}

	log.Printf("subscriptionStatus completed: updated=%d", updated)
	return nil
}

// expireUser は1ユーザーを free に落とす。落とす対象でなければ何もしない。
func expireUser(ctx context.Context, doc *firestore.DocumentSnapshot, now time.Time) error {
	subscription, _ := doc.Data()["subscription"].(map[string]any)
	status, _ := subscription["status"].(string)

	switch status {
	case "grace_period":
		// 猶予期間は期限超過が前提。通知を取りこぼした場合に premium が
		// 永久に残らないよう、猶予の上限を過ぎたものだけ落とす。
		expiresAt, ok := subscription["expires_at"].(time.Time)
		if !ok || now.Sub(expiresAt) <= gracePeriodMax {
			return nil
		}
	case "active", "canceled":
		// 落とす
	default:
		return nil
	}

	if _, err := doc.Ref.Set(ctx, map[string]any{
		"tier": "free",
		"subscription": map[string]any{
			"status":     "expired",
			"updated_at": firestore.ServerTimestamp,
		},
	}, firestore.MergeAll); err != nil {
		return err
	}

	log.Printf("Expired: uid=%s, status=%s", doc.Ref.ID, status)
	return nil
}
