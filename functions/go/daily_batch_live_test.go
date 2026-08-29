package function

import (
	"fmt"
	"testing"
	"time"

	"cloud.google.com/go/firestore"

	"github.com/mnbst/thai-memo/functions/go/internal/userdata"
)

// dailyBatch の Firestore へ実際に書く部分を dev の実 Firestore で確かめる。
//
// **runDailyBatch 全体は絶対に走らせない。** cleanupAnonymousUsers が Auth の
// ユーザーと、Auth に居ない users doc（テスト用の捨て uid を含む）を実削除する
// ため、dev の実データを巻き込む。ここでは書き込みを行う各関数を捨て uid に
// 対して個別に呼ぶ。
//
//	GCLOUD_PROJECT=thai-memo-dev LIVE_FIRESTORE_TEST=1 \
//	  go test -run TestDailyBatch -v .

// TestDailyBatchResetQuotaWrites は resetQuota の書き込みが merge であること、
// つまり無関係なフィールドを消さないことを確かめる。
//
// 判定そのものは TestQuotaResetPayloadGolden（JS との突き合わせ）で見ている。
// ここで見るのは「その payload を Firestore に置いたらどうなるか」だけ。
func TestDailyBatchResetQuotaWrites(t *testing.T) {
	db, ctx := liveFirestore(t)

	const uid = "go-port-dailybatch-throwaway"
	ref := db.Collection("users").Doc(uid)
	t.Cleanup(func() { _, _ = ref.Delete(ctx) })

	now := time.Now()
	// 期限切れのストア購入 premium。free へ落ちるはず。
	seed := map[string]any{
		"tier": "premium",
		"subscription": map[string]any{
			"platform":   "ios",
			"status":     "active",
			"expires_at": now.Add(-40 * 24 * time.Hour),
			// 落とすときに触らないフィールド。merge なら残る。
			"original_transaction_id": "keep-me",
		},
		"timezone":                  "Asia/Tokyo",
		"preferred_generation_hour": int64(10),
		"remaining_sentences":       int64(0),
		"nickname":                  "keep-me-too",
	}
	if _, err := ref.Set(ctx, seed); err != nil {
		t.Fatal(err)
	}

	doc, err := ref.Get(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if err := resetQuota(ctx, db, doc, now); err != nil {
		t.Fatal(err)
	}

	after, err := ref.Get(ctx)
	if err != nil {
		t.Fatal(err)
	}
	got := after.Data()

	if got["tier"] != "free" {
		t.Errorf("tier: want free, got %v", got["tier"])
	}
	if got["remaining_sentences"] != int64(5) {
		t.Errorf("remaining_sentences: want 5, got %v", got["remaining_sentences"])
	}
	if got["notify_utc_hour"] != int64(1) {
		t.Errorf("notify_utc_hour: want 1 (Asia/Tokyo 10時), got %v", got["notify_utc_hour"])
	}
	if got["nickname"] != "keep-me-too" {
		t.Errorf("merge されていない。nickname が %v", got["nickname"])
	}

	sub, _ := got["subscription"].(map[string]any)
	if sub["status"] != "expired" {
		t.Errorf("subscription.status: want expired, got %v", sub["status"])
	}
	// ここが本題。JS の merge:true と同じくネストしたマップも深く合成され、
	// subscription 配下の他フィールドが消えないこと。
	if sub["original_transaction_id"] != "keep-me" {
		t.Errorf("subscription が丸ごと置換されている: %v", sub)
	}
	if _, ok := sub["platform"]; !ok {
		t.Errorf("subscription.platform が消えている: %v", sub)
	}
}

// TestDailyBatchDecayUvmP は P 減衰が全語に効き、下限で止まることを確かめる。
func TestDailyBatchDecayUvmP(t *testing.T) {
	db, ctx := liveFirestore(t)

	const uid = "go-port-decay-throwaway"
	uvmCol := db.Collection("users").Doc(uid).Collection("uvm")

	seeds := map[string]any{
		"w-high":     0.9,
		"w-mid":      0.5,
		"w-tiny":     0.0005, // 減衰すると下限に張り付く
		"w-zero":     0.0,    // 対象外
		"w-negative": -0.5,   // 対象外（p <= 0）
	}
	// int で入っている語（Firestore からは int64 で返る）も混ぜる
	intSeeds := map[string]any{"w-int": int64(1)}

	t.Cleanup(func() {
		for word := range seeds {
			_, _ = uvmCol.Doc(word).Delete(ctx)
		}
		for word := range intSeeds {
			_, _ = uvmCol.Doc(word).Delete(ctx)
		}
		_, _ = db.Collection("users").Doc(uid).Delete(ctx)
	})

	for word, p := range seeds {
		if _, err := uvmCol.Doc(word).Set(ctx, map[string]any{
			"p": p, "word": word,
		}); err != nil {
			t.Fatal(err)
		}
	}
	for word, p := range intSeeds {
		if _, err := uvmCol.Doc(word).Set(ctx, map[string]any{
			"p": p, "word": word,
		}); err != nil {
			t.Fatal(err)
		}
	}

	if err := decayUvmP(ctx, db, uid); err != nil {
		t.Fatal(err)
	}

	want := map[string]float64{
		"w-high":     0.899,
		"w-mid":      0.499,
		"w-tiny":     0.0, // max(0, 0.0005-0.001)
		"w-zero":     0.0,
		"w-negative": -0.5, // 触らない
		"w-int":      0.999,
	}
	for word, expect := range want {
		doc, err := uvmCol.Doc(word).Get(ctx)
		if err != nil {
			t.Fatal(err)
		}
		got := floatField(doc.Data()["p"])
		if diff := got - expect; diff > 1e-9 || diff < -1e-9 {
			t.Errorf("%s: want %v, got %v", word, expect, got)
		}
		if doc.Data()["word"] != word {
			t.Errorf("%s: update ではなく上書きになっている: %v", word, doc.Data())
		}
	}
}

// TestDailyBatchCleanOldSentences は保持期間より古い例文だけが消えることを確かめる。
//
// cleanOldSentences は users を全走査するので、dev の他ユーザーの古い例文まで
// 消してしまう。ここでは削除対象クエリと BulkWriter の挙動だけを、捨て uid に
// 限定して同じ式で確かめる。
func TestDailyBatchCleanOldSentences(t *testing.T) {
	db, ctx := liveFirestore(t)

	const uid = "go-port-cleansent-throwaway"
	col := db.Collection("users").Doc(uid).Collection("sentences")

	now := time.Now()
	cutoff := oldSentenceCutoff(now)

	seeds := map[string]time.Time{
		"old-40d":        now.Add(-40 * 24 * time.Hour),
		"old-31d":        now.Add(-31 * 24 * time.Hour),
		"just-before":    cutoff.Add(-time.Second),
		"exactly-cutoff": cutoff, // "<" なので残る
		"just-after":     cutoff.Add(time.Second),
		"recent":         now.Add(-time.Hour),
		"future-somehow": now.Add(24 * time.Hour),
	}
	wantDeleted := map[string]bool{
		"old-40d": true, "old-31d": true, "just-before": true,
	}

	t.Cleanup(func() {
		for id := range seeds {
			_, _ = col.Doc(id).Delete(ctx)
		}
		_, _ = db.Collection("users").Doc(uid).Delete(ctx)
	})

	for id, createdAt := range seeds {
		if _, err := col.Doc(id).Set(ctx, map[string]any{
			"created_at": createdAt, "thai": "ทดสอบ",
		}); err != nil {
			t.Fatal(err)
		}
	}

	if err := deleteOldSentencesFor(ctx, db, uid, cutoff); err != nil {
		t.Fatal(err)
	}

	for id := range seeds {
		doc, err := col.Doc(id).Get(ctx)
		exists := err == nil && doc.Exists()
		if wantDeleted[id] && exists {
			t.Errorf("%s: 削除されるはずが残っている", id)
		}
		if !wantDeleted[id] && !exists {
			t.Errorf("%s: 残るはずが削除されている", id)
		}
	}
}

// TestDailyBatchClearDuplicateFcmTokens は重複解除の書き込みを確かめる。
// どの uid を解除するかの判定は TestDuplicateTokenUidsGolden で見ている。
func TestDailyBatchClearDuplicateFcmTokens(t *testing.T) {
	db, ctx := liveFirestore(t)

	// 活動時刻が新しい方（keep）を残し、古い方（stale）から消す
	uids := []string{"go-port-fcm-keep-throwaway", "go-port-fcm-stale-throwaway"}
	now := time.Now()

	t.Cleanup(func() {
		for _, uid := range uids {
			_, _ = db.Collection("users").Doc(uid).Delete(ctx)
		}
	})

	seeds := []map[string]any{
		{"fcm_token": "go-port-shared-token", "last_active_at": now,
			"daily_reminder_enabled": true},
		{"fcm_token": "go-port-shared-token",
			"last_active_at":         now.Add(-5 * 24 * time.Hour),
			"daily_reminder_enabled": true},
	}

	var docs []*firestore.DocumentSnapshot
	for i, uid := range uids {
		if _, err := db.Collection("users").Doc(uid).Set(ctx, seeds[i]); err != nil {
			t.Fatal(err)
		}
		doc, err := db.Collection("users").Doc(uid).Get(ctx)
		if err != nil {
			t.Fatal(err)
		}
		docs = append(docs, doc)
	}

	clearDuplicateFcmTokens(ctx, db, docs)

	keep, err := db.Collection("users").Doc(uids[0]).Get(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if keep.Data()["fcm_token"] != "go-port-shared-token" {
		t.Errorf("新しい方の登録まで消えている: %v", keep.Data())
	}
	if keep.Data()["daily_reminder_enabled"] != true {
		t.Errorf("新しい方の daily_reminder_enabled が変わっている: %v", keep.Data())
	}

	stale, err := db.Collection("users").Doc(uids[1]).Get(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if _, ok := stale.Data()["fcm_token"]; ok {
		t.Errorf("古い方の fcm_token が消えていない: %v", stale.Data())
	}
	if stale.Data()["daily_reminder_enabled"] != false {
		t.Errorf("古い方の daily_reminder_enabled: want false, got %v",
			stale.Data()["daily_reminder_enabled"])
	}
}

// TestDeleteUserFirestoreData は userdata.DeleteFirestoreData が
// 対象を漏れなく消し、他人のデータに触らないことを確かめる。
func TestDeleteUserFirestoreData(t *testing.T) {
	db, ctx := liveFirestore(t)

	const uid = "go-port-deluser-throwaway"
	const other = "go-port-deluser-other-throwaway"
	const nickname = "GoPortThrowaway"

	t.Cleanup(func() {
		for _, u := range []string{uid, other} {
			for _, sub := range []string{"sentences", "quiz_answers", "uvm"} {
				for i := range 3 {
					_, _ = db.Collection("users").Doc(u).
						Collection(sub).Doc(fmt.Sprintf("d%d", i)).Delete(ctx)
				}
			}
			_, _ = db.Collection("users").Doc(u).Delete(ctx)
			_, _ = db.Collection("leaderboard").Doc(u).Delete(ctx)
		}
		_, _ = db.Collection("nicknames").Doc("goportthrowaway").Delete(ctx)
		for _, id := range []string{"go-port-q1", "go-port-q2", "go-port-q-other"} {
			_, _ = db.Collection("quiz_queue").Doc(id).Delete(ctx)
		}
	})

	// 対象ユーザー
	if _, err := db.Collection("users").Doc(uid).Set(ctx,
		map[string]any{"tier": "free"}); err != nil {
		t.Fatal(err)
	}
	for _, sub := range []string{"sentences", "quiz_answers", "uvm"} {
		for i := range 3 {
			if _, err := db.Collection("users").Doc(uid).Collection(sub).
				Doc(fmt.Sprintf("d%d", i)).Set(ctx, map[string]any{"i": i}); err != nil {
				t.Fatal(err)
			}
		}
	}
	if _, err := db.Collection("leaderboard").Doc(uid).Set(ctx,
		map[string]any{"nickname": "  " + nickname + "  "}); err != nil {
		t.Fatal(err)
	}
	if _, err := db.Collection("nicknames").Doc("goportthrowaway").Set(ctx,
		map[string]any{"uid": uid}); err != nil {
		t.Fatal(err)
	}
	for _, id := range []string{"go-port-q1", "go-port-q2"} {
		if _, err := db.Collection("quiz_queue").Doc(id).Set(ctx,
			map[string]any{"uid": uid}); err != nil {
			t.Fatal(err)
		}
	}

	// 巻き添えにしてはいけない別ユーザー
	if _, err := db.Collection("users").Doc(other).Set(ctx,
		map[string]any{"tier": "free"}); err != nil {
		t.Fatal(err)
	}
	if _, err := db.Collection("users").Doc(other).Collection("uvm").
		Doc("d0").Set(ctx, map[string]any{"i": 0}); err != nil {
		t.Fatal(err)
	}
	if _, err := db.Collection("quiz_queue").Doc("go-port-q-other").Set(ctx,
		map[string]any{"uid": other}); err != nil {
		t.Fatal(err)
	}

	count, err := userdata.DeleteFirestoreData(ctx, db, uid)
	if err != nil {
		t.Fatal(err)
	}
	// sentences 3 + quiz_answers 3 + uvm 3 + users 1 + nicknames 1
	//   + leaderboard 1 + quiz_queue 2 = 14
	if count != 14 {
		t.Errorf("削除件数: want 14, got %d", count)
	}

	assertGone := func(ref *firestore.DocumentRef) {
		t.Helper()
		doc, err := ref.Get(ctx)
		if err == nil && doc.Exists() {
			t.Errorf("%s が残っている", ref.Path)
		}
	}
	for _, sub := range []string{"sentences", "quiz_answers", "uvm"} {
		for i := range 3 {
			assertGone(db.Collection("users").Doc(uid).
				Collection(sub).Doc(fmt.Sprintf("d%d", i)))
		}
	}
	assertGone(db.Collection("users").Doc(uid))
	assertGone(db.Collection("leaderboard").Doc(uid))
	// ニックネームは小文字化して解放される（予約が永久に埋まらないように）
	assertGone(db.Collection("nicknames").Doc("goportthrowaway"))
	assertGone(db.Collection("quiz_queue").Doc("go-port-q1"))
	assertGone(db.Collection("quiz_queue").Doc("go-port-q2"))

	assertExists := func(ref *firestore.DocumentRef) {
		t.Helper()
		doc, err := ref.Get(ctx)
		if err != nil || !doc.Exists() {
			t.Errorf("%s が巻き添えで消えている", ref.Path)
		}
	}
	assertExists(db.Collection("users").Doc(other))
	assertExists(db.Collection("users").Doc(other).Collection("uvm").Doc("d0"))
	assertExists(db.Collection("quiz_queue").Doc("go-port-q-other"))
}
