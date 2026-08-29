package function

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"os"
	"strconv"
	"strings"
	"sync"
	"time"

	"cloud.google.com/go/firestore"

	"github.com/mnbst/thai-memo/functions/go/internal/bldrama"
	"github.com/mnbst/thai-memo/functions/go/internal/callable"
	"github.com/mnbst/thai-memo/functions/go/internal/embeddings"
	"github.com/mnbst/thai-memo/functions/go/internal/fbapp"
	"github.com/mnbst/thai-memo/functions/go/internal/lang"
	"github.com/mnbst/thai-memo/functions/go/internal/llm"
	"github.com/mnbst/thai-memo/functions/go/internal/premium"
	"github.com/mnbst/thai-memo/functions/go/internal/quota"
	"github.com/mnbst/thai-memo/functions/go/internal/secrets"
	"github.com/mnbst/thai-memo/functions/go/internal/sentence"
	"github.com/mnbst/thai-memo/functions/go/internal/uvm"
)

// generateThaiSentence は functions/python/sentence_handlers.py:generateThaiSentence
// の移植。
//
// このハンドラは callable のエラー機構を使わない。失敗も HTTP 200 で
// {"success": false, "error": {"code", "message"}} を返す（クライアントが
// この形だけを見ているため）。
func generateThaiSentence(ctx context.Context, req *callable.Request) (any, error) {
	start := time.Now()
	response := map[string]any{"success": false}

	var params map[string]any
	if err := req.Bind(&params); err != nil {
		// data が JSON として壊れている場合。Python は req.data が dict でなければ
		// {} 相当で進むので、ここでも空として続ける。
		params = nil
	}
	if params == nil {
		params = map[string]any{}
	}

	requestedTopic := "random"
	if t, ok := params["topic"].(string); ok {
		requestedTopic = t
	}
	l := lang.Resolve(params["lang"])

	logData := map[string]any{
		"timestamp":      start.UTC().Format(time.RFC3339Nano),
		"userId":         "anonymous",
		"requestedTopic": requestedTopic,
		// 訳文の言語。旧クライアントは送ってこないので ja に落ちる。
		"lang": string(l),
		// App Check は現状 UNENFORCED。Python 版は検証済みトークンの有無を
		// 記録していたが、Go の callable は App Check を検証しないので、
		// ここではヘッダの有無だけを見る（未証明の割合はやや低く出る）。
		"appCheck": req.Raw != nil && req.Raw.Header.Get("X-Firebase-AppCheck") != "",
	}

	if req.Auth == nil || req.Auth.UID == "" {
		logData["error"] = "UNAUTHENTICATED"
		log.Printf("Authentication failed: %s", logJSON(logData))
		response["error"] = map[string]any{
			"code":    "UNAUTHENTICATED",
			"message": "User must be authenticated",
		}
		return response, nil
	}
	uid := req.Auth.UID
	logData["userId"] = uid
	log.Printf("Request started: %s", logJSON(logData))

	result, err := runGenerateThaiSentence(ctx, uid, params, l, logData, start)
	if err != nil {
		logData["success"] = false
		logData["processingTimeMs"] = int(time.Since(start).Milliseconds())
		logData["errorMessage"] = err.Error()
		response["error"] = generationErrorPayload(err)
		log.Printf("Request failed: %s", logJSON(logData))
		return response, nil
	}

	response["success"] = true
	response["data"] = result
	log.Printf("Request completed successfully: %s", logJSON(logData))
	return response, nil
}

// generationErrorPayload は例外メッセージからクライアントへ返すコードを決める
// （sentence_handlers.py の except 節）。
func generationErrorPayload(err error) map[string]any {
	msg := err.Error()
	switch {
	case strings.Contains(msg, "QUOTA_EXCEEDED"):
		return map[string]any{
			"code":    "QUOTA_EXCEEDED",
			"message": "この時間帯の例文生成上限に達しました",
		}
	case strings.Contains(msg, "SECRET_MANAGER_ERROR"):
		return map[string]any{
			"code":    "INTERNAL",
			"message": "Failed to retrieve API configuration",
		}
	case strings.Contains(msg, "LLM_API_ERROR"):
		return map[string]any{
			"code":    "API_ERROR",
			"message": "Failed to generate sentence",
		}
	default:
		return map[string]any{
			"code":    "UNKNOWN",
			"message": "An unexpected error occurred",
		}
	}
}

var errQuotaExceeded = errors.New("QUOTA_EXCEEDED")

func runGenerateThaiSentence(
	ctx context.Context, uid string, params map[string]any, l lang.Lang,
	logData map[string]any, start time.Time,
) (*sentence.Sentence, error) {
	db, err := fbapp.Firestore(ctx)
	if err != nil {
		return nil, err
	}
	userRef := db.Collection("users").Doc(uid)

	userData := map[string]any{}
	if snap, err := userRef.Get(ctx); err == nil && snap.Exists() {
		userData = snap.Data()
	}

	// 主経路は onUserCreate トリガーだが、doc 欠損（トリガー失敗・削除済み・
	// トリガー導入前ユーザー）のまま生成されると remaining_sentences=0 で
	// QUOTA_EXCEEDED になる。ここで冪等に初期クォータを付与して自己回復する。
	//
	// doc の有無ではなくクォータフィールドの有無で判定すること。孤児doc掃除
	// （dailyBatch）で doc が消えた後、updateUvm 等が merge=True でクイズ系
	// フィールドだけの部分docを作り直すケースがあり、doc は存在するのに
	// クォータだけ無い状態で永久に QUOTA_EXCEEDED になる。
	if _, ok := userData["remaining_sentences"]; !ok {
		initial, err := ensureUserQuota(ctx, userRef)
		if err != nil {
			return nil, err
		}
		for k, v := range initial {
			userData[k] = v
		}
	}

	isPremium := userData["tier"] == "premium"

	// プレミアム体験トライアル: 期間中は premium ロジック
	// （テーマ選択・premiumプロンプト・語彙上限なし）で出す。
	// クライアントの申告（premium_trial）は見ない。
	trialActive := !isPremium && premium.IsTrialActive(userData, time.Now())
	usePremiumSpec := isPremium || trialActive

	remaining := intValue(userData["remaining_sentences"])
	if remaining <= 0 {
		logData["error"] = "QUOTA_EXCEEDED"
		logData["remainingSentences"] = remaining
		log.Printf("Quota exceeded: %s", logJSON(logData))
		return nil, errQuotaExceeded
	}

	estimatedVocab := intValue(userData["estimated_vocab"])
	if !usePremiumSpec {
		estimatedVocab = min(estimatedVocab, uvm.FreeTierMaxVocab)
	}

	freqRank, err := uvm.GetFreqRank(ctx, fbapp.ProjectID())
	if err != nil {
		return nil, err
	}

	producer, err := newProducer(ctx)
	if err != nil {
		return nil, err
	}

	produced, err := producer.Produce(ctx, db, freqRank, sentence.ProduceRequest{
		UID:            uid,
		Params:         effectiveGenerationParams(params, usePremiumSpec),
		UsePremiumSpec: usePremiumSpec,
		EstimatedVocab: estimatedVocab,
		Lang:           l,
	})
	if err != nil {
		return nil, err
	}
	if produced == nil { // CacheOnly=false では起きない
		return nil, errors.New("sentence generation returned nothing")
	}

	logData["uvmWords"] = len(produced.TargetWords)
	logData["chosenTopic"] = produced.ChosenTopic
	if produced.FromCache {
		logData["source"] = "cached"
	}
	logData["success"] = true
	logData["processingTimeMs"] = int(time.Since(start).Milliseconds())

	// UVM の更新はレスポンスを待たせない。ただし返す前に必ず合流する
	// （Python 版のスレッドと同じ）。
	var wg sync.WaitGroup
	wg.Add(1)
	go func() {
		defer wg.Done()
		registerSentenceExposure(ctx, db, uid, produced)
		// premium は上限なし（負の値で「上限なし」を表す）。
		maxVocab := -1
		if !isPremium {
			maxVocab = uvm.FreeTierMaxVocab
		}
		uvm.SyncEstimatedVocab(ctx, db, uid, freqRank, maxVocab)
	}()

	if err := commitSentence(ctx, db, userRef, uid, produced, usePremiumSpec); err != nil {
		log.Printf("Failed to save sentence to Firestore: %v", err)
		wg.Wait()
		return nil, err
	}

	produced.Sentence.TargetWords = produced.TargetWords

	wg.Wait()
	return produced.Sentence, nil
}

// registerSentenceExposure は例文に出た語の露出を UVM に記録する
// （sentence_handlers.py:_register_sentence_exposure:151）。
//
// ターゲット語は新規作成も許すが、それ以外の語は既存ドキュメントの更新だけ。
func registerSentenceExposure(
	ctx context.Context, db *firestore.Client, uid string, produced *sentence.Produced,
) {
	allWords := uvm.SentenceWords(produced.Sentence.BreakdownWords())
	exposed := uvm.ExposedWords(produced.Sentence.BreakdownWords(), produced.TargetWords)
	if len(exposed) > 0 {
		if err := uvm.RegisterExposure(ctx, db, uid, exposed, produced.TargetWords); err != nil {
			log.Printf("register_sentence_exposure failed: %v", err)
			return
		}
	}

	targets := map[string]bool{}
	for _, t := range produced.TargetWords {
		targets[t] = true
	}
	var others []string
	for _, w := range allWords {
		if !targets[w] {
			others = append(others, w)
		}
	}
	if len(others) > 0 {
		if err := uvm.RegisterExposure(ctx, db, uid, others, nil); err != nil {
			log.Printf("register_sentence_exposure failed: %v", err)
		}
	}
}

// commitSentence は例文の保存とクォータ消費を 1 トランザクションで行う
// （sentence_handlers.py:_commit_sentences_transaction:296）。
func commitSentence(
	ctx context.Context, db *firestore.Client, userRef *firestore.DocumentRef,
	uid string, produced *sentence.Produced, usePremiumSpec bool,
) error {
	sentenceRef := userRef.Collection("sentences").NewDoc()
	doc := produced.Sentence.BuildSentenceDoc(produced.TargetWords[0], usePremiumSpec)

	return db.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		snap, err := tx.Get(userRef)
		userData := map[string]any{}
		if err == nil && snap.Exists() {
			userData = snap.Data()
		}
		if intValue(userData["remaining_sentences"]) < 1 {
			return errQuotaExceeded
		}
		if err := tx.Set(sentenceRef, doc); err != nil {
			return err
		}
		return tx.Update(userRef, sentenceCommitUpdate(userData, 1))
	})
}

// sentenceCommitUpdate は例文コミット時の users ドキュメント更新内容
// （sentence_handlers.py:_build_sentence_commit_update:277）。
//
// トライアルは期間制なので、消費するのは通常クォータ（remaining_sentences）だけ。
func sentenceCommitUpdate(userData map[string]any, decrement int) []firestore.Update {
	updates := []firestore.Update{
		{Path: "remaining_sentences", Value: firestore.Increment(-decrement)},
		{Path: "daily_sentence_generated", Value: true},
		{Path: "last_active_at", Value: firestore.ServerTimestamp},
		{Path: "last_sentence_generated_at", Value: firestore.ServerTimestamp},
		{Path: "sentence_generated_count", Value: firestore.Increment(decrement)},
	}
	if _, ok := userData["first_generated_at"]; !ok {
		updates = append(updates,
			firestore.Update{Path: "first_generated_at", Value: firestore.ServerTimestamp})
	}
	return updates
}

// ensureUserQuota は users/{uid} に初期クォータを冪等に付与し、その内容を返す
// （sentence_handlers.py:_ensure_user_quota:317）。
//
// onUserCreate トリガー（JS）と同じ初期値を使う。merge なので、万一トリガーと
// 競合しても既存フィールドを壊さない。値は quota パッケージで一元管理。
func ensureUserQuota(ctx context.Context, userRef *firestore.DocumentRef) (map[string]any, error) {
	initial := map[string]any{
		// 付与直後はトライアル中なので premium と同じ回数を出す。
		"remaining_sentences":      quota.PremiumDailySentences,
		"remaining_quizzes":        quota.PremiumDailyQuizzes,
		"daily_sentence_generated": false,
		// 期限はクォータのリセット境界（JST 0:00）に揃える。premium パッケージと同じ規則。
		"premium_trial_expires_at": time.UnixMilli(
			premium.TrialExpiresAtMsFrom(time.Now().UnixMilli(), quota.PremiumTrialDays)).UTC(),
		// 旧クライアント（〜1.3.15）がテーマを消さないための凍結値。減らさない。
		"premium_trial_remaining": quota.PremiumTrialSentences,
	}
	if _, err := userRef.Set(ctx, initial, firestore.MergeAll); err != nil {
		return nil, err
	}
	log.Printf("Initial quota set (fallback) for user %s", userRef.ID)
	return initial, nil
}

// effectiveGenerationParams は生成条件として LLM へ渡すパラメータを整える
// （sentence_handlers.py:_effective_generation_params:131）。
//
// テーマはクライアントの指定をそのまま使う。ヒアリング（interview.goal）
// からの決定も端末側で行う。free は自動選択に固定する。
func effectiveGenerationParams(params map[string]any, isPremium bool) map[string]any {
	out := map[string]any{}
	for k, v := range params {
		out[k] = v
	}
	delete(out, "premium_trial")
	// lang は生成条件ではなく出力言語の指定。ここに残すとプロンプトの
	// 「条件」ブロックに未知のキーとして流れ込むので取り除く。
	delete(out, "lang")
	if !isPremium {
		delete(out, "topic")
	}
	return out
}

// newProducer は生成コアに必要な依存を組み立てる。
func newProducer(ctx context.Context) (*sentence.Producer, error) {
	provider := strings.ToLower(envOr("SENTENCE_PROVIDER", "gemini"))

	// Python は使うプロバイダーのキーだけを遅延取得する。両方まとめて取ると、
	// openai を使っていない環境で openai-api-key シークレットが無いだけで
	// 生成が落ちる。
	geminiKey, err := secrets.Get(ctx, "gemini-api-key")
	if err != nil {
		return nil, fmt.Errorf("SECRET_MANAGER_ERROR: %w", err)
	}
	openAIKey := ""
	if provider == "openai" {
		openAIKey, err = secrets.Get(ctx, "openai-api-key")
		if err != nil {
			return nil, fmt.Errorf("SECRET_MANAGER_ERROR: %w", err)
		}
	}

	client := &llm.Client{
		OpenAIKey:          openAIKey,
		GeminiKey:          geminiKey,
		Provider:           provider,
		MaxTokens:          apiMaxTokens,
		OpenAIModel:        envOr("OPENAI_MODEL", "gpt-5.6-luna"),
		OpenAIModelPremium: envOr("OPENAI_MODEL_PREMIUM", "gpt-5.6-luna"),
		GeminiModel:        envOr("GEMINI_MODEL", "gemini-3.1-flash-lite"),
		GeminiModelPremium: envOr("GEMINI_MODEL_PREMIUM", "gemini-3.1-flash-lite"),
	}

	store := embeddings.Default
	return &sentence.Producer{
		Selector: &sentence.TargetWordSelector{
			Session: &uvm.SessionSelector{Emb: store},
		},
		Bank: &sentence.FreeBank{ProjectID: fbapp.ProjectID()},
		Service: &sentence.Service{
			Gen:      client,
			Resolver: &sentence.Resolver{SubThemes: store},
			Drama:    &bldrama.Builder{Ctx: ctx, Shots: store},
		},
	}, nil
}

// apiMaxTokens は constants.API_MAX_TOKENS。
const apiMaxTokens = 8192

func envOr(key, fallback string) string {
	if v := strings.TrimSpace(os.Getenv(key)); v != "" {
		return v
	}
	return fallback
}

// intValue は Firestore から返る数値（int64 / float64）を int に落とす。
func intValue(v any) int {
	switch n := v.(type) {
	case int64:
		return int(n)
	case int:
		return n
	case float64:
		return int(n)
	case string:
		if i, err := strconv.Atoi(n); err == nil {
			return i
		}
	}
	return 0
}

// logJSON は Python の print(f"...: {log_data}") 相当。dict の repr ではなく
// JSON にする（Cloud Logging で構造化して読めるように）。
func logJSON(data map[string]any) string {
	b, err := json.Marshal(data)
	if err != nil {
		return fmt.Sprintf("%v", data)
	}
	return string(b)
}
