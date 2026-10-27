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

	"github.com/mnbst/thai-memo/functions/go/internal/lang"
	"github.com/mnbst/thai-memo/functions/go/internal/quality"
	"github.com/mnbst/thai-memo/functions/go/internal/sentence"
)

// 例文プールへの振り分け（dailyBatch のステップ6）。
//
// 生成直後に Jev で1回だけ判定した結果が例文 doc の quality フィールドに入っている
// （sentence.Producer.check）。ここでは Jev を呼び直さず、quality.passed が真の文だけを
// 確認待ち（pool_review.go）へ回す。人が OK した文だけが本番プールに入る。
// 外した文はログに残す。
//
// 不合格の文はセットから外れて例文 doc にならず、中身は sentence_flags に残っている。
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
	// poolRejected は不合格だった文。プールへ回さない（いまは不合格の文は保存されない）。
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

	// 本番プールへは直接足さず、確認待ちへ入れる（pool_review.go）。
	// 失敗しても生成済みの例文には影響しないので、エラーは返さず記録だけ残す。
	if err := queuePoolReview(ctx, db, accepted, docs, now); err != nil {
		log.Printf("poolReview: write failed: %v", err)
	}
	return nil
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
		Words:               wordsField(data["word_breakdown"]),
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

// wordsField は Firestore の word_breakdown（map の配列）を判定用の語と意味へ写す。
func wordsField(v any) []quality.Word {
	items, _ := v.([]any)
	out := make([]quality.Word, 0, len(items))
	for _, it := range items {
		m, _ := it.(map[string]any)
		out = append(out, quality.Word{Word: stringField(m["word"]), Meaning: stringField(m["meaning"])})
	}
	return out
}
