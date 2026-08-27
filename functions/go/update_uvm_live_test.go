package function

import (
	"bytes"
	"context"
	"encoding/json"
	"math"
	"os"
	"os/exec"
	"testing"

	"cloud.google.com/go/firestore"
	firebase "firebase.google.com/go/v4"

	"github.com/mnbst/thai-memo/functions/go/internal/uvm"
)

// TestUpdateUvmDiffAgainstPython は Go 版と Python 版の batch_update_uvm を
// **同じ種から実 dev Firestore に対して**走らせ、書き込まれた結果を突き合わせる。
//
// 純粋関数（update_p 等）は internal/uvm の golden テストで固定済みなので、
// ここが見るのは Firestore への反映（更新/新規の分岐、estimated_vocab の同期）。
//
//	GCLOUD_PROJECT=thai-memo-dev LIVE_FIRESTORE_TEST=1 \
//	  go test -run TestUpdateUvmDiffAgainstPython -v .
func TestUpdateUvmDiffAgainstPython(t *testing.T) {
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

	freqRank, err := uvm.GetFreqRank(ctx, project)
	if err != nil {
		t.Fatal(err)
	}
	t.Logf("freq_rank: %d 語", len(freqRank))

	// rank 順に並べて、低rank/中rank/高rank/未収録 をまたぐ語を選ぶ。
	byRank := map[int]string{}
	for w, r := range freqRank {
		byRank[r] = w
	}
	pick := func(r int) string {
		w, ok := byRank[r]
		if !ok {
			t.Fatalf("rank %d の語が freq_rank に無い", r)
		}
		return w
	}

	type quizResult struct {
		Word             string `json:"word"`
		IsCorrect        bool   `json:"is_correct"`
		HintLevel        int    `json:"hint_level"`
		SentenceReviewed bool   `json:"sentence_reviewed"`
	}
	results := []quizResult{
		{Word: pick(1), IsCorrect: true, HintLevel: 0},
		{Word: pick(5), IsCorrect: false, HintLevel: 0},
		{Word: pick(40), IsCorrect: true, HintLevel: 1},
		{Word: pick(42), IsCorrect: true, HintLevel: 2},
		{Word: pick(60), IsCorrect: false, HintLevel: 1},
		{Word: pick(200), IsCorrect: true, HintLevel: 0, SentenceReviewed: true},
		{Word: "この語はfreq_rankに無い", IsCorrect: true, HintLevel: 0},
	}

	// 既存語の更新分岐も踏ませるため、一部は事前に doc を置いておく。
	preexisting := map[string]struct {
		P        float64
		Attempts int
	}{
		results[0].Word: {P: 0.42, Attempts: 3},
		results[4].Word: {P: 0.81, Attempts: 17},
	}

	const uidGo, uidPy = "go-port-uvm-diff-go", "go-port-uvm-diff-py"

	t.Cleanup(func() {
		for _, uid := range []string{uidGo, uidPy} {
			purgeUser(ctx, db, uid)
		}
	})

	for _, uid := range []string{uidGo, uidPy} {
		purgeUser(ctx, db, uid)
		// free ユーザー（tier 未設定）・estimated_vocab は途中の値から始める
		if _, err := db.Collection("users").Doc(uid).Set(ctx, map[string]any{
			"estimated_vocab": 30,
		}); err != nil {
			t.Fatal(err)
		}
		for word, seed := range preexisting {
			if _, err := db.Collection("users").Doc(uid).Collection("uvm").Doc(word).
				Set(ctx, map[string]any{
					"word": word, "p": seed.P, "quiz_attempts": seed.Attempts,
					"last_seen": 1.0, "last_result": false,
				}); err != nil {
				t.Fatal(err)
			}
		}
	}

	// --- Go 版 ---
	goResults := make([]uvm.Result, 0, len(results))
	for _, r := range results {
		goResults = append(goResults, uvm.Result{
			Word: r.Word, IsCorrect: r.IsCorrect,
			HintLevel: r.HintLevel, SentenceReviewed: r.SentenceReviewed,
		})
	}
	if err := uvm.BatchUpdate(ctx, db, uidGo, goResults, freqRank, "", false); err != nil {
		t.Fatal(err)
	}

	// --- Python 版 ---
	payload, _ := json.Marshal(map[string]any{
		"uid": uidPy, "results": results, "quiz_type": "", "is_premium": false,
	})
	cmd := exec.Command("uv", "run", "python", "scripts/uvm_golden/run_batch_update.py")
	cmd.Dir = "../python"
	cmd.Stdin = bytes.NewReader(payload)
	cmd.Env = append(os.Environ(), "GCLOUD_PROJECT="+project)
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	if err := cmd.Run(); err != nil {
		t.Fatalf("Python 版の実行に失敗: %v\n%s", err, stderr.String())
	}

	// --- 突き合わせ ---
	for _, r := range results {
		g := getDoc(t, ctx, db, uidGo, r.Word)
		p := getDoc(t, ctx, db, uidPy, r.Word)
		if g == nil || p == nil {
			t.Errorf("%s: go=%v py=%v （片方だけ書かれている）", r.Word, g != nil, p != nil)
			continue
		}
		// last_seen は時刻なので比較しない。
		for _, key := range []string{"p", "quiz_attempts", "last_result", "word"} {
			gv, pv := g[key], p[key]
			if fg, ok := toFloat(gv); ok {
				fp, _ := toFloat(pv)
				if math.Abs(fg-fp) > 1e-12 {
					t.Errorf("%s.%s: go=%v py=%v", r.Word, key, gv, pv)
				}
				continue
			}
			if gv != pv {
				t.Errorf("%s.%s: go=%#v py=%#v", r.Word, key, gv, pv)
			}
		}
	}

	gu := userDoc(t, ctx, db, uidGo)
	pu := userDoc(t, ctx, db, uidPy)
	if gu["estimated_vocab"] != pu["estimated_vocab"] {
		t.Errorf("estimated_vocab: go=%v py=%v", gu["estimated_vocab"], pu["estimated_vocab"])
	}
	t.Logf("estimated_vocab: %v (30 から同期)", gu["estimated_vocab"])

	// leaderboard も両方に出ているはず（nickname は乱数なので値は比較しない）
	for _, uid := range []string{uidGo, uidPy} {
		snap, err := db.Collection("leaderboard").Doc(uid).Get(ctx)
		if err != nil || !snap.Exists() {
			t.Errorf("leaderboard/%s が無い", uid)
			continue
		}
		if _, ok := snap.Data()["nickname"].(string); !ok {
			t.Errorf("leaderboard/%s に nickname が無い", uid)
		}
	}
}

func toFloat(v any) (float64, bool) {
	switch n := v.(type) {
	case float64:
		return n, true
	case int64:
		return float64(n), true
	}
	return 0, false
}

func getDoc(t *testing.T, ctx context.Context, db *firestore.Client, uid, word string) map[string]any {
	t.Helper()
	snap, err := db.Collection("users").Doc(uid).Collection("uvm").Doc(word).Get(ctx)
	if err != nil || !snap.Exists() {
		return nil
	}
	return snap.Data()
}

func userDoc(t *testing.T, ctx context.Context, db *firestore.Client, uid string) map[string]any {
	t.Helper()
	snap, err := db.Collection("users").Doc(uid).Get(ctx)
	if err != nil {
		t.Fatal(err)
	}
	return snap.Data()
}

// purgeUser はテスト用 uid の痕跡を消す。nicknames は leaderboard から辿る。
func purgeUser(ctx context.Context, db *firestore.Client, uid string) {
	if snap, err := db.Collection("leaderboard").Doc(uid).Get(ctx); err == nil && snap.Exists() {
		if name, ok := snap.Data()["nickname"].(string); ok && name != "" {
			_, _ = db.Collection("nicknames").Doc(lower(name)).Delete(ctx)
		}
	}
	_, _ = db.Collection("leaderboard").Doc(uid).Delete(ctx)

	it := db.Collection("users").Doc(uid).Collection("uvm").DocumentRefs(ctx)
	for {
		ref, err := it.Next()
		if err != nil {
			break
		}
		_, _ = ref.Delete(ctx)
	}
	_, _ = db.Collection("users").Doc(uid).Delete(ctx)
}

func lower(s string) string {
	b := []byte(s)
	for i := range b {
		if b[i] >= 'A' && b[i] <= 'Z' {
			b[i] += 'a' - 'A'
		}
	}
	return string(b)
}
