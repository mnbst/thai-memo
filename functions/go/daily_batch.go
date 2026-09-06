package function

import (
	"context"
	"log"
	"net/http"
	"sort"
	"sync"
	"time"

	"cloud.google.com/go/firestore"
	"firebase.google.com/go/v4/auth"
	"google.golang.org/api/iterator"

	"github.com/mnbst/thai-memo/functions/go/internal/fbapp"
	"github.com/mnbst/thai-memo/functions/go/internal/notify"
	"github.com/mnbst/thai-memo/functions/go/internal/premium"
	"github.com/mnbst/thai-memo/functions/go/internal/quota"
	"github.com/mnbst/thai-memo/functions/go/internal/subscription"
	"github.com/mnbst/thai-memo/functions/go/internal/userdata"
)

// dailyBatch は functions/javascript/src/dailyBatch.ts の移植。
//
// 毎日 JST 0:00 に実行され、以下を行う:
//  1. 非アクティブな匿名ユーザーと孤児 doc の削除
//  2. 重複 fcm_token の掃除
//  3. ユーザーごとの日次クォータをリセット
//  4. UVM の P 値を減衰
//  5. 30日以上前の古い例文を削除
//
// subscriptionStatus と同じく常に HTTP トリガーで、定期実行するかどうかは
// Cloud Scheduler ジョブ（Terraform 管理）の有無だけで決める。

// dailyBatchConcurrency は JS 版の CONCURRENCY。
const dailyBatchConcurrency = 5

// anonInactiveDays はこの日数以上トークン更新がない匿名ユーザーを削除対象とする。
//
// 匿名 doc は端末の fcm_token を握ったまま残りやすい（匿名で試してから
// サインインすると解除経路を通らない）。重複トークン掃除で通知の重複自体は
// 止まるため、残骸を残す不利より復帰の取りこぼしを避けることを優先する。
//
// UI（sign_in_reminder_banner）はここより短い「3日」を告知しており、意図的に
// 揃えていない。告知どおり3日で消していたところ、prod の匿名ユーザーには
// 4〜6日空けてから戻ってくる層が実在し（2026-08-03 時点で復帰11人中5人）、
// その進捗を消してしまっていた。告知は復帰を促す締切として短いまま残し、
// 実際の保持は7日に伸ばして復帰余地を確保する。短く告知して長く保つ方向の
// ずれなので、ユーザーの不利にはならない。縮めるときは必ずUIを先に直すこと。
const anonInactiveDays = 7

// maxAnonDeletionsPerRun は1回の実行で削除する匿名ユーザーの上限（負荷平準化）。
const maxAnonDeletionsPerRun = 500

// UVM P値減衰の定数。
//
// key_word の候補が未出題語（UVM 未登録 or P=0）で埋まらなくなると、
// GetSessionWords は 1-p 重み（UnknownWeights）にフォールバックして既習語から
// 引き直す。P を毎日 pDecayPerDay ずつ減衰させておくと、そのとき放置された語が
// 復習されたばかりの語より優先される。全登録単語に適用する。
const (
	pDecayPerDay = 0.001
	pDecayMin    = 0.0
)

// sentenceRetention は例文を保持する期間。これより古いものは削除する。
const sentenceRetentionDays = 30

func dailyBatchHTTP(w http.ResponseWriter, r *http.Request) {
	if err := runDailyBatch(r.Context()); err != nil {
		log.Printf("dailyBatch failed: %v", err)
		http.Error(w, "internal", http.StatusInternalServerError)
		return
	}
	_, _ = w.Write([]byte("ok"))
}

func runDailyBatch(ctx context.Context) error {
	log.Print("dailyBatch started")

	db, err := fbapp.Firestore(ctx)
	if err != nil {
		return err
	}
	authClient, err := fbapp.Auth(ctx)
	if err != nil {
		return err
	}

	now := time.Now()

	// 本体処理の前に匿名ユーザーを完全削除する。
	// 掃除の失敗が本体処理を巻き込まないよう隔離する。
	if err := cleanupAnonymousUsers(ctx, db, authClient, now); err != nil {
		log.Printf("cleanupAnonymousUsers failed: %v", err)
	}

	users, err := allUserDocs(ctx, db)
	if err != nil {
		return err
	}
	if len(users) == 0 {
		log.Print("No users found")
		return nil
	}

	clearDuplicateFcmTokens(ctx, db, users)

	// dailyBatchConcurrency 件ずつ並行処理。1件失敗しても継続する
	// （JS の Promise.allSettled と同じ）。
	for i := 0; i < len(users); i += dailyBatchConcurrency {
		end := min(i+dailyBatchConcurrency, len(users))

		var wg sync.WaitGroup
		for _, doc := range users[i:end] {
			wg.Add(1)
			go func(doc *firestore.DocumentSnapshot) {
				defer wg.Done()
				if err := resetQuota(ctx, db, doc, now); err != nil {
					log.Printf("resetQuota failed uid=%s: %v", doc.Ref.ID, err)
					return
				}
				if err := decayUvmP(ctx, db, doc.Ref.ID); err != nil {
					log.Printf("decayUvmP failed uid=%s: %v", doc.Ref.ID, err)
				}
			}(doc)
		}
		wg.Wait()
	}

	// 品質監査は古い例文の削除より先に回す。監査対象は直近24時間ぶんなので
	// 実際には競合しないが、順序に依存させない。
	if err := runSentenceAudit(ctx, db, users, now); err != nil {
		// 監査は学習用の記録であって本体処理ではない。落ちてもバッチは通す。
		log.Printf("runSentenceAudit failed: %v", err)
	}

	if err := cleanOldSentences(ctx, db, now); err != nil {
		return err
	}

	log.Print("dailyBatch completed")
	return nil
}

func allUserDocs(ctx context.Context, db *firestore.Client) ([]*firestore.DocumentSnapshot, error) {
	it := db.Collection("users").Documents(ctx)
	defer it.Stop()

	var out []*firestore.DocumentSnapshot
	for {
		doc, err := it.Next()
		if err == iterator.Done {
			return out, nil
		}
		if err != nil {
			return nil, err
		}
		out = append(out, doc)
	}
}

// ---------------------------------------------------------------------------
// 1. 匿名ユーザー・孤児 doc の掃除
// ---------------------------------------------------------------------------

// cleanupAnonymousUsers は非アクティブな匿名ユーザーと、Auth に存在しない
// 孤児 doc を完全削除する。
//
// 手順:
//  1. Auth 全ユーザーを列挙し、全 uid を記録しつつ、匿名（providerData 空 =
//     Google/Apple 未リンク）かつ最終トークン更新が anonInactiveDays 日以上前の
//     ユーザーを削除
//  2. Firestore の users を走査し、Auth に無い doc（= 削除済みユーザーの
//     キャッシュトークンで復活した孤児 doc）の Firestore データを削除
//
// 削除は Firestore データ同期削除 → Auth ユーザー削除の順で「完全に消えた状態」を
// 保証する。onDelete トリガー任せだと非同期のため本体走査時に doc が残る。
// onDelete の再削除は冪等で無害。1回あたり maxAnonDeletionsPerRun 件で打ち切る。
func cleanupAnonymousUsers(
	ctx context.Context,
	db *firestore.Client,
	authClient *auth.Client,
	now time.Time,
) error {
	authUids := map[string]bool{}
	inactiveCutoff := now.Add(-anonInactiveDays * 24 * time.Hour).UnixMilli()

	var deleted int
	var capped bool

	// 1. Auth 全ユーザー列挙 → 非アクティブな匿名を削除、全 uid を記録
	it := authClient.Users(ctx, "")
	for {
		user, err := it.Next()
		if err == iterator.Done {
			break
		}
		if err != nil {
			return err
		}

		authUids[user.UID] = true

		// 匿名判定: 外部プロバイダ（Google/Apple等）が一切紐づいていない
		if len(user.ProviderUserInfo) > 0 {
			continue
		}

		// 非アクティブ判定: 最終トークン更新（なければ最終サインイン、
		// それも無ければ作成時刻）が anonInactiveDays 日以内なら残す。
		if lastActiveMillis(user) > inactiveCutoff {
			continue
		}
		if capped {
			continue
		}

		if _, err := userdata.DeleteFirestoreData(ctx, db, user.UID); err != nil {
			log.Printf("Failed to delete anonymous user %s: %v", user.UID, err)
		} else if err := authClient.DeleteUser(ctx, user.UID); err != nil {
			log.Printf("Failed to delete anonymous user %s: %v", user.UID, err)
		} else {
			deleted++
		}

		if deleted >= maxAnonDeletionsPerRun {
			capped = true
		}
	}

	// 2. 孤児 doc 掃除: Auth に存在しない users doc の Firestore データを削除
	var orphans int
	users, err := allUserDocs(ctx, db)
	if err != nil {
		return err
	}
	for _, doc := range users {
		if authUids[doc.Ref.ID] {
			continue
		}
		if _, err := userdata.DeleteFirestoreData(ctx, db, doc.Ref.ID); err != nil {
			log.Printf("Failed to delete orphan doc %s: %v", doc.Ref.ID, err)
			continue
		}
		orphans++
	}

	log.Printf("cleanupAnonymousUsers: deleted %d anonymous user(s), %d orphan doc(s)",
		deleted, orphans)
	return nil
}

// lastActiveMillis は JS の
// `Date.parse(lastRefreshTime ?? lastSignInTime ?? creationTime)` 相当。
// Admin Go SDK は同じ値をエポックミリ秒で持っており、未設定は 0。
func lastActiveMillis(user *auth.ExportedUserRecord) int64 {
	if user.UserMetadata == nil {
		return 0
	}
	if user.UserMetadata.LastRefreshTimestamp != 0 {
		return user.UserMetadata.LastRefreshTimestamp
	}
	if user.UserMetadata.LastLogInTimestamp != 0 {
		return user.UserMetadata.LastLogInTimestamp
	}
	return user.UserMetadata.CreationTimestamp
}

// ---------------------------------------------------------------------------
// 2. 重複 fcm_token の掃除
// ---------------------------------------------------------------------------

// activityFields は最終アクティブとみなすタイムスタンプ（新しいものが勝つ）。
var activityFields = []string{
	"last_active_at",
	"last_sentence_generated_at",
	"last_notified_at",
	"last_opened_at",
}

func lastActivityMillis(data map[string]any) int64 {
	var latest int64
	for _, field := range activityFields {
		t, ok := data[field].(time.Time)
		if !ok {
			continue
		}
		if ms := t.UnixMilli(); ms > latest {
			latest = ms
		}
	}
	return latest
}

// tokenOwner は duplicateTokenUids の入力。
type tokenOwner struct {
	ID   string
	Data map[string]any
}

// duplicateTokenUids は同じ fcm_token を複数の users doc が持っている場合に、
// 登録を残す1件を除いた uid を返す。
//
// fcm_token は端末単位の値なのに users/{uid} に持たせているため、同じ端末で
// アカウントを切り替えると旧 doc に生きたトークンが残り、その端末には使った
// アカウントの数だけ毎日例文が届く（匿名で試してからサインインした場合など）。
// クライアントはサインアウト時に自分の登録を解除するが、アプリ削除・再インストールや
// 匿名からの移行では解除が走らないため、ここを最後の砦にする。
//
// 残すのは最終アクティブが最も新しい doc。同着は uid 順で決めて結果を安定させる。
func duplicateTokenUids(users []tokenOwner) []string {
	type entry struct {
		id       string
		activity int64
	}

	byToken := map[string][]entry{}
	var tokenOrder []string // map の反復順に依存しないよう出現順を保つ

	for _, user := range users {
		token, ok := user.Data["fcm_token"].(string)
		if !ok || token == "" {
			continue
		}
		if _, seen := byToken[token]; !seen {
			tokenOrder = append(tokenOrder, token)
		}
		byToken[token] = append(byToken[token], entry{
			id:       user.ID,
			activity: lastActivityMillis(user.Data),
		})
	}

	var stale []string
	for _, token := range tokenOrder {
		group := byToken[token]
		if len(group) < 2 {
			continue
		}
		sort.SliceStable(group, func(i, j int) bool {
			if group[i].activity != group[j].activity {
				return group[i].activity > group[j].activity
			}
			return group[i].id < group[j].id
		})
		for _, e := range group[1:] {
			stale = append(stale, e.id)
		}
	}
	return stale
}

// clearDuplicateFcmTokens は重複登録のうち最新の1件以外から fcm_token を消す。
func clearDuplicateFcmTokens(
	ctx context.Context,
	db *firestore.Client,
	docs []*firestore.DocumentSnapshot,
) {
	owners := make([]tokenOwner, 0, len(docs))
	for _, doc := range docs {
		owners = append(owners, tokenOwner{ID: doc.Ref.ID, Data: doc.Data()})
	}

	stale := duplicateTokenUids(owners)
	if len(stale) == 0 {
		return
	}

	for _, uid := range stale {
		_, err := db.Collection("users").Doc(uid).Update(ctx, []firestore.Update{
			{Path: "fcm_token", Value: firestore.Delete},
			{Path: "daily_reminder_enabled", Value: false},
		})
		if err != nil {
			log.Printf("Failed to clear duplicate fcm_token for %s: %v", uid, err)
		}
	}
	log.Printf("clearDuplicateFcmTokens: cleared %d duplicate registration(s)", len(stale))
}

// ---------------------------------------------------------------------------
// 3. 日次クォータのリセット
// ---------------------------------------------------------------------------

// resetQuota は tier に応じて remaining_sentences / remaining_quizzes を日次リセットする。
func resetQuota(
	ctx context.Context,
	db *firestore.Client,
	doc *firestore.DocumentSnapshot,
	now time.Time,
) error {
	payload := quotaResetPayload(doc.Ref.ID, doc.Data(), now)
	_, err := db.Collection("users").Doc(doc.Ref.ID).Set(ctx, payload, firestore.MergeAll)
	return err
}

// quotaResetPayload は resetQuota が書き込む内容を組み立てる（Firestore に触らない）。
//
// ストア通知の取りこぼし対策として、subscription.expires_at を24時間以上
// 過ぎた premium は free に落とす。猶予期間中（grace_period）は維持するが、
// GracePeriodMax を過ぎたら通知の取りこぼしとみなして落とす。
// ストア購入なのに expires_at を持たない premium も、期限判定が効かず
// 永久 premium になるため落とす。
// subscription フィールドがない premium（dev環境の手動設定等）は対象外。
func quotaResetPayload(uid string, userData map[string]any, now time.Time) map[string]any {
	tier, _ := userData["tier"].(string)
	if tier == "" {
		tier = "free"
	}
	sub, _ := userData["subscription"].(map[string]any)
	expiresAt, hasExpiresAt := sub["expires_at"].(time.Time)
	isStoreSubscription := subscription.IsStorePlatform(sub["platform"])

	// 猶予期間中は期限超過が前提なので、通常より長い上限で判定する
	margin := subscription.ExpiryDemotionMargin
	if status, _ := sub["status"].(string); status == "grace_period" {
		margin = subscription.GracePeriodMax
	}

	subscriptionLapsed := tier == "premium"
	if subscriptionLapsed {
		if hasExpiresAt {
			subscriptionLapsed = now.Sub(expiresAt) > margin
		} else {
			// ストア購入で expires_at がない = 期限判定が働かないので premium を維持しない
			subscriptionLapsed = isStoreSubscription
		}
	}

	isPremium := tier == "premium" && !subscriptionLapsed
	// トライアル中は課金 premium と同じ回数を出す。
	trialActive := premium.IsTrialActive(userData, now)
	effectivePremium := isPremium || trialActive

	sentenceResetValue := quota.FreeDailySentences
	quizResetValue := quota.FreeDailyQuizzes
	if effectivePremium {
		sentenceResetValue = quota.PremiumDailySentences
		quizResetValue = quota.PremiumDailyQuizzes
	}

	payload := map[string]any{
		"remaining_sentences":      sentenceResetValue,
		"remaining_quizzes":        quizResetValue,
		"daily_sentence_generated": false,
	}

	// 配信バッチが時刻でクエリできるよう、毎日ここで作り直す。全ユーザーを
	// どのみち走査しているので追加の読み取りは発生せず、端末の移動や DST 切り替え、
	// 旧クライアントからの設定変更にも1日以内に追従する。
	// 算出不能（DST春の飛び時刻）なら既存値を維持する。
	if utcHour, ok := notify.UTCHour(
		userData["timezone"], userData["preferred_generation_hour"], now,
	); ok {
		payload["notify_utc_hour"] = utcHour
	}

	// 体験終了ダイアログは「回数が free に戻ってから」出したい。期限切れ後の最初の
	// リセットでここに刻み、クライアントはこの時刻の有無だけを見る。
	if !isPremium && premium.IsTrialExpired(userData, now) &&
		userData["premium_trial_ended_at"] == nil {
		payload["premium_trial_ended_at"] = firestore.ServerTimestamp
	}

	// 期限を JST 0:00（このリセットの境界）へ切り上げて揃える。既に揃っていれば
	// 書き換えは起きない。1.3.14 以前は期限そのものを見て体験終了を知らせるため、
	// 揃えておかないと「まだ premium の回数が残っている日」に終了を告げてしまう。
	if trialExpiresAt, ok := premium.TrialExpiresAtMs(userData); trialActive && ok {
		if aligned := premium.CeilToJSTMidnight(trialExpiresAt); aligned != trialExpiresAt {
			payload["premium_trial_expires_at"] = time.UnixMilli(aligned)
		}
	}

	if subscriptionLapsed {
		log.Printf("resetQuota: demoting lapsed premium user %s", uid)
		payload["tier"] = "free"
		payload["subscription"] = map[string]any{"status": "expired"}
	}

	return payload
}

// ---------------------------------------------------------------------------
// 4. UVM の P 値減衰
// ---------------------------------------------------------------------------

// decayUvmP は全登録 UVM 語に対し P 減衰を適用する。
func decayUvmP(ctx context.Context, db *firestore.Client, uid string) error {
	it := db.Collection("users").Doc(uid).Collection("uvm").Documents(ctx)
	defer it.Stop()

	bw := db.BulkWriter(ctx)
	var total int

	for {
		doc, err := it.Next()
		if err == iterator.Done {
			break
		}
		if err != nil {
			return err
		}

		p := floatField(doc.Data()["p"])
		if p <= pDecayMin {
			continue
		}

		newP := max(pDecayMin, p-pDecayPerDay)
		if _, err := bw.Update(doc.Ref, []firestore.Update{
			{Path: "p", Value: newP},
		}); err != nil {
			return err
		}
		total++
	}

	// BulkWriter は 500 件制限を自分でさばくので、JS のような手動分割は要らない。
	bw.End()

	if total > 0 {
		log.Printf("decayUvmP: uid=%s, updated %d word(s)", uid, total)
	}
	return nil
}

// floatField は Firestore の数値を float64 にする。整数は int64 で返るため。
// JS の `?? 0` と同じく、数値以外・未設定は 0 とみなす。
func floatField(v any) float64 {
	switch n := v.(type) {
	case float64:
		return n
	case int64:
		return float64(n)
	}
	return 0
}

// ---------------------------------------------------------------------------
// 5. 古い例文の削除
// ---------------------------------------------------------------------------

// cleanOldSentences は sentenceRetentionDays 日以上前の例文を全ユーザーから削除する。
func cleanOldSentences(ctx context.Context, db *firestore.Client, now time.Time) error {
	cutoff := oldSentenceCutoff(now)

	users, err := allUserDocs(ctx, db)
	if err != nil {
		return err
	}

	for _, userDoc := range users {
		if err := deleteOldSentencesFor(ctx, db, userDoc.Ref.ID, cutoff); err != nil {
			return err
		}
	}
	return nil
}

// deleteOldSentencesFor は1ユーザーぶんの古い例文を消す。
// 全走査と分けておくと、テストから捨て uid だけを対象に呼べる。
func deleteOldSentencesFor(
	ctx context.Context, db *firestore.Client, uid string, cutoff time.Time,
) error {
	it := db.Collection("users").Doc(uid).Collection("sentences").
		Where("created_at", "<", cutoff).
		Documents(ctx)
	defer it.Stop()

	bw := db.BulkWriter(ctx)
	var deleted int
	for {
		doc, err := it.Next()
		if err == iterator.Done {
			break
		}
		if err != nil {
			return err
		}
		if _, err := bw.Delete(doc.Ref); err != nil {
			return err
		}
		deleted++
	}
	bw.End()

	if deleted > 0 {
		log.Printf("cleanOldSentences: uid=%s, deleted %d sentence(s)", uid, deleted)
	}
	return nil
}

// oldSentenceCutoff は削除境界（この時刻より前の created_at を消す）を求める。
//
// JS 版は nowJST()（= now + 9h）から30日引き、setHours(0,0,0,0) で「その日の
// 0:00」に丸めてから 9h 引いて UTC に戻していた。setHours はプロセスのローカル
// タイムゾーンで効くので、この式が JST 0:00 の境界になるのは実行環境の TZ が
// UTC のとき（Cloud Functions がそう）だけ。Go 版は UTC 固定で明示的に書く。
func oldSentenceCutoff(now time.Time) time.Time {
	jstNow := now.UTC().Add(9 * time.Hour)
	d := jstNow.AddDate(0, 0, -sentenceRetentionDays)
	midnight := time.Date(d.Year(), d.Month(), d.Day(), 0, 0, 0, 0, time.UTC)
	return midnight.Add(-9 * time.Hour)
}
