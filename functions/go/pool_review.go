package function

import (
	"context"
	"encoding/json"
	"log"
	"time"

	"cloud.google.com/go/firestore"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"

	"github.com/mnbst/thai-memo/functions/go/internal/poolreview"
	"github.com/mnbst/thai-memo/functions/go/internal/quality"
)

// 例文プールの確認待ち（docs/design_listening_playback.md「プールへの追加」）。
//
// dailyBatch は judge を通った文を本番プールへ直接足さず、Firestore の
// pool_review へ入れる。人が pool-review スキルで OK / NG を付け、OK の文だけを
// cmd/poolreview が本番プールへ移して、そのときお手本の音声を作る。

// poolReviewDoc は確認待ちの1件。sentence は本番プールの1件と同じ形
// （sentence.Sentence の JSON）で、承認時はそのままプールへ移す。
func poolReviewDoc(e poolEntry, c quality.Candidate, data map[string]any, now time.Time) (map[string]any, error) {
	raw, err := json.Marshal(e.Sentence)
	if err != nil {
		return nil, err
	}
	var s map[string]any
	if err := json.Unmarshal(raw, &s); err != nil {
		return nil, err
	}
	doc := map[string]any{
		"thai_text":  e.Sentence.ThaiText,
		"sentence":   s,
		"tier":       e.Tier,
		"lang":       string(e.Lang),
		"source":     "users/" + c.UID + "/sentences/" + c.SentenceID,
		"status":     poolreview.StatusPending,
		"queued_at":  now,
		"quality":    data["quality"],
		"created_at": data["created_at"],
	}
	return doc, nil
}

// queuePoolReview は判定を通った文を確認待ちへ入れる。既にある文（確認済みを含む）は飛ばす。
// 1件書けなくても残りは続ける（対象は直近24時間なので、ここで止めると翌日には拾い直されない）。
func queuePoolReview(
	ctx context.Context, db *firestore.Client, accepted []quality.Candidate,
	docs map[string]map[string]any, now time.Time,
) error {
	added, skipped, failed := 0, 0, 0
	var firstErr error
	for _, c := range accepted {
		data, ok := docs[quality.FlagID(c)]
		if !ok {
			continue
		}
		e, ok := buildPoolEntry(data)
		if !ok {
			continue
		}
		doc, err := poolReviewDoc(e, c, data, now)
		if err == nil {
			ref := db.Collection(poolreview.Collection).Doc(poolreview.ID(e.Tier, e.Lang, e.Sentence.ThaiText))
			_, err = ref.Create(ctx, doc)
		}
		switch {
		case status.Code(err) == codes.AlreadyExists:
			skipped++
		case err != nil:
			failed++
			if firstErr == nil {
				firstErr = err
			}
			log.Printf("poolReview: write failed source=users/%s/sentences/%s: %v", c.UID, c.SentenceID, err)
		default:
			added++
		}
	}
	log.Printf("poolReview: queued=%d already=%d failed=%d", added, skipped, failed)
	return firstErr
}
