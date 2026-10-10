package function

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"os"
	"slices"
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
	"github.com/mnbst/thai-memo/functions/go/internal/themeshots"
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
		// App Check は検証するが弾かない（callable.HTTP 参照）。
		"appCheck": req.AppCheck == callable.AppCheckValid,
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
	// data は1本目。セットを知らない旧クライアントはこれだけを見る。
	// sentences には作れた全部を入れる（1本のときも配列で返す）。
	response["data"] = result[0]
	response["sentences"] = result
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
	case strings.Contains(msg, "GENERATION_IN_PROGRESS"):
		return map[string]any{
			"code":    "RESOURCE_BUSY",
			"message": "例文を生成中です。しばらくしてから再度お試しください",
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
var errGenerationInProgress = errors.New("GENERATION_IN_PROGRESS")

// generationLeaseDuration は例文生成 lease の有効期限。
//
// インスタンスが落ちて defer の解放が走らなかった場合、次に生成できるまでの
// ロックアウト時間がそのままこの値になる。守る処理より十分長く、かつ無駄に
// 長くない値にする。現在の関数タイムアウトは generateThaiSentence が 120 秒、
// 同じ lease を取る resetLearningData が 60 秒なので、余裕を 60 秒足して 3 分。
// 関数タイムアウトを伸ばすときはここも一緒に見直すこと。
const generationLeaseDuration = 3 * time.Minute

// requestedSetSize はクライアントが求める本数。
//
// 旧クライアントは count を送らないので1本（従来どおり）。上限は
// そのユーザーのセット本数（sentence.SetSizeFor）で、これを超える値を
// 送られても増やさない。入門者はここで2〜4本に縮む。
//
// 数を読むのに callable.Int を使うこと。Flutter の Firebase SDK は Dart の
// int を protobuf の Int64 ラッパー
// （{"@type":".../google.protobuf.Int64Value","value":5}）に包んで送るので、
// Firestore 用の intValue では map のまま読めず、常に既定値へ落ちる
// （vocabtest.go の Answers と同じ理由）。
func requestedSetSize(params, userData map[string]any) int {
	count, ok := callable.Int(params["count"])
	if !ok || count < 1 {
		return 1
	}
	return min(count, sentence.SetSizeFor(userData))
}

func runGenerateThaiSentence(
	ctx context.Context, uid string, params map[string]any, l lang.Lang,
	logData map[string]any, start time.Time,
) ([]*sentence.Sentence, error) {
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
		initial, err := ensureUserQuota(ctx, db, userRef)
		if err != nil {
			return nil, err
		}
		for k, v := range initial {
			userData[k] = v
		}
	}

	// 旧アプリの新規ユーザーにだけ、これまでのプレミアム体験を配る
	// （legacyTrialGrant のコメント）。
	clientUsesStoreTrial, _ := params["store_trial_paywall"].(bool)
	if needsLegacyTrial(userData, clientUsesStoreTrial) {
		granted, err := grantLegacyTrial(
			ctx, db, userRef, time.Now(), clientUsesStoreTrial,
		)
		if err != nil {
			return nil, err
		}
		for k, v := range granted {
			userData[k] = v
		}
	}

	// 実効プレミアム（課金 premium・体験トライアル・猶予期間・反映待ちの購入）
	// なら premium ロジック（テーマ選択・premiumプロンプト・語彙上限なし）で出す。
	// 判定は premium.IsEffectivePremium に集約する。配信（deliverDailySentence）・
	// クイズ・語彙テストと同じ関数を通し、経路ごとに権利の解釈がずれないようにする。
	// クライアントの申告（premium_trial）は見ない。
	usePremiumSpec := premium.IsEffectivePremium(userData, time.Now())

	// premium（トライアル含む）は回数を消費しない。例文は静的コーパスから出す
	// ようになり 1 本あたりの限界コストがほぼ 0 なので、残数を見る意味が無い。
	// free だけが remaining_sentences（残りセット数）で絞られる。
	remaining := intValue(userData["remaining_sentences"])
	if !usePremiumSpec && remaining <= 0 {
		logData["error"] = "QUOTA_EXCEEDED"
		logData["remainingSentences"] = remaining
		log.Printf("Quota exceeded: %s", logJSON(logData))
		return nil, errQuotaExceeded
	}

	// クォータ消費前の LLM 呼び出しを同一ユーザーが並行実行できないよう、
	// Firestore 上の期限付き lease でインスタンスをまたいで直列化する。
	leaseToken, err := acquireGenerationLease(ctx, db, userRef)
	if err != nil {
		return nil, err
	}
	defer releaseGenerationLease(ctx, db, userRef, leaseToken)

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

	// free の枠はセット数で数えるので、本数は残りに関係なく1セットぶん作る。
	count := requestedSetSize(params, userData)

	produced, err := producer.ProduceBatch(ctx, db, freqRank, sentence.ProduceRequest{
		UID:            uid,
		Params:         effectiveGenerationParams(params, usePremiumSpec),
		UsePremiumSpec: usePremiumSpec,
		EstimatedVocab: estimatedVocab,
		TestedVocab:    intValue(userData["vocab_test_vocab"]),
		Lang:           l,
		// LLM 生成分を判定し、不合格なら作り直す（待ち時間 +0.5 秒、作り直し時 +5 秒前後）。
		QualityCheck: generationQualityCheck(),
	}, count)
	if err != nil {
		return nil, err
	}
	if len(produced) == 0 { // CacheOnly=false では起きない
		return nil, errors.New("sentence generation returned nothing")
	}

	logData["requestedCount"] = count
	logData["generatedCount"] = len(produced)
	logData["uvmWords"] = len(produced[0].TargetWords)
	logData["chosenTopic"] = produced[0].ChosenTopic
	if produced[0].FromCache {
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
		for _, p := range produced {
			registerSentenceExposure(ctx, db, uid, p)
		}
		// 最新の実効権利を読み、真のfreeだけを従来どおり100語上限にする。
		uvm.SyncEstimatedVocab(ctx, db, uid, freqRank)
	}()

	if err := commitSentences(ctx, db, userRef, produced, usePremiumSpec, l,
		sentence.SupportsViewTracking(userData)); err != nil {
		log.Printf("Failed to save sentence to Firestore: %v", err)
		wg.Wait()
		return nil, err
	}

	sentences := make([]*sentence.Sentence, len(produced))
	for i, p := range produced {
		p.Sentence.TargetWords = p.TargetWords
		sentences[i] = p.Sentence
	}

	wg.Wait()
	return sentences, nil
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

// commitSentences はセット全部の保存とクォータ消費を 1 トランザクションで行う
// （sentence_handlers.py:_commit_sentences_transaction:296）。
//
// クォータは本数ぶん消費する。トランザクション内で残りが足りなければ
// 全部やめる（部分的に書いて部分的に課金する状態を作らない）。
func commitSentences(
	ctx context.Context, db *firestore.Client, userRef *firestore.DocumentRef,
	produced []*sentence.Produced, usePremiumSpec bool, l lang.Lang,
	trackViewed bool,
) error {
	refs := make([]*firestore.DocumentRef, len(produced))
	docs := make([]map[string]any, len(produced))
	for i, p := range produced {
		refs[i] = userRef.Collection("sentences").NewDoc()
		docs[i] = p.Sentence.BuildSentenceDoc(sentence.DocMeta{
			KeyWord:        p.TargetWords[0],
			UsePremiumSpec: usePremiumSpec,
			Lang:           l,
			FromCache:      p.FromCache,
			TrackViewed:    trackViewed,
			Quality:        p.Quality,
		})
	}

	if err := db.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		snap, err := tx.Get(userRef)
		userData := map[string]any{}
		if err == nil && snap.Exists() {
			userData = snap.Data()
		}
		if !usePremiumSpec && intValue(userData["remaining_sentences"]) < 1 {
			return errQuotaExceeded
		}
		for i, ref := range refs {
			if err := tx.Set(ref, docs[i]); err != nil {
				return err
			}
		}
		return tx.Update(userRef, sentenceCommitUpdate(userData, len(refs), !usePremiumSpec))
	}); err != nil {
		return err
	}

	// 保存できた doc ID をレスポンスへ載せる。クライアントはこれをローカルの
	// 主キーにし、読んだ例文へ既読（viewed）を書き戻す宛先にする。
	for i, p := range produced {
		p.Sentence.ID = refs[i].ID
	}
	return nil
}

// sentenceCommitUpdate は例文コミット時の users ドキュメント更新内容
// （sentence_handlers.py:_build_sentence_commit_update:277）。
//
// consumeQuota が false（premium・トライアル）のときは remaining_sentences を
// 触らない。free は本数によらず1セットで1減らす（remaining_sentences はセット数）。
// 生成本数の記録（sentence_generated_count）は tier によらず残す。
func sentenceCommitUpdate(
	userData map[string]any, count int, consumeQuota bool,
) []firestore.Update {
	updates := []firestore.Update{
		{Path: "daily_sentence_generated", Value: true},
		{Path: "last_active_at", Value: firestore.ServerTimestamp},
		{Path: "last_sentence_generated_at", Value: firestore.ServerTimestamp},
		{Path: "sentence_generated_count", Value: firestore.Increment(count)},
	}
	if consumeQuota {
		updates = append(updates,
			firestore.Update{Path: "remaining_sentences", Value: firestore.Increment(-1)})
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
//
// 新規は free で始まる。プレミアム体験はストアの無料トライアルへ移した
// （1.4.13〜）。旧アプリ向けの体験は初回生成で grantLegacyTrial が配る。
func ensureUserQuota(
	ctx context.Context, db *firestore.Client, userRef *firestore.DocumentRef,
) (map[string]any, error) {
	initial := map[string]any{
		"remaining_sentences":      quota.FreeDailySentences,
		"remaining_quizzes":        quota.FreeDailyQuizzes,
		"daily_sentence_generated": false,
	}
	result := initial
	created := false
	err := db.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		created = false
		result = initial
		snap, err := tx.Get(userRef)
		if err == nil && snap.Exists() {
			if _, ok := snap.Data()["remaining_sentences"]; ok {
				result = snap.Data()
				return nil
			}
		} else if err != nil && !isNotFoundErr(err) {
			return err
		}
		created = true
		return tx.Set(userRef, initial, firestore.MergeAll)
	})
	if err != nil {
		return nil, err
	}
	if created {
		log.Printf("Initial quota set (fallback) for user %s", userRef.ID)
	}
	return result, nil
}

// storeTrialAppVersion はストアの無料トライアルへ移った最初の版。
// これより前の版はオンボーディングの末尾で「プレミアムを2日間おためし」と
// 案内するので、その人にはサーバーの体験を配らないと案内が嘘になる。
var storeTrialAppVersion = [3]int{1, 4, 13}

// needsLegacyTrial は旧アプリの新規ユーザーで、まだ体験を配っていないか。
//
// 体験はもともと onUserCreate で配っていたが、その時点ではまだ版が分からない
// （app_version はアプリの起動時に書かれる）。旧アプリはオンボーディングの
// 直後に必ず例文を生成するので、初回生成で配れば案内と中身が一致する。
//
//   - 体験を一度も持っていない（premium_trial_expires_at が無い）
//   - まだ一度も生成していない（体験導入前からの既存ユーザーを除く）
//   - 新クライアントの store_trial_paywall 申告が無い
//   - 保存済みの版が 1.4.13 未満か、記録が無い（旧アプリ）
//
// app_version の書き込みは起動時の非同期処理なので、それだけで判定すると
// 新アプリの初回生成が先に着いたときに旧2日体験を誤付与する。
func needsLegacyTrial(userData map[string]any, clientUsesStoreTrial bool) bool {
	if clientUsesStoreTrial {
		return false
	}
	if _, ok := userData["premium_trial_expires_at"]; ok {
		return false
	}
	if _, ok := userData["first_generated_at"]; ok {
		return false
	}
	version, _ := userData["app_version"].(string)
	return appVersionBefore(version, storeTrialAppVersion)
}

// appVersionBefore は version（"1.4.12" 形式）が min より前か。
// 読めない値は前（旧アプリ）とみなす。
func appVersionBefore(version string, min [3]int) bool {
	parts := strings.Split(strings.TrimSpace(version), ".")
	if len(parts) != 3 {
		return true
	}
	for i, part := range parts {
		n, err := strconv.Atoi(part)
		if err != nil {
			return true
		}
		if n != min[i] {
			return n < min[i]
		}
	}
	return false
}

// grantLegacyTrial は旧アプリの新規ユーザーにプレミアム体験を配る。
// 以前 onUserCreate が入れていたのと同じ値。同時に呼ばれても二重に延ばさない。
func grantLegacyTrial(
	ctx context.Context, db *firestore.Client, userRef *firestore.DocumentRef, now time.Time,
	clientUsesStoreTrial bool,
) (map[string]any, error) {
	grant := map[string]any{
		// 体験中は premium と同じ回数を出す。
		"remaining_sentences": quota.PremiumDailySentences,
		"remaining_quizzes":   quota.PremiumDailyQuizzes,
		// 期限はクォータのリセット境界（JST 0:00）に揃える。premium パッケージと同じ規則。
		"premium_trial_expires_at": time.UnixMilli(
			premium.TrialExpiresAtMsFrom(now.UnixMilli(), quota.PremiumTrialDays)).UTC(),
		// 旧クライアント（〜1.3.15）がテーマを消さないための凍結値。減らさない。
		"premium_trial_remaining": quota.PremiumTrialSentences,
	}
	result := map[string]any{}
	err := db.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		result = map[string]any{}
		snap, err := tx.Get(userRef)
		if err != nil && !isNotFoundErr(err) {
			return err
		}
		if err == nil && snap.Exists() &&
			!needsLegacyTrial(snap.Data(), clientUsesStoreTrial) {
			return nil
		}
		result = grant
		return tx.Set(userRef, grant, firestore.MergeAll)
	})
	if err != nil {
		return nil, err
	}
	if len(result) > 0 {
		log.Printf("Legacy premium trial granted for user %s", userRef.ID)
	}
	return result, nil
}

func acquireGenerationLease(
	ctx context.Context, db *firestore.Client, userRef *firestore.DocumentRef,
) (string, error) {
	return acquireOperationLease(ctx, db, userRef, "sentence", generationLeaseDuration)
}

func acquireOperationLease(
	ctx context.Context, db *firestore.Client, userRef *firestore.DocumentRef,
	operation string, duration time.Duration,
) (string, error) {
	lockRef := userRef.Collection("generation_locks").Doc(operation)
	token := userRef.Collection("generation_locks").NewDoc().ID
	now := time.Now().UTC()
	err := db.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		snap, err := tx.Get(lockRef)
		if err == nil && snap.Exists() {
			expiresAt, _ := snap.Data()["expires_at"].(time.Time)
			if expiresAt.After(now) {
				return errGenerationInProgress
			}
		} else if err != nil && !isNotFoundErr(err) {
			return err
		}
		return tx.Set(lockRef, map[string]any{
			"token": token, "expires_at": now.Add(duration),
		})
	})
	return token, err
}

func releaseGenerationLease(
	ctx context.Context, db *firestore.Client, userRef *firestore.DocumentRef, token string,
) {
	releaseOperationLease(ctx, db, userRef, "sentence", token)
}

func releaseOperationLease(
	ctx context.Context, db *firestore.Client, userRef *firestore.DocumentRef,
	operation, token string,
) {
	cleanupCtx, cancel := context.WithTimeout(context.WithoutCancel(ctx), 5*time.Second)
	defer cancel()
	lockRef := userRef.Collection("generation_locks").Doc(operation)
	if err := db.RunTransaction(cleanupCtx, func(ctx context.Context, tx *firestore.Transaction) error {
		snap, err := tx.Get(lockRef)
		if isNotFoundErr(err) {
			return nil
		}
		if err != nil {
			return err
		}
		if current, _ := snap.Data()["token"].(string); current != token {
			return nil
		}
		return tx.Delete(lockRef)
	}); err != nil {
		log.Printf("generation lease release failed uid=%s: %v", userRef.ID, err)
	}
}

// effectiveGenerationParams は生成条件として LLM へ渡すパラメータを整える
// （sentence_handlers.py:_effective_generation_params:131）。
//
// テーマはクライアントの指定をそのまま使う。ヒアリング（interview.goal）
// からの決定も端末側で行う。free は自動選択に固定する。
func effectiveGenerationParams(params map[string]any, isPremium bool) map[string]any {
	out := map[string]any{}
	// プロンプトへ入る値はサーバー定義の選択肢だけを通す。未知キーや自由入力を
	// そのままコピーすると、premium の topic 経由で指示を注入できる。
	if isPremium {
		if topic, ok := params["topic"].(string); ok && generationTopicAllowed(topic) {
			out["topic"] = topic
		}
	}
	if frame, ok := params["timeFrame"].(string); ok &&
		slices.Contains(sentence.TimeFrames, frame) {
		out["timeFrame"] = frame
	}
	// 旧クライアント互換。現在の生成コアはこの2項目をプロンプトに使わないが、
	// 整形結果の契約は維持する。制御文字を含む自由入力は落とす。
	for _, key := range []string{"style", "emotion"} {
		if value, ok := params[key].(string); ok && len(value) <= 64 &&
			!strings.ContainsAny(value, "\r\n") {
			out[key] = value
		}
	}
	return out
}

func generationTopicAllowed(topic string) bool {
	if topic == "" || slices.Contains(sentence.Topics, topic) {
		return true
	}
	// まとめたテーマ（タイ暮らし・タイ旅行）。中身への解決は選定側で行う。
	if _, ok := sentence.TopicGroups[topic]; ok {
		return true
	}
	for _, configured := range sentence.Topics {
		if head, _, ok := strings.Cut(configured, "（"); ok && topic == head {
			return true
		}
	}
	return false
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
	// 参考例文はプロンプトの断片と、まとめたテーマの解決の両方に使う。
	shots := &themeshots.Builder{Ctx: ctx, Scenes: store}
	return &sentence.Producer{
		// 判定器が作れなくても生成は止めない（判定なしで動く）。
		Checker: newQualityChecker(ctx),
		Selector: &sentence.TargetWordSelector{
			Session: &uvm.SessionSelector{Emb: store},
			Groups:  shots,
		},
		Bank: &sentence.FreeBank{ProjectID: fbapp.ProjectID()},
		// premium は静的コーパスから出す。無い語だけ Service（LLM）へ落ちる。
		Corpus: &sentence.CorpusBank{ProjectID: fbapp.ProjectID()},
		// バンクの在庫が既出だった語も LLM 生成へ落とす（同じ文を二度出さない）。
		History: &sentence.FirestoreHistory{},
		Service: &sentence.Service{
			Gen:      client,
			Resolver: &sentence.Resolver{SubThemes: store},
			Drama:    &bldrama.Builder{Ctx: ctx, Shots: store},
			Shots:    shots,
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

// generationQualityCheck は通常生成で生成直後の品質判定を行うか。
// SENTENCE_QUALITY_CHECK=0 で止められる（Jev 障害時・待ち時間が問題になったときの逃げ道）。
func generationQualityCheck() bool {
	return envOr("SENTENCE_QUALITY_CHECK", "1") != "0"
}
