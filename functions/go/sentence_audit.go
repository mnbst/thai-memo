package function

import (
	"context"
	"fmt"
	"log"
	"strconv"
	"sync"
	"time"

	"cloud.google.com/go/firestore"
	"google.golang.org/api/iterator"

	"github.com/mnbst/thai-memo/functions/go/internal/fbapp"
	"github.com/mnbst/thai-memo/functions/go/internal/lang"
	"github.com/mnbst/thai-memo/functions/go/internal/quality"
	"github.com/mnbst/thai-memo/functions/go/internal/sentence"
)

// 例文プールへの振り分け（dailyBatch のステップ6）。
//
// 生成直後に Jev で判定し、不合格なら作り直して判定し直した結果が例文 doc の
// quality フィールドに入っている（sentence.Producer.checkAndRetry）。ここでは
// quality.passed が真の文だけを候補にし、さらにプール用の観点（quality.PoolAspects）で
// 判定し直して、通った文だけを例文プールへ回す。外した文はログに残す。
// premium と free は同じ観点で判定し、ティアごとのプールへ書き分ける（sentence_pool.go）。
//
// 不合格の中身は sentence_flags にも判定ごとに残っている（stage=first / retry）。
// stage=retry が「作り直しても不合格でプールに入らなかった文」。
const (
	// auditWindow は対象の生成時刻の範囲（直近この時間ぶん）。
	// dailyBatch は JST 0:00 に回るので、実質「前日ぶん」になる。
	auditWindow = 24 * time.Hour
)

// poolVerdict は例文 doc の quality からプールへの振り分けを決めた結果。
type poolVerdict int

const (
	// poolPassed は判定に合格した文。プールへ回す。
	poolPassed poolVerdict = iota
	// poolRejected は作り直しても不合格だった文。プールへ回さない。
	poolRejected
	// poolUnjudged は判定していない文（判定の失敗・判定を止めていた期間）。
	// 品質が分からないのでプールへ回さない。
	poolUnjudged
)

// runSentenceAudit は直近の LLM 生成の例文のうち、判定に合格したものを例文プールへ回す。
//
// users は runDailyBatch が既に読んだものを使い回す（3度目の全走査を避ける）。
func runSentenceAudit(
	ctx context.Context, db *firestore.Client, users []*firestore.DocumentSnapshot,
	now time.Time,
) error {
	candidates, docs := auditCandidates(ctx, db, users, now.Add(-auditWindow))
	if len(candidates) == 0 {
		log.Print("sentencePool: no LLM sentences in window")
		return nil
	}

	var accepted []quality.Candidate
	counts := map[poolVerdict]int{}
	for _, c := range candidates {
		v, reason := poolVerdictOf(docs[quality.FlagID(c)])
		counts[v]++
		switch v {
		case poolPassed:
			accepted = append(accepted, c)
		case poolRejected:
			log.Printf("sentencePool: rejected tier=%s key_word=%s reason=%s thai=%q translation=%q",
				c.GenerationTier, c.KeyWord, reason, c.ThaiText, c.JapaneseTranslation)
		}
	}
	log.Printf("sentencePool: candidates=%d (%s) passed=%d rejected=%d unjudged=%d",
		len(candidates), tierCounts(candidates), counts[poolPassed], counts[poolRejected], counts[poolUnjudged])

	if len(accepted) > 0 {
		judge, err := quality.NewJudge(ctx)
		if err != nil {
			// 判定できないなら入れない（未判定の文と同じ扱い）。
			log.Printf("sentencePool: judge unavailable, skip pooling: %v", err)
			return nil
		}
		accepted = poolGate(ctx, judge, accepted)
	}

	// プールの書き出しに失敗しても生成済みの例文には影響しないので、
	// エラーは返さず記録だけ残す。
	if err := poolAccepted(ctx, accepted, docs); err != nil {
		log.Printf("sentencePool: write failed: %v", err)
	}
	return nil
}

// poolReviewer はプール用の観点で判定するもの（quality.Judge。テストで差し替える）。
type poolReviewer interface {
	ReviewPool(ctx context.Context, batch []quality.Candidate) (quality.Result, error)
}

// poolGate は生成時の判定に合格した文を、プール用の観点で判定し直す。
// 通った文だけを返す。判定に失敗した文は返さない（品質が分からない文は入れない）。
func poolGate(ctx context.Context, r poolReviewer, accepted []quality.Candidate) []quality.Candidate {
	res, err := r.ReviewPool(ctx, accepted)
	if err != nil {
		log.Printf("sentencePool: pool judge failed for some sentences: %v", err)
	}
	for i, c := range res.Flagged {
		log.Printf("sentencePool: pool-rejected tier=%s key_word=%s reason=%s thai=%q translation=%q",
			c.GenerationTier, c.KeyWord, res.Verdicts[i].Reason, c.ThaiText, c.JapaneseTranslation)
	}
	log.Printf("sentencePool: pool judge accepted=%d (%s) rejected=%d failed=%d",
		len(res.Accepted), tierCounts(res.Accepted), len(res.Flagged),
		len(accepted)-len(res.Accepted)-len(res.Flagged))
	return res.Accepted
}

// tierCounts はティアごとの本数をログ用に並べる（premium=3 free=1）。
func tierCounts(cs []quality.Candidate) string {
	n := map[string]int{}
	for _, c := range cs {
		n[c.GenerationTier]++
	}
	return fmt.Sprintf("premium=%d free=%d",
		n[sentence.GenerationTier(true)], n[sentence.GenerationTier(false)])
}

// poolVerdictOf は例文 doc の quality フィールドから振り分けを決める。
// 不合格なら理由（閾値を超えた観点と確率）も返す。
func poolVerdictOf(data map[string]any) (poolVerdict, string) {
	q, ok := data["quality"].(map[string]any)
	if !ok {
		return poolUnjudged, ""
	}
	passed, ok := q["passed"].(bool)
	if !ok {
		return poolUnjudged, ""
	}
	if passed {
		return poolPassed, ""
	}
	return poolRejected, stringField(q["reason"])
}

// poolAccepted は判定を通った例文を GCS のプールへ足す。
//
// SENTENCE_POOL_MAX=0 で止められる（プール自体を使わない運用に戻せる）。
func poolAccepted(
	ctx context.Context, accepted []quality.Candidate, docs map[string]map[string]any,
) error {
	maxEntries := intEnvOr("SENTENCE_POOL_MAX", poolMaxEntries)
	if maxEntries <= 0 {
		log.Print("sentencePool: disabled (SENTENCE_POOL_MAX=0)")
		return nil
	}
	entries := make([]poolEntry, 0, len(accepted))
	for _, c := range accepted {
		data, ok := docs[quality.FlagID(c)]
		if !ok {
			continue
		}
		if e, ok := buildPoolEntry(data); ok {
			entries = append(entries, e)
		}
	}
	return writeSentencePool(ctx, fbapp.ProjectID(), entries, maxEntries)
}

// auditCandidates は各ユーザーの直近の LLM 生成の例文（premium / free）を集める。
//
// クエリは created_at の範囲だけにして generation_tier はメモリで絞る。
// 2フィールドの複合条件はサブコレクションの複合インデックスを要求するが、
// 1ユーザーの1日ぶんは数件なので、絞り込みの利得よりインデックス運用の
// 手間の方が大きい。
func auditCandidates(
	ctx context.Context, db *firestore.Client, users []*firestore.DocumentSnapshot,
	cutoff time.Time,
) ([]quality.Candidate, map[string]map[string]any) {
	var out []quality.Candidate
	// docs はプールへ入れるときと quality を読むときに使う。Candidate は
	// 一部の項目しか持たず、word_breakdown や quality が落ちているため doc 側を取っておく。
	docs := map[string]map[string]any{}
	jobs := make(chan *firestore.DocumentSnapshot, dailyBatchConcurrency)
	var wg sync.WaitGroup
	var outMu sync.Mutex
	for range dailyBatchConcurrency {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for userDoc := range jobs {
				uid := userDoc.Ref.ID
				it := db.Collection("users").Doc(uid).Collection("sentences").
					Where("created_at", ">=", cutoff).Documents(ctx)
				var found []quality.Candidate
				for {
					doc, err := it.Next()
					if err == iterator.Done {
						break
					}
					if err != nil {
						log.Printf("sentencePool: read failed uid=%s: %v", uid, err)
						break
					}
					if c, ok := candidateFrom(uid, doc.Ref.ID, doc.Data()); ok {
						found = append(found, c)
						outMu.Lock()
						docs[quality.FlagID(c)] = doc.Data()
						outMu.Unlock()
					}
				}
				it.Stop()
				outMu.Lock()
				out = append(out, found...)
				outMu.Unlock()
			}
		}()
	}
	for _, userDoc := range users {
		jobs <- userDoc
	}
	close(jobs)
	wg.Wait()
	return out, docs
}

// candidateFrom は例文 doc をプールの候補へ変換する。ティアが premium / free で
// ないもの、バンク由来のもの、本文が欠けているものは対象外。
//
// バンク由来（from_cache=true）を外すのは、既にバンクにある文をプールへ入れ直すと
// 同じ文が二重に増えるため。フィールドが無い doc はこれを付ける前の保存で、
// 当時は LLM 生成しか users/{uid}/sentences に入らなかったので対象のままでよい。
func candidateFrom(uid, docID string, data map[string]any) (quality.Candidate, bool) {
	tier, ok := poolTier(data)
	if !ok {
		return quality.Candidate{}, false
	}
	if cached, ok := data["from_cache"].(bool); ok && cached {
		return quality.Candidate{}, false
	}
	// 本人が消した例文・洗い替えた未読セットは共有の在庫に回さない。
	if isSentenceDeleted(data) {
		return quality.Candidate{}, false
	}
	thai := stringField(data["thai_text"])
	if thai == "" {
		return quality.Candidate{}, false
	}

	ctxMap, _ := data["context"].(map[string]any)
	createdAt, _ := data["created_at"].(time.Time)

	return quality.Candidate{
		Lang:                lang.Resolve(data["lang"]),
		UID:                 uid,
		SentenceID:          docID,
		ThaiText:            thai,
		Pronunciation:       stringField(data["pronunciation"]),
		JapaneseTranslation: stringField(data["japanese_translation"]),
		KeyWord:             stringField(data["key_word"]),
		Topic:               stringField(ctxMap["topic"]),
		Emotion:             stringField(ctxMap["emotion"]),
		GenerationTier:      tier,
		CreatedAt:           createdAt,
	}, true
}

// chunkCandidates は size 件ずつに分ける（sentence_audit_live_test の束分けで使う）。
func chunkCandidates(candidates []quality.Candidate, size int) [][]quality.Candidate {
	var out [][]quality.Candidate
	for i := 0; i < len(candidates); i += size {
		out = append(out, candidates[i:min(i+size, len(candidates))])
	}
	return out
}

// newJudge は手元で判定を試すための判定器（sentence_audit_live_test）。
func newJudge(ctx context.Context) (*quality.Judge, error) {
	return quality.NewJudge(ctx)
}

// intEnvOr は整数の環境変数を読む。空・不正なら fallback。
func intEnvOr(key string, fallback int) int {
	v := envOr(key, "")
	if v == "" {
		return fallback
	}
	n, err := strconv.Atoi(v)
	if err != nil {
		log.Printf("%s=%q は整数として読めない。既定値 %d を使う", key, v, fallback)
		return fallback
	}
	return n
}

// stringField は Firestore の値を文字列に落とす。
func stringField(v any) string {
	s, _ := v.(string)
	return s
}
