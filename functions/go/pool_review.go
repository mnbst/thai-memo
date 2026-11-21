package function

import (
	"context"
	"encoding/json"
	"log"
	"time"

	"cloud.google.com/go/firestore"
	"google.golang.org/api/iterator"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"

	"github.com/mnbst/thai-memo/functions/go/internal/poolreview"
	"github.com/mnbst/thai-memo/functions/go/internal/quality"
)

// 例文プールの確認待ち（docs/design_listening_playback.md「プールへの追加」）。
//
// dailyBatch は judge を通った文を本番プールへ直接足さず、Firestore の
// pool_review へ入れる。pool-review スキルで OK / NG を付け、OK の文だけを
// cmd/poolreview が本番プールへ移して、そのときお手本の音声を作る。
//
// judge で不合格だった文（sentence_flags）も確認待ちへ入れる。judge は誤検出が多く
// （2026-11-21、訳の意味のずれで外れた 407本のうち 380本が正しい訳）、確認で拾い直すため。
// quality.passed=false と所見がそのまま載るので、確認する側は不合格の文だと分かる。

// poolReviewDoc は確認待ちの1件。sentence は本番プールの1件と同じ形
// （sentence.Sentence の JSON）で、承認時はそのままプールへ移す。
func poolReviewDoc(e poolEntry, source string, data map[string]any, now time.Time) (map[string]any, error) {
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
		"source":     source,
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
		source := "users/" + c.UID + "/sentences/" + c.SentenceID
		err := createPoolReview(ctx, db, e, source, data, now)
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

// createPoolReview は確認待ちを1件作る。既にあれば AlreadyExists を返す。
func createPoolReview(
	ctx context.Context, db *firestore.Client, e poolEntry, source string,
	data map[string]any, now time.Time,
) error {
	doc, err := poolReviewDoc(e, source, data, now)
	if err != nil {
		return err
	}
	ref := db.Collection(poolreview.Collection).Doc(poolreview.ID(e.Tier, e.Lang, e.Sentence.ThaiText))
	_, err = ref.Create(ctx, doc)
	return err
}

// flaggedReviewData は sentence_flags の1件を、確認待ちへ入れる例文 doc の形にする。
// 文の全体（sentence_doc）を持たない古い flag は false。
//
// quality は例文 doc と同じ形（passed・reason・scores・model）で載せる。
// created_at は生成時刻、無ければ判定時刻。
func flaggedReviewData(flag map[string]any) (map[string]any, bool) {
	sd, ok := flag["sentence_doc"].(map[string]any)
	if !ok {
		return nil, false
	}
	data := make(map[string]any, len(sd)+2)
	for k, v := range sd {
		data[k] = v
	}
	data["quality"] = map[string]any{
		"passed": false,
		"reason": flag["reason"],
		"scores": flag["scores"],
		"model":  flag["judge_model"],
	}
	if t, ok := flag["created_at"].(time.Time); ok && !t.IsZero() {
		data["created_at"] = t
	} else {
		data["created_at"] = flag["judged_at"]
	}
	return data, true
}

// queueFlaggedReview は直近の judge 不合格の文（sentence_flags）を確認待ちへ入れる。
// 合格の文と同じく、既にある文（確認済みを含む）は飛ばし、1件の失敗で止めない。
func queueFlaggedReview(ctx context.Context, db *firestore.Client, cutoff, now time.Time) error {
	it := db.Collection("sentence_flags").Where("judged_at", ">=", cutoff).Documents(ctx)
	defer it.Stop()
	added, skipped, failed, unusable := 0, 0, 0, 0
	var firstErr error
	for {
		snap, err := it.Next()
		if err == iterator.Done {
			break
		}
		if err != nil {
			return err
		}
		data, ok := flaggedReviewData(snap.Data())
		if !ok {
			unusable++
			continue
		}
		e, ok := buildPoolEntry(data)
		if !ok {
			unusable++
			continue
		}
		err = createPoolReview(ctx, db, e, "sentence_flags/"+snap.Ref.ID, data, now)
		switch {
		case status.Code(err) == codes.AlreadyExists:
			skipped++
		case err != nil:
			failed++
			if firstErr == nil {
				firstErr = err
			}
			log.Printf("poolReview: flagged write failed source=sentence_flags/%s: %v", snap.Ref.ID, err)
		default:
			added++
		}
	}
	log.Printf("poolReview: flagged queued=%d already=%d failed=%d unusable=%d", added, skipped, failed, unusable)
	return firstErr
}
