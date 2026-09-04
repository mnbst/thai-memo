package function

import (
	"context"
	"errors"
	"log"
	"math/rand"
	"net/http"
	"sort"
	"strconv"
	"time"

	"cloud.google.com/go/firestore"
	"firebase.google.com/go/v4/messaging"
	"google.golang.org/api/iterator"

	"github.com/mnbst/thai-memo/functions/go/internal/dailysentence"
	"github.com/mnbst/thai-memo/functions/go/internal/fbapp"
	"github.com/mnbst/thai-memo/functions/go/internal/lang"
	"github.com/mnbst/thai-memo/functions/go/internal/sentence"
	"github.com/mnbst/thai-memo/functions/go/internal/uvm"
)

// deliverDailySentence は daily_sentence_handlers.py の移植。
//
// 毎時起動し、ユーザーのローカル時刻が配信希望時刻に一致する対象へ、
// 通常生成と共通の生成コア（sentence.Producer.Produce）で例文を1件作って
// Firestore に書き、FCM で通知する。free はキャッシュのみで LLM を呼ばない
// （ミス時はターゲット語を引き直す）。premium と、プレミアム体験トライアル枠を
// 充てる配信は LLM 生成し、失敗時はキャッシュに退避する。
// 通知の送信成功後に露出登録（UVM）を行い、通常生成と語彙状態を揃える。
//
// dailyBatch と同じく HTTP トリガーのままにして、定期実行するかどうかは
// Cloud Scheduler ジョブ（Terraform 管理）の有無だけで決める。
func deliverDailySentenceHTTP(w http.ResponseWriter, r *http.Request) {
	if err := runDeliverDailySentence(r.Context(), time.Now().UTC()); err != nil {
		log.Printf("deliverDailySentence failed: %v", err)
		http.Error(w, "internal", http.StatusInternalServerError)
		return
	}
	_, _ = w.Write([]byte("ok"))
}

// notifier は FCM 送信の差し替え点。実装は messaging.Client。
type notifier interface {
	Send(ctx context.Context, message *messaging.Message) (string, error)
}

// sentenceProducer は生成コアの差し替え点。実装は sentence.Producer。
type sentenceProducer interface {
	Produce(ctx context.Context, db *firestore.Client, freqRank uvm.FreqRank,
		req sentence.ProduceRequest) (*sentence.Produced, error)
}

// deliverer は 1 時間分の配信に必要な依存をまとめる。
type deliverer struct {
	DB       *firestore.Client
	Producer sentenceProducer
	FreqRank uvm.FreqRank
	Notifier notifier
	// Rand はヒアリングからのテーマ抽選に使う。nil なら共有の乱数源。
	Rand *rand.Rand
}

func runDeliverDailySentence(ctx context.Context, now time.Time) error {
	db, err := fbapp.Firestore(ctx)
	if err != nil {
		return err
	}
	producer, err := newProducer(ctx)
	if err != nil {
		return err
	}
	freqRank, err := uvm.GetFreqRank(ctx, fbapp.ProjectID())
	if err != nil {
		return err
	}
	msg, err := fbapp.Messaging(ctx)
	if err != nil {
		return err
	}
	d := &deliverer{DB: db, Producer: producer, FreqRank: freqRank, Notifier: msg}

	delivered := 0
	reasons := map[string]int{}
	err = d.eachCandidate(ctx, now, func(uid string, userData map[string]any) {
		reason := dailysentence.DeliverySkipReason(userData, now)
		if reason == "" {
			reason = d.deliverOne(ctx, uid, userData, now)
		}
		if reason == "" {
			delivered++
		} else {
			reasons[reason]++
		}
	})

	// 内訳は「なぜ通知が届いていないのか」を後から追うための常設ログ。
	// 候補は notify_utc_hour で絞った後なので、母数はこの時刻の配信希望者だけ。
	skipped := 0
	keys := make([]string, 0, len(reasons))
	for k, v := range reasons {
		keys = append(keys, k)
		skipped += v
	}
	sort.Strings(keys)
	breakdown := ""
	for _, k := range keys {
		if breakdown != "" {
			breakdown += " "
		}
		breakdown += k + "=" + strconv.Itoa(reasons[k])
	}
	line := "daily_sentence: delivered=" + strconv.Itoa(delivered) + " skipped=" + strconv.Itoa(skipped)
	if breakdown != "" {
		line += " [" + breakdown + "]"
	}
	log.Print(line)
	return err
}

// eachCandidate はこの時刻に配信されうるユーザーだけを列挙する。
//
// users 全件を毎時読むと読み取りが 24×N/日 になるため、非正規化した
// notify_utc_hour（現地の配信希望時刻に対応するUTC時刻）で絞り込む。
// これで 1日あたり各ユーザー1回しか読まない。
//
// この値はあくまで足切り用で、配信の可否は従来どおり ShouldDeliver 内の
// ローカル時刻比較が最終判定を行う（値が古くても誤配信にはならない）。
// フィールドは dailyBatch が毎日全ユーザーに書き直すため、旧クライアントでも
// 1日以内に埋まる。
func (d *deliverer) eachCandidate(
	ctx context.Context, now time.Time, fn func(uid string, userData map[string]any),
) error {
	it := d.DB.Collection("users").
		Where("notify_utc_hour", "==", now.UTC().Hour()).
		Documents(ctx)
	defer it.Stop()
	for {
		doc, err := it.Next()
		if errors.Is(err, iterator.Done) {
			return nil
		}
		if err != nil {
			return err
		}
		fn(doc.Ref.ID, doc.Data())
	}
}

// picked は配信する例文と、その生成条件。
type picked struct {
	Produced       *sentence.Produced
	UsePremiumSpec bool
}

// buildSentence は配信する例文を作る。
//
// 生成コアは通常生成と共通の Producer.Produce。
// 訳文の言語はサーバー起点でリクエストが無いため、クライアントが
// users/{uid}.app_language にミラーした設定から解決する。渡し忘れると
// 既定値 ja に落ち、en ユーザーの配信だけ日本語になる
// （2026-08-14 実測: en ユーザーの配信例文10本が全て日本語訳だった）。
// free はキャッシュのみで LLM 原価をゼロに保つ。premium と、トライアル枠を充てる
// 配信（UsesPremiumTrial）は LLM で生成し、失敗した場合だけキャッシュに退避して
// 通知そのものは落とさない。
// premium のテーマはクライアントが users/{uid}.preferred_topic にミラーした
// 設定を使い、未設定（おまかせ）ならヒアリングの用途（interview.goal）から
// 決める。どちらも無ければ通常生成と同じく UVM の key_word から決める。
func (d *deliverer) buildSentence(
	ctx context.Context, uid string, userData map[string]any, now time.Time,
) *picked {
	l := lang.Resolve(userData["app_language"])

	if userData["tier"] == "premium" || dailysentence.UsesPremiumTrial(userData, now) {
		params := map[string]any{}
		// 本人が選んだテーマ > ヒアリングの用途 > key_word 起点の自動選出。
		preferred, _ := userData["preferred_topic"].(string)
		if preferred == "" {
			preferred = sentence.ResolveInterviewTopic(userData, d.intn)
		}
		if preferred != "" {
			params["topic"] = preferred
		}
		produced, err := d.Producer.Produce(ctx, d.DB, d.FreqRank, sentence.ProduceRequest{
			UID:            uid,
			Params:         params,
			UsePremiumSpec: true,
			EstimatedVocab: intValue(userData["estimated_vocab"]),
			TestedVocab:    intValue(userData["vocab_test_vocab"]),
			// premium は LLM 生成なので引き直さない（Produce の既定と同じ 1 周）。
			SelectRetry: 1,
			Lang:        l,
		})
		if err != nil {
			log.Printf("daily_sentence: premium generation failed for %s: %v", uid, err)
		} else if produced != nil {
			return &picked{Produced: produced, UsePremiumSpec: true}
		}
	}

	produced, err := d.Producer.Produce(ctx, d.DB, d.FreqRank, sentence.ProduceRequest{
		UID:            uid,
		Params:         map[string]any{},
		UsePremiumSpec: false,
		EstimatedVocab: min(intValue(userData["estimated_vocab"]), uvm.FreeTierMaxVocab),
		// free は測定値を使わない（GetSessionWords 側でも 0 に落とす）。
		TestedVocab: 0,
		CacheOnly:      true,
		SelectRetry:    dailysentence.MaxTargetWordRetry,
		Lang:           l,
	})
	if err != nil {
		log.Printf("daily_sentence: cached generation failed for %s: %v", uid, err)
		return nil
	}
	if produced == nil {
		return nil
	}
	return &picked{Produced: produced, UsePremiumSpec: false}
}

func (d *deliverer) intn(n int) int {
	if d.Rand != nil {
		return d.Rand.Intn(n)
	}
	return rand.Intn(n)
}

// errDeliveryNotDue はトランザクション内の再判定で配信条件を満たさなくなった。
var errDeliveryNotDue = errors.New("DELIVERY_NOT_DUE")

// deliveryStoppedError は段階が配信停止に達したことを表す。
//
// トランザクション内で update しても、エラーを返した時点で rollback され
// 書き込みごと捨てられるため、停止の記録はトランザクション外で行う。
type deliveryStoppedError struct {
	updates []firestore.Update
}

func (e *deliveryStoppedError) Error() string { return "DELIVERY_STOPPED" }

// commitDailySentence は例文docの書き込みとクォータ消費・段階更新を
// 1トランザクションで行う。
//
// 戻り値は (送信先トークン, 通知失敗時に段階を戻すための更新内容)。
//
// last_sentence_generated_at は書かない。あれは「次へ」押下＝反応のシグナルであり、
// 配信そのものを反応として数えてはいけない。
func (d *deliverer) commitDailySentence(
	ctx context.Context, userRef, sentenceRef *firestore.DocumentRef,
	sentenceData map[string]any, now time.Time,
) (token string, restore []firestore.Update, err error) {
	err = d.DB.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		userData := map[string]any{}
		if snap, gerr := tx.Get(userRef); gerr == nil && snap.Exists() {
			userData = snap.Data()
		}

		tok, rest, update, perr := dailyCommitPlan(userData, now)
		if perr != nil {
			return perr
		}
		token, restore = tok, rest

		if serr := tx.Set(sentenceRef, sentenceData); serr != nil {
			return serr
		}
		return tx.Update(userRef, update)
	})
	return token, restore, err
}

// dailyCommitPlan は最新の user doc から、コミット時の書き込み内容を決める。
//
// 戻り値は (送信先トークン, 通知失敗時に戻すための更新, users への更新)。
func dailyCommitPlan(userData map[string]any, now time.Time) (
	token string, restore, update []firestore.Update, err error,
) {
	// 外側の列挙結果は古い可能性があるため、二重配信を防ぐ正の判定は
	// トランザクション内の最新 user doc で行う。
	if !dailysentence.ShouldDeliver(userData, now) {
		return "", nil, nil, errDeliveryNotDue
	}

	tierUpdate := dailysentence.EvaluateResponse(userData)
	if tierUpdate.NotifyTier >= dailysentence.TierStopped {
		return "", nil, nil, &deliveryStoppedError{updates: append(
			[]firestore.Update{{Path: "last_notified_at", Value: firestore.ServerTimestamp}},
			tierUpdateFields(tierUpdate)...)}
	}

	token, _ = userData["fcm_token"].(string)
	restore = deliveryRestoreUpdate(userData)
	update = append([]firestore.Update{
		{Path: "remaining_sentences", Value: firestore.Increment(-1)},
		{Path: "daily_sentence_generated", Value: true},
		{Path: "last_notified_at", Value: firestore.ServerTimestamp},
	}, tierUpdateFields(tierUpdate)...)
	return token, restore, update, nil
}

func tierUpdateFields(u dailysentence.TierUpdate) []firestore.Update {
	return []firestore.Update{
		{Path: "notify_tier", Value: u.NotifyTier},
		{Path: "notify_tier_misses", Value: u.NotifyMisses},
	}
}

// deliveryRestoreUpdate は通知失敗時に段階を配信前へ戻すための更新内容。
//
// last_notified_at は元が無ければ削除する（Python の DELETE_FIELD）。
func deliveryRestoreUpdate(userData map[string]any) []firestore.Update {
	last := any(firestore.Delete)
	if v, ok := userData["last_notified_at"]; ok && !isZeroValue(v) {
		last = v
	}
	return []firestore.Update{
		{Path: "notify_tier", Value: intValue(userData["notify_tier"])},
		{Path: "notify_tier_misses", Value: intValue(userData["notify_tier_misses"])},
		{Path: "last_notified_at", Value: last},
	}
}

// isZeroValue は Python の falsy 相当（None / 空 / ゼロ値）。
func isZeroValue(v any) bool {
	switch t := v.(type) {
	case nil:
		return true
	case string:
		return t == ""
	case time.Time:
		return t.IsZero()
	case int64:
		return t == 0
	case float64:
		return t == 0
	case bool:
		return !t
	}
	return false
}

// buildNotification は通知メッセージを組み立てる。
//
// 複数行の本文は展開しないと切られるため、Android は BigText 相当の
// 表示になるよう優先度を上げ、iOS はロック画面で読み上げ枠を確保する。
func buildNotification(
	token, sentenceID string, sentenceData map[string]any, l lang.Lang,
) *messaging.Message {
	title, body := dailysentence.BuildNotificationText(sentenceData, l)
	return &messaging.Message{
		Token:        token,
		Notification: &messaging.Notification{Title: title, Body: body},
		Android: &messaging.AndroidConfig{
			Priority: "high",
			Notification: &messaging.AndroidNotification{
				Body:         body,
				DefaultSound: true,
			},
		},
		APNS: &messaging.APNSConfig{
			Payload: &messaging.APNSPayload{
				Aps: &messaging.Aps{Sound: "default"},
			},
		},
		Data: map[string]string{"type": "daily_sentence", "sentence_id": sentenceID},
	}
}

// rollbackDelivery は通知が届かなかった場合に配信をなかったことにする。
//
// 段階（notify_tier）も配信前に戻す。届いていない通知を無反応として数えると、
// ユーザーが身に覚えのないまま配信停止へ近づいてしまうため。
//
// deleteToken はトークン失効のときだけ true にする。権限不足や FCM 障害で
// トークンまで消すと、原因を直しても配信対象から永久に外れてしまう
// （再登録はアプリ再起動待ちになる）。
func rollbackDelivery(
	ctx context.Context, userRef, sentenceRef *firestore.DocumentRef,
	restore []firestore.Update, deleteToken bool,
) {
	if _, err := sentenceRef.Delete(ctx); err != nil {
		log.Printf("daily_sentence: rollback の例文削除に失敗: %v", err)
	}
	if _, err := userRef.Update(ctx, rollbackUpdate(restore, deleteToken)); err != nil {
		log.Printf("daily_sentence: rollback の users 更新に失敗: %v", err)
	}
}

func rollbackUpdate(restore []firestore.Update, deleteToken bool) []firestore.Update {
	updates := []firestore.Update{
		{Path: "remaining_sentences", Value: firestore.Increment(1)},
		{Path: "daily_sentence_generated", Value: false},
	}
	if deleteToken {
		updates = append(updates,
			firestore.Update{Path: "fcm_token", Value: firestore.Delete})
	}
	return append(updates, restore...)
}

// deliverOne は1件配信する。配信できたら ""、できなければ理由を返す（ログ集計用）。
func (d *deliverer) deliverOne(
	ctx context.Context, uid string, userData map[string]any, now time.Time,
) string {
	userRef := d.DB.Collection("users").Doc(uid)

	if userData["tier"] == "premium" || dailysentence.UsesPremiumTrial(userData, now) {
		// LLM を叩く前に最新状態を読み直す。二重配信自体はトランザクションで
		// 弾けるが、生成コストは commit 前に払ってしまうため窓を狭めておく。
		userData = map[string]any{}
		if snap, err := userRef.Get(ctx); err == nil && snap.Exists() {
			userData = snap.Data()
		}
		if reason := dailysentence.DeliverySkipReason(userData, now); reason != "" {
			return "stale:" + reason
		}
	}

	p := d.buildSentence(ctx, uid, userData, now)
	if p == nil {
		log.Printf("daily_sentence: no sentence available for %s", uid)
		return "no_sentence"
	}

	sentenceData := p.Produced.Sentence.BuildSentenceDoc(
		p.Produced.TargetWords[0], p.UsePremiumSpec)
	sentenceData["daily"] = true
	sentenceData["daily_date"] = dailysentence.LocalDate(userData["timezone"], now)
	sentenceRef := userRef.Collection("sentences").NewDoc()

	token, restore, err := d.commitDailySentence(ctx, userRef, sentenceRef, sentenceData, now)
	if err != nil {
		var stopped *deliveryStoppedError
		switch {
		case errors.Is(err, errDeliveryNotDue):
			return "not_due_at_commit"
		case errors.As(err, &stopped):
			if _, uerr := userRef.Update(ctx, stopped.updates); uerr != nil {
				log.Printf("daily_sentence: 配信停止の記録に失敗 %s: %v", uid, uerr)
			}
			return "backoff_stopped_now"
		}
		log.Printf("daily_sentence: commit failed for %s: %v", uid, err)
		return "error"
	}

	// key_word とその意味を通知に載せるため、整形済みの sentenceData を渡す。
	msg := buildNotification(token, sentenceRef.ID, sentenceData,
		lang.Resolve(userData["app_language"]))
	if _, err := d.Notifier.Send(ctx, msg); err != nil {
		if messaging.IsUnregistered(err) {
			log.Printf("daily_sentence: token unregistered, rolling back %s", uid)
			rollbackDelivery(ctx, userRef, sentenceRef, restore, true)
			return "token_unregistered"
		}
		// トークン失効以外の送信失敗（権限・FCM障害など）。ここを素通りすると
		// 通知が飛ばないのにクォータと当日フラグだけ消費されてしまう。
		log.Printf("daily_sentence: send failed for %s: %v", uid, err)
		rollbackDelivery(ctx, userRef, sentenceRef, restore, false)
		return "send_failed"
	}

	// 露出登録は通知が届いた後にだけ行う。配信をロールバックしても
	// UVM の P 微増は巻き戻せないため、送信成功を確認してから登録する。
	registerSentenceExposure(ctx, d.DB, uid, p.Produced)
	// 上限の判定は配信スペックの判定（deliverOne 冒頭）と揃える。tier だけで
	// 見ると、トライアル中の estimated_vocab が毎回 100 へ切り戻される。
	maxVocab := -1
	if userData["tier"] != "premium" && !dailysentence.UsesPremiumTrial(userData, now) {
		maxVocab = uvm.FreeTierMaxVocab
	}
	uvm.SyncEstimatedVocab(ctx, d.DB, uid, d.FreqRank, maxVocab)
	return ""
}
