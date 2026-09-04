package function

import (
	"context"
	"log"
	"math/rand"
	"strconv"
	"strings"
	"sync"
	"time"

	"cloud.google.com/go/firestore"
	"google.golang.org/api/iterator"

	"github.com/mnbst/thai-memo/functions/go/internal/llm"
	"github.com/mnbst/thai-memo/functions/go/internal/quality"
	"github.com/mnbst/thai-memo/functions/go/internal/secrets"
)

// 例文品質監査（dailyBatch のステップ6）の設定。
//
// 生成経路（generateThaiSentence）では判定しない。あのハンドラは UVM 更新の
// ゴルーチンを合流させてから返す作りで、判定を挟むとその時間がそのまま
// ユーザーの待ち時間に乗る。品質の記録のために生成を遅くする価値はない。
const (
	// auditWindow は監査対象の生成時刻の範囲（直近この時間ぶん）。
	// dailyBatch は JST 0:00 に回るので、実質「前日ぶん」になる。
	auditWindow = 24 * time.Hour

	// auditMaxPerRun は1回の実行で判定にかける例文の上限。
	// 対象母数が増えても LLM のコストと実行時間を一定に保つ。
	auditMaxPerRun = 100

	// auditMaxPerUser は1ユーザーから採る上限。大量に生成する少数の
	// ユーザーで枠が埋まると、監査結果がその人の語彙帯に偏る。
	auditMaxPerUser = 3

	// auditBatchSize は1回の LLM 呼び出しに詰める件数。
	auditBatchSize = 5

	// auditConcurrency は LLM 呼び出しの並列数。
	auditConcurrency = 4
)

// 判定に使う既定のプロバイダーとモデル。
//
// 生成（gemini-3.1-flash-lite）と別ベンダーにする。同じ系列だと自分の癖を
// 自然と判定して見逃すので、ここを生成側と揃えてはいけない。
//
// 2026-09-02 の実測（既知の欠陥6件＋正常4件の対照セット）:
//
//	gpt-5.6-luna      6件中5件を検出・誤検出0・$0.0006/回
//	gemini-3.5-flash  6件中3件・誤検出0・$0.0057/回
//	gemini-3.7-flash  同じ3件（モデルを上げても変わらない）
//
// 落ちるのは共起の誤り（ดูงาน 等）。judge のモデルではなくプロンプトが
// そのクラスを名指ししていないことによる。
const (
	defaultJudgeProvider = "openai"
	defaultJudgeModel    = "gpt-5.6-luna"
)

// runSentenceAudit は直近に生成された premium 例文を判定し、不自然なものだけを
// sentence_flags へ残す。
//
// users は runDailyBatch が既に読んだものを使い回す（3度目の全走査を避ける）。
func runSentenceAudit(
	ctx context.Context, db *firestore.Client, users []*firestore.DocumentSnapshot,
	now time.Time,
) error {
	maxPerRun := intEnvOr("SENTENCE_AUDIT_MAX", auditMaxPerRun)
	if maxPerRun <= 0 {
		log.Print("sentenceAudit: disabled (SENTENCE_AUDIT_MAX=0)")
		return nil
	}

	candidates := auditCandidates(ctx, db, users, now.Add(-auditWindow))
	if len(candidates) == 0 {
		log.Print("sentenceAudit: no premium sentences in window")
		return nil
	}
	candidates = sampleCandidates(candidates, maxPerRun)

	judge, err := newJudge(ctx)
	if err != nil {
		return err
	}

	var (
		mu      sync.Mutex
		flagged int
		failed  int
	)
	judgedAt := time.Now()

	batches := chunkCandidates(candidates, auditBatchSize)
	for i := 0; i < len(batches); i += auditConcurrency {
		end := min(i+auditConcurrency, len(batches))

		var wg sync.WaitGroup
		for _, batch := range batches[i:end] {
			wg.Add(1)
			go func(batch []quality.Candidate) {
				defer wg.Done()

				hits, verdicts, err := judge.JudgeBatch(ctx, batch)
				if err != nil {
					mu.Lock()
					failed++
					mu.Unlock()
					log.Printf("sentenceAudit: judge failed: %v", err)
					return
				}
				if len(hits) == 0 {
					return
				}
				if err := quality.Write(ctx, db, hits, verdicts, judge.Model, judgedAt); err != nil {
					log.Printf("sentenceAudit: write failed: %v", err)
					return
				}
				mu.Lock()
				flagged += len(hits)
				mu.Unlock()
			}(batch)
		}
		wg.Wait()
	}

	log.Printf("sentenceAudit: judged=%d flagged=%d failedBatches=%d model=%s",
		len(candidates), flagged, failed, judge.Model)
	return nil
}

// auditCandidates は各ユーザーの直近の premium 例文を集める。
//
// クエリは created_at の範囲だけにして generation_tier はメモリで絞る。
// 2フィールドの複合条件はサブコレクションの複合インデックスを要求するが、
// 1ユーザーの1日ぶんは数件なので、絞り込みの利得よりインデックス運用の
// 手間の方が大きい。
func auditCandidates(
	ctx context.Context, db *firestore.Client, users []*firestore.DocumentSnapshot,
	cutoff time.Time,
) []quality.Candidate {
	var out []quality.Candidate
	for _, userDoc := range users {
		uid := userDoc.Ref.ID
		it := db.Collection("users").Doc(uid).Collection("sentences").
			Where("created_at", ">=", cutoff).
			Documents(ctx)

		taken := 0
		for taken < auditMaxPerUser {
			doc, err := it.Next()
			if err == iterator.Done {
				break
			}
			if err != nil {
				log.Printf("sentenceAudit: read failed uid=%s: %v", uid, err)
				break
			}
			c, ok := candidateFrom(uid, doc.Ref.ID, doc.Data())
			if !ok {
				continue
			}
			out = append(out, c)
			taken++
		}
		it.Stop()
	}
	return out
}

// candidateFrom は例文 doc を判定対象へ変換する。premium 生成でないもの、
// 本文が欠けているものは対象外。
func candidateFrom(uid, docID string, data map[string]any) (quality.Candidate, bool) {
	if stringField(data["generation_tier"]) != "premium" {
		return quality.Candidate{}, false
	}
	thai := stringField(data["thai_text"])
	if thai == "" {
		return quality.Candidate{}, false
	}

	ctxMap, _ := data["context"].(map[string]any)
	createdAt, _ := data["created_at"].(time.Time)

	return quality.Candidate{
		UID:                 uid,
		SentenceID:          docID,
		ThaiText:            thai,
		Pronunciation:       stringField(data["pronunciation"]),
		JapaneseTranslation: stringField(data["japanese_translation"]),
		KeyWord:             stringField(data["key_word"]),
		Topic:               stringField(ctxMap["topic"]),
		Emotion:             stringField(ctxMap["emotion"]),
		GenerationTier:      "premium",
		CreatedAt:           createdAt,
	}, true
}

// sampleCandidates は上限まで無作為に間引く。
//
// 先頭から切ると users の走査順（＝doc ID 順）で常に同じユーザーばかりが
// 監査され、残りの生成結果が永久に見えない。
func sampleCandidates(candidates []quality.Candidate, maxPerRun int) []quality.Candidate {
	if len(candidates) <= maxPerRun {
		return candidates
	}
	rand.Shuffle(len(candidates), func(i, j int) {
		candidates[i], candidates[j] = candidates[j], candidates[i]
	})
	return candidates[:maxPerRun]
}

// chunkCandidates は size 件ずつに分ける。
func chunkCandidates(candidates []quality.Candidate, size int) [][]quality.Candidate {
	var out [][]quality.Candidate
	for i := 0; i < len(candidates); i += size {
		out = append(out, candidates[i:min(i+size, len(candidates))])
	}
	return out
}

// newJudge は判定用の LLM クライアントを組み立てる。
//
// SENTENCE_JUDGE_PROVIDER で openai / gemini を選ぶ。判定は生成と別ベンダーに
// できると blind spot の相関がいちばん切れるので、片方に固定しない。
// isPremium=true で呼ぶので *ModelPremium 側だけ設定すれば足りる。
func newJudge(ctx context.Context) (*quality.Judge, error) {
	provider := strings.ToLower(envOr("SENTENCE_JUDGE_PROVIDER", defaultJudgeProvider))
	model := envOr("SENTENCE_JUDGE_MODEL", defaultJudgeModel)

	client := &llm.Client{Provider: provider, MaxTokens: apiMaxTokens}
	switch provider {
	case "openai":
		key, err := secrets.Get(ctx, "openai-api-key")
		if err != nil {
			return nil, err
		}
		client.OpenAIKey = key
		client.OpenAIModelPremium = model
	default:
		key, err := secrets.Get(ctx, "gemini-api-key")
		if err != nil {
			return nil, err
		}
		client.GeminiKey = key
		client.GeminiModelPremium = model
	}
	return &quality.Judge{Gen: client, Model: model}, nil
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
