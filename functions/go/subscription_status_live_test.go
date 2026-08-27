package function

import (
	"context"
	"os"
	"testing"
	"time"

	"cloud.google.com/go/firestore"
	firebase "firebase.google.com/go/v4"
	"google.golang.org/api/iterator"
)

// TestSubscriptionStatusDecision は「どの状態を free に落とすか」の判定表を
// 実 Firestore に対して1件ずつ確かめる。
//
// 全体スキャン（runSubscriptionStatus）は dev の実ユーザーまで巻き込むので
// 走らせない。ここでは expireUser を種ごとに直接呼ぶ。
// クエリ条件そのものは TestSubscriptionStatusQuery で別に見る。
//
//	GCLOUD_PROJECT=thai-memo-dev LIVE_FIRESTORE_TEST=1 \
//	  go test -run TestSubscriptionStatus -v .
func TestSubscriptionStatusDecision(t *testing.T) {
	db, ctx := liveFirestore(t)

	now := time.Now()
	past := now.Add(-40 * 24 * time.Hour)   // 猶予上限(30日)を超えている
	recent := now.Add(-10 * 24 * time.Hour) // 猶予上限内

	cases := []struct {
		name         string
		subscription map[string]any
		wantDemoted  bool
	}{
		{"active は落とす",
			map[string]any{"status": "active", "expires_at": recent}, true},
		{"canceled は落とす",
			map[string]any{"status": "canceled", "expires_at": recent}, true},
		{"grace_period で猶予上限を超えていれば落とす",
			map[string]any{"status": "grace_period", "expires_at": past}, true},
		{"grace_period で猶予上限内なら残す",
			map[string]any{"status": "grace_period", "expires_at": recent}, false},
		{"grace_period で expires_at が無ければ残す",
			map[string]any{"status": "grace_period"}, false},
		{"grace_period で expires_at が Timestamp でなければ残す",
			map[string]any{"status": "grace_period", "expires_at": 12345}, false},
		{"expired は対象外",
			map[string]any{"status": "expired", "expires_at": past}, false},
		{"未知の status は対象外",
			map[string]any{"status": "on_hold", "expires_at": past}, false},
		{"status が無ければ対象外",
			map[string]any{"expires_at": past}, false},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			const uid = "go-port-substatus-throwaway"
			ref := db.Collection("users").Doc(uid)
			t.Cleanup(func() { _, _ = ref.Delete(ctx) })

			if _, err := ref.Set(ctx, map[string]any{
				"tier":         "premium",
				"subscription": tc.subscription,
			}); err != nil {
				t.Fatal(err)
			}
			snap, err := ref.Get(ctx)
			if err != nil {
				t.Fatal(err)
			}
			if err := expireUser(ctx, snap, now); err != nil {
				t.Fatal(err)
			}

			after, err := ref.Get(ctx)
			if err != nil {
				t.Fatal(err)
			}
			tier, _ := after.Data()["tier"].(string)
			sub, _ := after.Data()["subscription"].(map[string]any)
			status, _ := sub["status"].(string)

			if tc.wantDemoted {
				if tier != "free" {
					t.Errorf("tier = %q, want free", tier)
				}
				if status != "expired" {
					t.Errorf("subscription.status = %q, want expired", status)
				}
				if _, ok := sub["updated_at"].(time.Time); !ok {
					t.Errorf("subscription.updated_at が書かれていない: %#v", sub["updated_at"])
				}
			} else {
				if tier != "premium" {
					t.Errorf("tier = %q, want premium（落としてはいけない）", tier)
				}
				want, _ := tc.subscription["status"].(string)
				if status != want {
					t.Errorf("subscription.status = %q, want %q（触ってはいけない）", status, want)
				}
			}
		})
	}
}

// TestSubscriptionStatusQuery はスキャンのクエリ条件だけを確かめる（書き込みなし）。
// 複合インデックス（tier + subscription.expires_at）が生きていることの確認も兼ねる。
func TestSubscriptionStatusQuery(t *testing.T) {
	db, ctx := liveFirestore(t)

	now := time.Now()
	seeds := map[string]map[string]any{
		"go-port-substatus-q-hit": {
			"tier":         "premium",
			"subscription": map[string]any{"status": "active", "expires_at": now.Add(-time.Hour)},
		},
		"go-port-substatus-q-future": {
			"tier":         "premium",
			"subscription": map[string]any{"status": "active", "expires_at": now.Add(24 * time.Hour)},
		},
		"go-port-substatus-q-free": {
			"tier":         "free",
			"subscription": map[string]any{"status": "active", "expires_at": now.Add(-time.Hour)},
		},
	}
	for uid, data := range seeds {
		ref := db.Collection("users").Doc(uid)
		t.Cleanup(func() { _, _ = ref.Delete(ctx) })
		if _, err := ref.Set(ctx, data); err != nil {
			t.Fatal(err)
		}
	}

	it := db.Collection("users").
		Where("tier", "==", "premium").
		Where("subscription.expires_at", "<", now).
		Documents(ctx)
	defer it.Stop()

	found := map[string]bool{}
	for {
		doc, err := it.Next()
		if err == iterator.Done {
			break
		}
		if err != nil {
			t.Fatalf("クエリに失敗（複合インデックスが無い？）: %v", err)
		}
		found[doc.Ref.ID] = true
	}

	if !found["go-port-substatus-q-hit"] {
		t.Error("期限切れ premium が拾えていない")
	}
	if found["go-port-substatus-q-future"] {
		t.Error("期限が未来の premium を拾ってしまった")
	}
	if found["go-port-substatus-q-free"] {
		t.Error("free ユーザーを拾ってしまった")
	}
}

func liveFirestore(t *testing.T) (*firestore.Client, context.Context) {
	t.Helper()
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
	t.Cleanup(func() { _ = db.Close() })
	return db, ctx
}
