package function

import (
	"bytes"
	"context"
	"encoding/json"
	"os"
	"os/exec"
	"strings"
	"testing"

	"cloud.google.com/go/firestore"
	firebase "firebase.google.com/go/v4"
	"google.golang.org/api/iterator"

	"github.com/mnbst/thai-memo/functions/go/internal/tier"
)

// TestApplyTierDiffAgainstJS は Go 版と JS 版の applyTier を同じ種から
// 実 dev Firestore に対して走らせ、users と tier_grants の中身を突き合わせる。
//
// 事前に JS 側をコンパイルしておくこと:
//
//	cd functions/javascript && node node_modules/typescript/bin/tsc \
//	  scripts/runApplyTier.ts src/services/tierService.ts \
//	  --outDir .difftest-build --rootDir . --module commonjs --target ES2020 \
//	  --esModuleInterop --skipLibCheck --resolveJsonModule --types node
//
//	GCLOUD_PROJECT=thai-memo-dev LIVE_FIRESTORE_TEST=1 \
//	  go test -run TestApplyTierDiffAgainstJS -v .
func TestApplyTierDiffAgainstJS(t *testing.T) {
	if os.Getenv("LIVE_FIRESTORE_TEST") == "" {
		t.Skip("LIVE_FIRESTORE_TEST が未設定")
	}
	project := os.Getenv("GCLOUD_PROJECT")

	ctx := context.Background()
	app, err := firebase.NewApp(ctx, &firebase.Config{ProjectID: project})
	if err != nil {
		t.Fatal(err)
	}
	db, err := app.Firestore(ctx)
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	cases := []struct {
		name    string
		seed    map[string]any
		tier    tier.Tier
		days    int
		force   bool
		wantErr bool // 両実装ともエラーになるはず
	}{
		{
			name: "free から premium（30日）",
			seed: map[string]any{"tier": "free"},
			tier: tier.Premium, days: 30,
		},
		{
			name: "free から premium（無期限）",
			seed: map[string]any{"tier": "free"},
			tier: tier.Premium, days: 0,
		},
		{
			name: "premium から free",
			seed: map[string]any{"tier": "premium"},
			tier: tier.Free, days: 30,
		},
		{
			name: "tier 据え置き（クォータを触らない）",
			seed: map[string]any{"tier": "premium", "remaining_sentences": 3},
			tier: tier.Premium, days: 7,
		},
		{
			name: "ストア購入が有効 → force なしは拒否",
			seed: map[string]any{"tier": "premium", "subscription": map[string]any{
				"platform": "ios", "status": "active", "purchase_token": "keep-me",
			}},
			tier: tier.Free, days: 30, wantErr: true,
		},
		{
			name: "ストア購入が有効 → force ありは上書き",
			seed: map[string]any{"tier": "premium", "subscription": map[string]any{
				"platform": "ios", "status": "active", "purchase_token": "keep-me",
			}},
			tier: tier.Free, days: 30, force: true,
		},
		{
			name: "ストア購入だが失効 → subscription を触らない",
			seed: map[string]any{"tier": "free", "subscription": map[string]any{
				"platform": "android", "status": "expired", "purchase_token": "keep-me",
			}},
			tier: tier.Premium, days: 30,
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			uidGo := "go-port-tier-diff-go"
			uidJS := "go-port-tier-diff-js"

			t.Cleanup(func() {
				for _, uid := range []string{uidGo, uidJS} {
					_, _ = db.Collection("users").Doc(uid).Delete(ctx)
					deleteGrants(ctx, db, uid)
				}
			})

			for _, uid := range []string{uidGo, uidJS} {
				_, _ = db.Collection("users").Doc(uid).Delete(ctx)
				deleteGrants(ctx, db, uid)
				if _, err := db.Collection("users").Doc(uid).Set(ctx, tc.seed); err != nil {
					t.Fatal(err)
				}
			}

			goRes, goErr := tier.ApplyTier(ctx, db, tier.Params{
				UID: uidGo, Tier: tc.tier, DurationDays: tc.days,
				Source: "admin", Actor: "tester", Reason: "diff test", Force: tc.force,
			})

			jsRes := runJSApplyTier(t, project, map[string]any{
				"uid": uidJS, "tier": string(tc.tier), "durationDays": tc.days,
				"source": "admin", "actor": "tester", "reason": "diff test", "force": tc.force,
			})

			jsFailed := jsRes["error"] != nil
			if (goErr != nil) != jsFailed {
				t.Fatalf("エラーの有無が違う: go=%v js=%v", goErr, jsRes["error"])
			}
			if tc.wantErr {
				if goErr == nil {
					t.Fatal("拒否されるはずが通った")
				}
				t.Logf("両実装とも拒否: %v", goErr)
				return
			}
			if goErr != nil {
				t.Fatal(goErr)
			}

			// 返り値
			if s, _ := jsRes["previousTier"].(string); s != string(goRes.PreviousTier) {
				t.Errorf("previous_tier: go=%s js=%s", goRes.PreviousTier, s)
			}
			// expires_at は「now + days」なので実行時刻ぶんズレる。
			// null かどうかだけ揃っていればよい。
			goNull := goRes.ExpiresAt == ""
			jsNull := jsRes["expiresAt"] == nil
			if goNull != jsNull {
				t.Errorf("expires_at の null 一致せず: go=%q js=%v", goRes.ExpiresAt, jsRes["expiresAt"])
			}

			// users ドキュメント
			gu := userDoc(t, ctx, db, uidGo)
			ju := userDoc(t, ctx, db, uidJS)
			compareDocs(t, "users", gu, ju, map[string]bool{
				// 時刻・自動採番は比較から外す
				"subscription.updated_at": true,
				"subscription.expires_at": true,
			})

			// tier_grants（1件だけ増えているはず）
			gg := grants(t, ctx, db, uidGo)
			jg := grants(t, ctx, db, uidJS)
			if len(gg) != 1 || len(jg) != 1 {
				t.Fatalf("tier_grants の件数: go=%d js=%d", len(gg), len(jg))
			}
			compareDocs(t, "tier_grants", gg[0], jg[0], map[string]bool{
				"created_at": true,
				"expires_at": true,
				"uid":        true, // 比較用に別 uid を使っているので当然ずれる
			})
		})
	}
}

func runJSApplyTier(t *testing.T, project string, req map[string]any) map[string]any {
	t.Helper()
	payload, _ := json.Marshal(req)
	cmd := exec.Command("node", ".difftest-build/scripts/runApplyTier.js")
	cmd.Dir = "../javascript"
	cmd.Stdin = bytes.NewReader(payload)
	cmd.Env = append(os.Environ(), "GCLOUD_PROJECT="+project)
	var out, errb bytes.Buffer
	cmd.Stdout = &out
	cmd.Stderr = &errb
	if err := cmd.Run(); err != nil {
		t.Fatalf("JS 版の実行に失敗: %v\n%s", err, errb.String())
	}
	// applyTier は console.log を吐くので、JSON は最後の行だけを取る。
	lines := strings.Split(strings.TrimSpace(out.String()), "\n")
	last := lines[len(lines)-1]

	var res map[string]any
	if err := json.Unmarshal([]byte(last), &res); err != nil {
		t.Fatalf("JS の出力を解釈できない: %q (stderr=%s)", out.String(), errb.String())
	}
	return res
}

// compareDocs は2つのドキュメントを再帰的に比べる。skip はドット区切りのパス。
func compareDocs(t *testing.T, label string, a, b map[string]any, skip map[string]bool) {
	t.Helper()
	compareMaps(t, label, "", a, b, skip)
}

func compareMaps(t *testing.T, label, prefix string, a, b map[string]any, skip map[string]bool) {
	t.Helper()
	keys := map[string]bool{}
	for k := range a {
		keys[k] = true
	}
	for k := range b {
		keys[k] = true
	}
	for k := range keys {
		path := k
		if prefix != "" {
			path = prefix + "." + k
		}
		if skip[path] {
			continue
		}
		av, bv := a[k], b[k]
		am, aok := av.(map[string]any)
		bm, bok := bv.(map[string]any)
		if aok && bok {
			compareMaps(t, label, path, am, bm, skip)
			continue
		}
		if !equalScalar(av, bv) {
			t.Errorf("%s.%s: go=%#v js=%#v", label, path, av, bv)
		}
	}
}

func equalScalar(a, b any) bool {
	if af, ok := toFloat(a); ok {
		if bf, ok := toFloat(b); ok {
			return af == bf
		}
		return false
	}
	return a == b
}

func deleteGrants(ctx context.Context, db *firestore.Client, uid string) {
	it := db.Collection("tier_grants").Where("uid", "==", uid).Documents(ctx)
	defer it.Stop()
	for {
		doc, err := it.Next()
		if err != nil {
			return
		}
		_, _ = doc.Ref.Delete(ctx)
	}
}

func grants(t *testing.T, ctx context.Context, db *firestore.Client, uid string) []map[string]any {
	t.Helper()
	it := db.Collection("tier_grants").Where("uid", "==", uid).Documents(ctx)
	defer it.Stop()
	var out []map[string]any
	for {
		doc, err := it.Next()
		if err == iterator.Done {
			return out
		}
		if err != nil {
			t.Fatal(err)
		}
		out = append(out, doc.Data())
	}
}
