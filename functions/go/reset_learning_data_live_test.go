package function

import (
	"context"
	"os"
	"testing"

	firebase "firebase.google.com/go/v4"

	"github.com/mnbst/thai-memo/functions/go/internal/callable"
)

// TestResetLearningDataLive はハンドラを **実際の dev Firestore** に対して回す。
//
// 既定ではスキップする。実行するとき:
//
//	GCLOUD_PROJECT=thai-memo-dev LIVE_FIRESTORE_TEST=1 \
//	  go test -run TestResetLearningDataLive -v .
//
// callable の電文と ID トークン検証は internal/callable のテストで固定済みなので、
// ここが見るのは Firestore に対する削除とクォータ初期化だけ。
// 使い捨て uid にしか触らない。
func TestResetLearningDataLive(t *testing.T) {
	if os.Getenv("LIVE_FIRESTORE_TEST") == "" {
		t.Skip("LIVE_FIRESTORE_TEST が未設定")
	}

	ctx := context.Background()
	app, err := firebase.NewApp(ctx, &firebase.Config{ProjectID: os.Getenv("GCLOUD_PROJECT")})
	if err != nil {
		t.Fatal(err)
	}
	db, err := app.Firestore(ctx)
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	const uid = "go-port-live-test-throwaway"
	const queueDoc = "go-port-live-test-queue"

	seed := map[string][]string{
		"sentences":    {"s1", "s2"},
		"quiz_answers": {"q1"},
		"uvm":          {"u1"},
	}

	t.Cleanup(func() {
		for sub, ids := range seed {
			for _, id := range ids {
				_, _ = db.Collection("users").Doc(uid).Collection(sub).Doc(id).Delete(ctx)
			}
		}
		_, _ = db.Collection("quiz_queue").Doc(queueDoc).Delete(ctx)
		_, _ = db.Collection("users").Doc(uid).Delete(ctx)
	})

	want := 0
	for sub, ids := range seed {
		for _, id := range ids {
			if _, err := db.Collection("users").Doc(uid).Collection(sub).Doc(id).
				Set(ctx, map[string]any{"seeded": true}); err != nil {
				t.Fatal(err)
			}
			want++
		}
	}
	if _, err := db.Collection("quiz_queue").Doc(queueDoc).
		Set(ctx, map[string]any{"uid": uid}); err != nil {
		t.Fatal(err)
	}
	want++

	// merge であることを確かめるため、リセット対象外のフィールドも入れておく。
	if _, err := db.Collection("users").Doc(uid).Set(ctx, map[string]any{
		"remaining_sentences":      99,
		"sentence_generated_count": 42,
		"daily_sentence_generated": true,
		"keep_me":                  "残るはず",
	}); err != nil {
		t.Fatal(err)
	}

	got, err := resetLearningData(ctx, &callable.Request{
		Auth: &callable.Auth{UID: uid},
	})
	if err != nil {
		t.Fatal(err)
	}
	if n := got.(map[string]any)["deleted"]; n != want {
		t.Fatalf("deleted = %v, want %d", n, want)
	}

	for sub, ids := range seed {
		for _, id := range ids {
			snap, err := db.Collection("users").Doc(uid).Collection(sub).Doc(id).Get(ctx)
			if err == nil && snap.Exists() {
				t.Errorf("%s/%s が残っている", sub, id)
			}
		}
	}
	if snap, err := db.Collection("quiz_queue").Doc(queueDoc).Get(ctx); err == nil && snap.Exists() {
		t.Error("quiz_queue の doc が残っている")
	}

	snap, err := db.Collection("users").Doc(uid).Get(ctx)
	if err != nil {
		t.Fatal(err)
	}
	for k, w := range map[string]any{
		"remaining_sentences":      int64(5),
		"remaining_quizzes":        int64(5),
		"sentence_generated_count": int64(0),
		"estimated_vocab":          int64(0),
		"daily_sentence_generated": false,
		"keep_me":                  "残るはず", // merge なので消えない
	} {
		if v := snap.Data()[k]; v != w {
			t.Errorf("users/%s.%s = %#v, want %#v", uid, k, v, w)
		}
	}
}
