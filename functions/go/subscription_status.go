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
	if r.Method != http.MethodPost {
		http.Error(w, "Method Not Allowed", http.StatusMethodNotAllowed)
		return
	}
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

	jobs := make(chan *firestore.DocumentSnapshot, subscriptionStatusConcurrency)
	var wg sync.WaitGroup
	for range subscriptionStatusConcurrency {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for doc := range jobs {
				// JS の Promise.allSettled と同じく、1件の失敗で全体を止めない。
				if err := expireUser(ctx, db, doc, now); err != nil {
					log.Printf("Failed to update uid=%s: %v", doc.Ref.ID, err)
					continue
				}
				mu.Lock()
				updated++
				mu.Unlock()
			}
		}()
	}
	for _, doc := range docs {
		jobs <- doc
	}
	close(jobs)
	wg.Wait()

	log.Printf("subscriptionStatus completed: updated=%d", updated)
	return nil
}

// expireUser は1ユーザーを free に落とす。落とす対象でなければ何もしない。
//
// クエリのスナップショットに LastUpdateTime を効かせると、同時刻起動の
// dailyBatch が全ユーザー doc を書き直す（resetQuota）せいで前提条件が外れ、
// 降格が丸ごと落ちる。トランザクション内で読み直して判定し、競合時は
// Firestore 側の再試行に任せる。
func expireUser(
	ctx context.Context, db *firestore.Client,
	doc *firestore.DocumentSnapshot, now time.Time,
) error {
	var status string
	if err := db.RunTransaction(ctx, func(
		ctx context.Context, tx *firestore.Transaction,
	) error {
		status = ""
		snap, err := tx.Get(doc.Ref)
		if isNotFoundErr(err) {
			return nil
		}
		if err != nil {
			return err
		}

		// クエリ条件（tier==premium かつ expires_at が過去）を読み直した値で
		// 再確認する。読み取り後にストア通知で更新されていた doc を、古い
		// スナップショットの判断で free に落とさない。
		if tier, _ := snap.Data()["tier"].(string); tier != "premium" {
			return nil
		}
		subscription, _ := snap.Data()["subscription"].(map[string]any)
		status, _ = subscription["status"].(string)
		expiresAt, hasExpiresAt := subscription["expires_at"].(time.Time)
		if !hasExpiresAt || !expiresAt.Before(now) {
			status = ""
			return nil
		}

		switch status {
		case "grace_period":
			// 猶予期間は期限超過が前提。通知を取りこぼした場合に premium が
			// 永久に残らないよう、猶予の上限を過ぎたものだけ落とす。
			if now.Sub(expiresAt) <= gracePeriodMax {
				status = ""
				return nil
			}
		case "active", "canceled":
			// 落とす
		default:
			status = ""
			return nil
		}

		return tx.Update(doc.Ref, []firestore.Update{
			{Path: "tier", Value: "free"},
			{Path: "subscription.status", Value: "expired"},
			{Path: "subscription.updated_at", Value: firestore.ServerTimestamp},
		})
	}); err != nil {
		return err
	}
	if status == "" {
		return nil
	}

	log.Printf("Expired: uid=%s, status=%s", doc.Ref.ID, status)
	return nil
}
