package function

import (
	"context"
	"errors"
	"log"
	"math/rand"
	"net/http"
	"sort"
	"strconv"
	"sync"
	"time"

	"cloud.google.com/go/firestore"
	"firebase.google.com/go/v4/messaging"
	"google.golang.org/api/iterator"

	"github.com/mnbst/thai-memo/functions/go/internal/dailysentence"
	"github.com/mnbst/thai-memo/functions/go/internal/fbapp"
	"github.com/mnbst/thai-memo/functions/go/internal/lang"
	"github.com/mnbst/thai-memo/functions/go/internal/premium"
	"github.com/mnbst/thai-memo/functions/go/internal/sentence"
	"github.com/mnbst/thai-memo/functions/go/internal/uvm"
)

// 外部 LLM・FCM と Firestore の突発負荷を抑えつつ、候補ユーザーを並行配信する。
const dailySentenceConcurrency = 5

// deliverDailySentence は daily_sentence_handlers.py の移植。
//
// 毎時起動し、ユーザーのローカル時刻が配信希望時刻に一致する対象へ、
// 通常生成と共通の生成コア（sentence.Producer.ProduceBatch）で例文を作って
// Firestore に書き、FCM で通知する（通知はセットで1通）。
// 本数は 1.4.8 以降のクライアントなら5本、旧版は従来どおり1本
// （dailysentence.BatchSize）。例文→確認クイズ→まとめクイズのサイクルを
// 1日で一巡させるための設計。docs/design_daily_sentence_batch.md を参照。
// free はキャッシュのみで LLM を呼ばない（ミス時はターゲット語を引き直す）。
// premium と、プレミアム体験トライアル枠を充てる配信は LLM 生成し、
// 失敗時はキャッシュに退避する。
// 通知の送信成功後に露出登録（UVM）を行い、通常生成と語彙状態を揃える。
//
// dailyBatch と同じく HTTP トリガーのままにして、定期実行するかどうかは
// Cloud Scheduler ジョブ（Terraform 管理）の有無だけで決める。
func deliverDailySentenceHTTP(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method Not Allowed", http.StatusMethodNotAllowed)
		return
	}
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
	ProduceBatch(ctx context.Context, db *firestore.Client, freqRank uvm.FreqRank,
		req sentence.ProduceRequest, n int) ([]*sentence.Produced, error)
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
	type candidate struct {
		uid  string
		data map[string]any
	}
	jobs := make(chan candidate, dailySentenceConcurrency)
	var wg sync.WaitGroup
	var resultMu sync.Mutex
	for range dailySentenceConcurrency {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for c := range jobs {
				reason := dailysentence.DeliverySkipReason(c.data, now)
				if reason == "" {
					reason = d.deliverOne(ctx, c.uid, c.data, now)
				}
				resultMu.Lock()
				if reason == "" {
					delivered++
				} else {
					reasons[reason]++
				}
				resultMu.Unlock()
			}
		}()
	}
	err = d.eachCandidate(ctx, now, func(uid string, userData map[string]any) {
		jobs <- candidate{uid: uid, data: userData}
	})
	close(jobs)
	wg.Wait()

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

// pickedSet は配信する例文セットと、その生成条件。
type pickedSet struct {
	Produced       []*sentence.Produced
	UsePremiumSpec bool
	// Lang は訳文の言語（保存する doc に残す）。
	Lang lang.Lang
}

// buildSentences は配信する例文を n 本作る。
//
// 生成コアは通常生成と共通の Producer.ProduceBatch（単語選定1回・生成は語ごとに並列）。
// テーマは premium のおまかせだけセット内で散る（sentence.SelectTargetWords）。
// n 本に満たなくても、揃ったぶんだけ配信する。
// 訳文の言語はサーバー起点でリクエストが無いため、クライアントが
// users/{uid}.app_language にミラーした設定から解決する。渡し忘れると
// 既定値 ja に落ち、en ユーザーの配信だけ日本語になる
// （2026-08-14 実測: en ユーザーの配信例文10本が全て日本語訳だった）。
// free はキャッシュのみで LLM 原価をゼロに保つ。実効プレミアム
// （premium.IsEffectivePremium: 課金・体験トライアル・猶予期間・反映待ちの購入）は
// LLM で生成し、失敗した場合だけキャッシュに退避して通知そのものは落とさない。
// 回数消費の判定（consumeQuota）と同じ関数を使い、「回数は premium 扱いなのに
// 中身は free 品質」のような食い違いを作らない。
// premium のテーマはクライアントが users/{uid}.preferred_topic にミラーした
// 設定を使い、未設定（おまかせ）ならヒアリングの用途（interview.goal）から
// 決める。どちらも無ければ通常生成と同じく UVM の key_word から決める。
func (d *deliverer) buildSentences(
	ctx context.Context, uid string, userData map[string]any, now time.Time, n int,
) *pickedSet {
	l := lang.Resolve(userData["app_language"])

	if premium.IsEffectivePremium(userData, now) {
		params := map[string]any{}
		// 本人が選んだテーマ > ヒアリングの用途 > key_word 起点の自動選出。
		preferred, _ := userData["preferred_topic"].(string)
		if preferred == "" {
			preferred = sentence.ResolveInterviewTopic(userData, d.intn)
		}
		if preferred != "" {
			params["topic"] = preferred
		}
		produced, err := d.Producer.ProduceBatch(ctx, d.DB, d.FreqRank, sentence.ProduceRequest{
			UID:            uid,
			Params:         params,
			UsePremiumSpec: true,
			EstimatedVocab: intValue(userData["estimated_vocab"]),
			TestedVocab:    intValue(userData["vocab_test_vocab"]),
			// premium は LLM 生成なので引き直さない（Produce の既定と同じ 1 周）。
			SelectRetry: 1,
			Lang:        l,
			// 配信はユーザーを待たせないので、LLM 生成分を判定して不合格なら作り直す。
			QualityCheck: deliveryQualityCheck(),
		}, n)
		if err != nil {
			log.Printf("daily_sentence: premium generation failed for %s: %v", uid, err)
		} else if len(produced) > 0 {
			return &pickedSet{Produced: produced, UsePremiumSpec: true, Lang: l}
		}
	}

	produced, err := d.Producer.ProduceBatch(ctx, d.DB, d.FreqRank, sentence.ProduceRequest{
		UID:            uid,
		Params:         map[string]any{},
		UsePremiumSpec: false,
		EstimatedVocab: min(intValue(userData["estimated_vocab"]), uvm.FreeTierMaxVocab),
		// free は測定値を使わない（GetSessionWords 側でも 0 に落とす）。
		TestedVocab: 0,
		CacheOnly:   true,
		// キャッシュミス分は語を引き直す。n 本ぶん埋めるので周回数も本数に比例させる。
		SelectRetry: dailysentence.MaxTargetWordRetry * n,
		Lang:        l,
	}, n)
	if err != nil {
		log.Printf("daily_sentence: cached generation failed for %s: %v", uid, err)
		return nil
	}
	if len(produced) == 0 {
		return nil
	}
	return &pickedSet{Produced: produced, UsePremiumSpec: false, Lang: l}
}

func (d *deliverer) intn(n int) int {
	if d.Rand != nil {
		return d.Rand.Intn(n)
	}
	return rand.Intn(n)
}

// errDeliveryNotDue はトランザクション内の再判定で配信条件を満たさなくなった。
var errDeliveryNotDue = errors.New("DELIVERY_NOT_DUE")

// errEntitlementChanged は例文生成中に実効tierが変わったことを表す。
// free条件で作った例文をpremium確定後に配信（またはその逆）しないため、
// その回は何も確定せず次回の定期実行へ回す。
var errEntitlementChanged = errors.New("ENTITLEMENT_CHANGED")

// deliveryStoppedError は段階が配信停止に達したことを表す。
//
// トランザクション内で update しても、エラーを返した時点で rollback され
// 書き込みごと捨てられるため、停止の記録はトランザクション外で行う。
type deliveryStoppedError struct {
	updates []firestore.Update
}

func (e *deliveryStoppedError) Error() string { return "DELIVERY_STOPPED" }

// commitDailySentence はセット全部の例文docの書き込みとクォータ消費・段階更新を
// 1トランザクションで行う。
//
// 戻り値は (送信先トークン, 通知失敗時に段階を戻すための更新内容)。
//
// last_sentence_generated_at は書かない。あれは「次へ」押下＝反応のシグナルであり、
// 配信そのものを反応として数えてはいけない。
func (d *deliverer) commitDailySentence(
	ctx context.Context, userRef *firestore.DocumentRef,
	sentenceRefs []*firestore.DocumentRef, sentenceData []map[string]any, now time.Time,
	consumeQuota bool,
) (token string, restore []firestore.Update, err error) {
	expectedPremium := !consumeQuota
	err = d.DB.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		userData := map[string]any{}
		if snap, gerr := tx.Get(userRef); gerr == nil && snap.Exists() {
			userData = snap.Data()
		}

		consumed := 0
		if consumeQuota {
			consumed = len(sentenceRefs)
		}
		tok, rest, update, perr := dailyCommitPlanForEntitlement(
			userData, now, consumed, expectedPremium)
		if perr != nil {
			return perr
		}
		token, restore = tok, rest

		for i, ref := range sentenceRefs {
			if serr := tx.Set(ref, sentenceData[i]); serr != nil {
				return serr
			}
		}
		return tx.Update(userRef, update)
	})
	return token, restore, err
}

// dailyCommitPlan は最新の user doc から、コミット時の書き込み内容を決める。
//
// consumed は消費するクォータ（配信本数）。premium・トライアルは回数を消費しない
// ので 0 が渡り、remaining_sentences には触らない。
// 戻り値は (送信先トークン, 通知失敗時に戻すための更新, users への更新)。
func dailyCommitPlan(userData map[string]any, now time.Time, consumed int) (
	token string, restore, update []firestore.Update, err error,
) {
	return dailyCommitPlanForEntitlement(
		userData, now, consumed, premium.IsEffectivePremium(userData, now))
}

func dailyCommitPlanForEntitlement(
	userData map[string]any, now time.Time, consumed int, expectedPremium bool,
) (token string, restore, update []firestore.Update, err error) {
	// 外側の列挙結果は古い可能性があるため、二重配信を防ぐ正の判定は
	// トランザクション内の最新 user doc で行う。
	if !dailysentence.ShouldDeliver(userData, now) {
		return "", nil, nil, errDeliveryNotDue
	}
	if premium.IsEffectivePremium(userData, now) != expectedPremium {
		return "", nil, nil, errEntitlementChanged
	}

	tierUpdate := dailysentence.EvaluateResponse(userData)
	if tierUpdate.NotifyTier >= dailysentence.TierStopped {
		return "", nil, nil, &deliveryStoppedError{updates: append(
			[]firestore.Update{{Path: "last_notified_at", Value: firestore.ServerTimestamp}},
			tierUpdateFields(tierUpdate)...)}
	}

	token, _ = userData["fcm_token"].(string)
	restore = deliveryRestoreUpdate(userData)
	update = []firestore.Update{
		{Path: "daily_sentence_generated", Value: true},
		{Path: "last_notified_at", Value: firestore.ServerTimestamp},
	}
	if consumed > 0 {
		update = append(update,
			firestore.Update{Path: "remaining_sentences", Value: firestore.Increment(-consumed)})
	}
	update = append(update, tierUpdateFields(tierUpdate)...)
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
// セットで配信しても通知は1通のまま。Data に daily_set_id / daily_set_size を
// 載せ、クライアントは同じセットの例文をまとめて取り込む。sentence_id は
// 5本セットを知らない旧版が見るので、1本目の doc ID を従来どおり載せ続ける。
func buildNotification(
	token, setID string, setSize int, sentenceData map[string]any, l lang.Lang,
) *messaging.Message {
	title, body := dailysentence.BuildNotificationText(sentenceData, setSize, l)
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
		Data: map[string]string{
			"type":           "daily_sentence",
			"sentence_id":    setID,
			"daily_set_id":   setID,
			"daily_set_size": strconv.Itoa(setSize),
		},
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
	ctx context.Context, userRef *firestore.DocumentRef,
	sentenceRefs []*firestore.DocumentRef, restore []firestore.Update,
	deleteToken, consumedQuota bool,
) {
	for _, ref := range sentenceRefs {
		if _, err := ref.Delete(ctx); err != nil {
			log.Printf("daily_sentence: rollback の例文削除に失敗: %v", err)
		}
	}
	consumed := 0
	if consumedQuota {
		consumed = len(sentenceRefs)
	}
	update := rollbackUpdate(restore, deleteToken, consumed)
	if _, err := userRef.Update(ctx, update); err != nil {
		log.Printf("daily_sentence: rollback の users 更新に失敗: %v", err)
	}
}

func rollbackUpdate(
	restore []firestore.Update, deleteToken bool, consumed int,
) []firestore.Update {
	updates := []firestore.Update{
		{Path: "daily_sentence_generated", Value: false},
	}
	if consumed > 0 {
		updates = append(updates,
			firestore.Update{Path: "remaining_sentences", Value: firestore.Increment(consumed)})
	}
	if deleteToken {
		updates = append(updates,
			firestore.Update{Path: "fcm_token", Value: firestore.Delete})
	}
	return append(updates, restore...)
}

// deliverOne は1ユーザーへ1セット配信する。配信できたら ""、
// できなければ理由を返す（ログ集計用）。
//
// 本数はクライアントの版で決まる（dailysentence.BatchSize）。旧版は従来どおり1本。
// クォータが本数に足りなければ取れるぶんだけ配信する。
func (d *deliverer) deliverOne(
	ctx context.Context, uid string, userData map[string]any, now time.Time,
) string {
	userRef := d.DB.Collection("users").Doc(uid)

	// 候補列挙後に購入検証が完了することがあるため、元のtierに関係なく生成直前に
	// 必ず読み直す。読めないときは古いfree条件で配信せず、次回へ回す。
	snap, err := userRef.Get(ctx)
	if err != nil || !snap.Exists() {
		if err != nil {
			log.Printf("daily_sentence: user refresh failed for %s: %v", uid, err)
		}
		return "refresh_failed"
	}
	userData = snap.Data()
	if reason := dailysentence.DeliverySkipReason(userData, now); reason != "" {
		return "stale:" + reason
	}

	// premium・トライアルは回数を消費しないので、残数で絞らない。
	consumeQuota := !premium.IsEffectivePremium(userData, now)

	// free は先に自発生成した日は残り本数がセットに足りない。取れるぶんだけ配信する。
	n := dailysentence.BatchSize(userData)
	if consumeQuota {
		n = min(n, intValue(userData["remaining_sentences"]))
	}
	if n <= 0 {
		return "quota_exhausted"
	}

	p := d.buildSentences(ctx, uid, userData, now, n)
	if p == nil {
		log.Printf("daily_sentence: no sentence available for %s", uid)
		return "no_sentence"
	}

	// daily_set_id は1本目の doc ID を流用する。セット専用の ID を作っても
	// 参照する側（クライアントの取り込み）は同値で引くだけなので増やさない。
	size := len(p.Produced)
	localDate := dailysentence.LocalDate(userData["timezone"], now)
	sentenceRefs := make([]*firestore.DocumentRef, size)
	sentenceData := make([]map[string]any, size)
	for i := range sentenceRefs {
		sentenceRefs[i] = userRef.Collection("sentences").NewDoc()
	}
	setID := sentenceRefs[0].ID
	for i, produced := range p.Produced {
		data := produced.Sentence.BuildSentenceDoc(sentence.DocMeta{
			KeyWord:        produced.TargetWords[0],
			UsePremiumSpec: p.UsePremiumSpec,
			Lang:           p.Lang,
			FromCache:      produced.FromCache,
			TrackViewed:    sentence.SupportsViewTracking(userData),
			Quality:        produced.Quality,
		})
		data["daily"] = true
		data["daily_date"] = localDate
		data["daily_set_id"] = setID
		data["daily_set_index"] = i
		data["daily_set_size"] = size
		sentenceData[i] = data
	}

	token, restore, err := d.commitDailySentence(
		ctx, userRef, sentenceRefs, sentenceData, now, consumeQuota)
	if err != nil {
		var stopped *deliveryStoppedError
		switch {
		case errors.Is(err, errDeliveryNotDue):
			return "not_due_at_commit"
		case errors.Is(err, errEntitlementChanged):
			return "entitlement_changed_at_commit"
		case errors.As(err, &stopped):
			if _, uerr := userRef.Update(ctx, stopped.updates); uerr != nil {
				log.Printf("daily_sentence: 配信停止の記録に失敗 %s: %v", uid, uerr)
			}
			return "backoff_stopped_now"
		}
		log.Printf("daily_sentence: commit failed for %s: %v", uid, err)
		return "error"
	}

	// key_word とその意味を通知に載せるため、整形済みの1本目を渡す。
	msg := buildNotification(token, setID, size, sentenceData[0],
		lang.Resolve(userData["app_language"]))
	if _, err := d.Notifier.Send(ctx, msg); err != nil {
		if messaging.IsUnregistered(err) {
			log.Printf("daily_sentence: token unregistered, rolling back %s", uid)
			rollbackDelivery(ctx, userRef, sentenceRefs, restore, true, consumeQuota)
			return "token_unregistered"
		}
		// トークン失効以外の送信失敗（権限・FCM障害など）。ここを素通りすると
		// 通知が飛ばないのにクォータと当日フラグだけ消費されてしまう。
		log.Printf("daily_sentence: send failed for %s: %v", uid, err)
		rollbackDelivery(ctx, userRef, sentenceRefs, restore, false, consumeQuota)
		return "send_failed"
	}

	// 露出登録は通知が届いた後にだけ行う。配信をロールバックしても
	// UVM の P 微増は巻き戻せないため、送信成功を確認してから登録する。
	for _, produced := range p.Produced {
		registerSentenceExposure(ctx, d.DB, uid, produced)
	}
	// 最新の実効権利を読み、真のfreeだけを従来どおり100語上限にする。
	uvm.SyncEstimatedVocab(ctx, d.DB, uid, d.FreqRank)

	// 通知が届いたあとで、前回までの未読セットを洗い替える。送信前に消すと、
	// 通知失敗でロールバックしたとき手元から例文だけが消える。
	d.purgeUnreadDeliveredSets(ctx, userRef, setID)
	return ""
}

// deliveredDoc は洗い替えの判定に使う配信docの最小形。
type deliveredDoc struct {
	ID   string
	Data map[string]any
}

// deliveredSetID は配信docの属するセット。旧形式（daily_set_id 無し）は
// doc 自身を1本のセットとして扱う（クライアントの setIdOf と同じ規則）。
func deliveredSetID(docID string, data map[string]any) string {
	if setID, ok := data["daily_set_id"].(string); ok && setID != "" {
		return setID
	}
	return docID
}

// unreadDeliveredSetIDs は keepSetID 以外で「1本も読まれていない」配信セットを
// 返す（doc ID 昇順で安定させる）。
//
// 1本でも既読があるセットは消さない。消化の途中で、カーソルがそこに載っている。
// viewed フィールドを持たない doc は既読扱い（isSentenceViewed）なので、
// 既読トラッキング非対応の版へ配信したぶんは洗い替えの対象にならない。
// 判定できないものを消さない側に倒す。
func unreadDeliveredSetIDs(docs []deliveredDoc, keepSetID string) []string {
	members := map[string][]string{}
	read := map[string]bool{}
	for _, doc := range docs {
		setID := deliveredSetID(doc.ID, doc.Data)
		if setID == keepSetID {
			continue
		}
		members[setID] = append(members[setID], doc.ID)
		if isSentenceViewed(doc.Data) {
			read[setID] = true
		}
	}

	var ids []string
	for setID := range members {
		if !read[setID] {
			ids = append(ids, setID)
		}
	}
	sort.Strings(ids)
	return ids
}

// purgeUnreadDeliveredSets は今回配信した keepSetID 以外の未読セットを消す。
//
// 通知したのに1本も読まれなかったセットは、次の配信が届いた時点で捨てる。
// 残すと、クライアントは未取り込みの配信を30日ぶん全部拾って待機列へ積むため
// （daily_sentence_service.dart）、無視した日数ぶん古い例文が先に出て、いまの
// レベルに合った最新セットが最後尾へ回る。key_word の選定は P とestimated_vocab
// しか見ず、クイズを受けていない間はどちらも動かないので、溜まったセットは
// 同じ帯の似た語ばかりになる（重複するうえスコアも伸びない）。
//
// 失敗しても配信自体は成立しているのでログだけ残す。次回の配信で消し直せる。
func (d *deliverer) purgeUnreadDeliveredSets(
	ctx context.Context, userRef *firestore.DocumentRef, keepSetID string,
) {
	it := userRef.Collection("sentences").Where("daily", "==", true).Documents(ctx)
	defer it.Stop()

	var docs []deliveredDoc
	for {
		doc, err := it.Next()
		if err == iterator.Done {
			break
		}
		if err != nil {
			log.Printf("daily_sentence: 未読セットの列挙に失敗 %s: %v", userRef.ID, err)
			return
		}
		docs = append(docs, deliveredDoc{ID: doc.Ref.ID, Data: doc.Data()})
	}

	stale := map[string]bool{}
	for _, setID := range unreadDeliveredSetIDs(docs, keepSetID) {
		stale[setID] = true
	}
	if len(stale) == 0 {
		return
	}

	bw := d.DB.BulkWriter(ctx)
	deleted := 0
	for _, doc := range docs {
		if !stale[deliveredSetID(doc.ID, doc.Data)] {
			continue
		}
		if _, err := bw.Delete(userRef.Collection("sentences").Doc(doc.ID)); err != nil {
			log.Printf("daily_sentence: 未読セットの削除に失敗 %s: %v", userRef.ID, err)
			continue
		}
		deleted++
	}
	bw.End()
	log.Printf("daily_sentence: purged unread sets uid=%s sets=%d sentences=%d",
		userRef.ID, len(stale), deleted)
}

// deliveryQualityCheck は配信で生成直後の品質判定を行うか。
// DELIVERY_QUALITY_CHECK=0 で止められる（Jev 障害時の逃げ道）。
func deliveryQualityCheck() bool {
	return envOr("DELIVERY_QUALITY_CHECK", "1") != "0"
}
