package function

import (
	"context"
	"errors"
	"strings"
	"sync"
	"testing"
	"time"

	"cloud.google.com/go/firestore"
	"firebase.google.com/go/v4/messaging"
	"google.golang.org/api/iterator"

	"github.com/mnbst/thai-memo/functions/go/internal/dailysentence"
	"github.com/mnbst/thai-memo/functions/go/internal/fbapp"
	"github.com/mnbst/thai-memo/functions/go/internal/uvm"
)

// 5本セット配信を dev の実 Firestore・実 Gemini に対して端から端まで確かめる。
//
// 通知だけは差し替える。実 FCM へ送ると実機にプッシュが飛ぶうえ、捨てトークンでは
// 必ず失敗してロールバックが走り、確かめたい書き込みごと消えてしまう。
//
//	GCLOUD_PROJECT=thai-memo-dev LIVE_FIRESTORE_TEST=1 \
//	  go test -run TestDeliverDailySentenceSetLive -v -timeout 300s .
func TestDeliverDailySentenceSetLive(t *testing.T) {
	db, ctx := liveFirestore(t)

	const uid = "go-port-dailyset-throwaway"
	userRef := db.Collection("users").Doc(uid)
	t.Cleanup(func() { deleteUserTree(ctx, t, userRef) })
	// 前回の失敗が残っていても素の状態から始める。
	deleteUserTree(ctx, t, userRef)

	now := time.Now().UTC()
	seed := map[string]any{
		"tier":                       "premium",
		"app_version":                "1.4.8",
		"app_language":               "ja",
		"fcm_token":                  "throwaway-token",
		"daily_reminder_enabled":     true,
		"timezone":                   "UTC",
		"preferred_generation_hour":  int64(now.Hour()),
		"remaining_sentences":        int64(20),
		"daily_sentence_generated":   false,
		"estimated_vocab":            int64(800),
		"last_sentence_generated_at": now.Add(-48 * time.Hour),
	}
	if _, err := userRef.Set(ctx, seed); err != nil {
		t.Fatal(err)
	}
	if reason := dailysentence.DeliverySkipReason(seed, now); reason != "" {
		t.Fatalf("配信対象になっていない: %s", reason)
	}
	if n := dailysentence.BatchSize(seed); n != dailysentence.DailyBatchSize {
		t.Fatalf("配信本数 %d, want %d", n, dailysentence.DailyBatchSize)
	}

	producer, err := newProducer(ctx)
	if err != nil {
		t.Fatal(err)
	}
	freqRank, err := uvm.GetFreqRank(ctx, fbapp.ProjectID())
	if err != nil {
		t.Fatal(err)
	}
	sent := &captureNotifier{}
	d := &deliverer{DB: db, Producer: producer, FreqRank: freqRank, Notifier: sent}

	started := time.Now()
	if reason := d.deliverOne(ctx, uid, seed, now); reason != "" {
		t.Fatalf("配信されなかった: %s", reason)
	}
	t.Logf("配信 %.1fs", time.Since(started).Seconds())

	// --- 例文ドキュメント ---
	docs, err := userRef.Collection("sentences").Documents(ctx).GetAll()
	if err != nil {
		t.Fatal(err)
	}
	if len(docs) != dailysentence.DailyBatchSize {
		t.Fatalf("書かれた例文 %d本, want %d", len(docs), dailysentence.DailyBatchSize)
	}

	setIDs := map[string]int{}
	indexes := map[int64]int{}
	keyWords := map[string]int{}
	topics := map[string]int{}
	for _, doc := range docs {
		data := doc.Data()
		if data["daily"] != true {
			t.Errorf("%s: daily が立っていない", doc.Ref.ID)
		}
		if size, _ := data["daily_set_size"].(int64); size != int64(len(docs)) {
			t.Errorf("%s: daily_set_size = %v, want %d", doc.Ref.ID, data["daily_set_size"], len(docs))
		}
		setID, _ := data["daily_set_id"].(string)
		setIDs[setID]++
		index, _ := data["daily_set_index"].(int64)
		indexes[index]++
		keyWord, _ := data["key_word"].(string)
		keyWords[keyWord]++
		if ctxMap, ok := data["context"].(map[string]any); ok {
			topic, _ := ctxMap["topic"].(string)
			topics[topic]++
		}
		if tier, _ := data["generation_tier"].(string); tier != "premium" {
			t.Errorf("%s: generation_tier = %q, want premium", doc.Ref.ID, tier)
		}
		t.Logf("  [%d] %s key_word=%s", index, doc.Ref.ID, keyWord)
	}

	// セットIDは1つ。1本目の doc ID を流用しているので、その ID の doc が実在する。
	if len(setIDs) != 1 {
		t.Errorf("daily_set_id が %d 種類ある: %v", len(setIDs), setIDs)
	}
	for setID := range setIDs {
		if _, err := userRef.Collection("sentences").Doc(setID).Get(ctx); err != nil {
			t.Errorf("daily_set_id %q の doc が無い: %v", setID, err)
		}
	}
	// 表示順は 0..n-1 が1つずつ。
	for i := range int64(len(docs)) {
		if indexes[i] != 1 {
			t.Errorf("daily_set_index=%d が %d 件", i, indexes[i])
		}
	}
	// key_word はセット内で重複しない（選定を1回にまとめている根拠）。
	for word, n := range keyWords {
		if n != 1 || word == "" {
			t.Errorf("key_word %q が %d 件", word, n)
		}
	}
	// テーマはセットで共通（SelectTargetWords がテーマを1つ返す）。
	if len(topics) > 1 {
		t.Errorf("テーマがセット内で割れている: %v", topics)
	}
	t.Logf("テーマ=%v", topics)

	// --- クォータと当日フラグ ---
	after, err := userRef.Get(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if got, _ := after.Data()["remaining_sentences"].(int64); got != 20-int64(len(docs)) {
		t.Errorf("remaining_sentences = %d, want %d", got, 20-int64(len(docs)))
	}
	if after.Data()["daily_sentence_generated"] != true {
		t.Error("daily_sentence_generated が立っていない")
	}

	// --- 通知 ---
	msg := sent.last()
	if msg == nil {
		t.Fatal("通知が送られていない")
	}
	if msg.Data["daily_set_size"] != "5" {
		t.Errorf("daily_set_size = %q, want 5", msg.Data["daily_set_size"])
	}
	if msg.Data["daily_set_id"] == "" || msg.Data["daily_set_id"] != msg.Data["sentence_id"] {
		t.Errorf("sentence_id と daily_set_id が揃っていない: %v", msg.Data)
	}
	if !strings.Contains(msg.Notification.Title, "ほか4本") {
		t.Errorf("タイトルに本数が無い: %q", msg.Notification.Title)
	}
	t.Logf("通知 title=%q", msg.Notification.Title)
	t.Logf("通知 body=%q", msg.Notification.Body)
}

// captureNotifier は送信せずに内容だけ控える。
type captureNotifier struct {
	mu   sync.Mutex
	msgs []*messaging.Message
}

func (n *captureNotifier) Send(_ context.Context, m *messaging.Message) (string, error) {
	n.mu.Lock()
	defer n.mu.Unlock()
	n.msgs = append(n.msgs, m)
	return "projects/test/messages/1", nil
}

func (n *captureNotifier) last() *messaging.Message {
	n.mu.Lock()
	defer n.mu.Unlock()
	if len(n.msgs) == 0 {
		return nil
	}
	return n.msgs[len(n.msgs)-1]
}

// deleteUserTree は捨て uid の doc とサブコレクションを消す。
// UVM の露出登録もサブコレクションへ書くので、doc だけ消すと残る。
func deleteUserTree(ctx context.Context, t *testing.T, userRef *firestore.DocumentRef) {
	t.Helper()
	cols := userRef.Collections(ctx)
	for {
		col, err := cols.Next()
		if errors.Is(err, iterator.Done) {
			break
		}
		if err != nil {
			t.Logf("サブコレクションの列挙に失敗: %v", err)
			break
		}
		docs, err := col.Documents(ctx).GetAll()
		if err != nil {
			t.Logf("%s の列挙に失敗: %v", col.ID, err)
			continue
		}
		for _, doc := range docs {
			if _, err := doc.Ref.Delete(ctx); err != nil {
				t.Logf("%s の削除に失敗: %v", doc.Ref.Path, err)
			}
		}
	}
	if _, err := userRef.Delete(ctx); err != nil {
		t.Logf("users doc の削除に失敗: %v", err)
	}
}
