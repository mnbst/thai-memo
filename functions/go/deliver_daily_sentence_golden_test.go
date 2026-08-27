package function

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"strconv"
	"strings"
	"testing"
	"time"

	"cloud.google.com/go/firestore"

	"github.com/mnbst/thai-memo/functions/go/internal/sentence"
	"github.com/mnbst/thai-memo/functions/go/internal/uvm"
)

type deliveryGolden struct {
	Now           string `json:"now"`
	BuildSentence []struct {
		Name     string         `json:"name"`
		UserData map[string]any `json:"user_data"`
		Calls    []struct {
			Params         map[string]any `json:"params"`
			UsePremiumSpec bool           `json:"use_premium_spec"`
			EstimatedVocab int            `json:"estimated_vocab"`
			CacheOnly      bool           `json:"cache_only"`
			SelectRetry    int            `json:"select_retry"`
			Lang           string         `json:"lang"`
		} `json:"calls"`
		PremiumResult string `json:"premium_result"`
		Want          *struct {
			TargetWords    []string `json:"target_words"`
			UsePremiumSpec bool     `json:"use_premium_spec"`
		} `json:"want"`
	} `json:"build_sentence"`
	Commit []struct {
		Name           string         `json:"name"`
		UserData       map[string]any `json:"user_data"`
		Outcome        string         `json:"outcome"`
		Token          string         `json:"token"`
		Restore        map[string]any `json:"restore"`
		StoppedUpdates map[string]any `json:"stopped_updates"`
		UserUpdate     map[string]any `json:"user_update"`
		WroteSentence  int            `json:"wrote_sentence"`
	} `json:"commit"`
	Rollback []struct {
		Restore         map[string]any `json:"restore"`
		DeleteToken     bool           `json:"delete_token"`
		SentenceDeleted int            `json:"sentence_deleted"`
		UserUpdate      map[string]any `json:"user_update"`
	} `json:"rollback"`
}

func loadDeliveryGolden(t *testing.T) *deliveryGolden {
	t.Helper()
	raw, err := os.ReadFile("../python/scripts/daily_golden/delivery_golden.json")
	if err != nil {
		t.Fatalf("golden を読めない: %v", err)
	}
	var g deliveryGolden
	if err := json.Unmarshal(raw, &g); err != nil {
		t.Fatalf("golden を parse できない: %v", err)
	}
	return &g
}

// deliveryTimestampFields は golden で ISO 文字列として出ている timestamp。
// Firestore は time.Time で返すので、読み込み時に戻す。
var deliveryTimestampFields = map[string]bool{
	"last_notified_at":           true,
	"last_sentence_generated_at": true,
	"last_opened_at":             true,
	"premium_trial_expires_at":   true,
}

func deliveryUserData(t *testing.T, raw map[string]any) map[string]any {
	t.Helper()
	if raw == nil {
		return map[string]any{}
	}
	out := make(map[string]any, len(raw))
	for k, v := range raw {
		out[k] = deliveryValue(t, k, v)
	}
	return out
}

func deliveryValue(t *testing.T, key string, v any) any {
	t.Helper()
	if s, ok := v.(string); ok && deliveryTimestampFields[key] && strings.Contains(s, "T") {
		ts, err := time.Parse(time.RFC3339, s)
		if err != nil {
			t.Fatalf("%s を時刻として読めない: %v", key, err)
		}
		return ts.UTC()
	}
	// JSON の数値は float64 で来る。Firestore は整数を int64 で返すので揃える。
	if f, ok := v.(float64); ok && f == float64(int64(f)) {
		return int64(f)
	}
	return v
}

// stubProducer は Produce の呼び出しを記録する。
type stubProducer struct {
	calls   []sentence.ProduceRequest
	premium string // "ok" / "raise" / "none"
	noCache bool
}

func (p *stubProducer) Produce(
	_ context.Context, _ *firestore.Client, _ uvm.FreqRank, req sentence.ProduceRequest,
) (*sentence.Produced, error) {
	p.calls = append(p.calls, req)
	if req.UsePremiumSpec {
		switch p.premium {
		case "raise":
			return nil, errors.New("LLM down")
		case "none":
			return nil, nil
		}
		return &sentence.Produced{
			Sentence: &sentence.Sentence{}, TargetWords: []string{"w1"},
			ChosenTopic: "topic1",
		}, nil
	}
	if p.noCache {
		return nil, nil
	}
	return &sentence.Produced{
		Sentence: &sentence.Sentence{}, TargetWords: []string{"w2"},
		ChosenTopic: "topic2", FromCache: true,
	}, nil
}

func TestDeliveryBuildSentenceGolden(t *testing.T) {
	golden := loadDeliveryGolden(t)
	now, err := time.Parse(time.RFC3339, golden.Now)
	if err != nil {
		t.Fatalf("now を読めない: %v", err)
	}

	premiumPaths, cachePaths := 0, 0
	for _, c := range golden.BuildSentence {
		userData := deliveryUserData(t, c.UserData)
		stub := &stubProducer{
			premium: c.PremiumResult,
			noCache: userData["no_cache"] == true,
		}
		// ヒアリングからのテーマは抽選なので値までは比べない（指定の有無だけ見る）。
		d := &deliverer{Producer: stub}
		got := d.buildSentence(context.Background(), "uid", userData, now)

		if len(stub.calls) != len(c.Calls) {
			t.Errorf("%s: Produce の呼び出し回数 %d, want %d",
				c.Name, len(stub.calls), len(c.Calls))
			continue
		}
		for i, want := range c.Calls {
			got := stub.calls[i]
			if got.UsePremiumSpec != want.UsePremiumSpec ||
				got.EstimatedVocab != want.EstimatedVocab ||
				got.CacheOnly != want.CacheOnly ||
				got.SelectRetry != want.SelectRetry ||
				string(got.Lang) != want.Lang {
				t.Errorf("%s: Produce[%d] 不一致\n got: %+v\nwant: %+v",
					c.Name, i, got, want)
			}
			// テーマは指定の有無だけ比べる（値は Python 側の stub 依存）。
			if (got.Params["topic"] != nil) != (want.Params["topic"] != nil) {
				t.Errorf("%s: Produce[%d] の topic 指定が不一致: got=%v want=%v",
					c.Name, i, got.Params["topic"], want.Params["topic"])
			}
			if want.UsePremiumSpec {
				premiumPaths++
			} else {
				cachePaths++
			}
		}

		switch {
		case c.Want == nil && got != nil:
			t.Errorf("%s: 配信しないはずが例文が返った", c.Name)
		case c.Want != nil && got == nil:
			t.Errorf("%s: 例文が返らなかった", c.Name)
		case c.Want != nil:
			if got.UsePremiumSpec != c.Want.UsePremiumSpec {
				t.Errorf("%s: use_premium_spec %v, want %v",
					c.Name, got.UsePremiumSpec, c.Want.UsePremiumSpec)
			}
			if fmt.Sprint(got.Produced.TargetWords) != fmt.Sprint(c.Want.TargetWords) {
				t.Errorf("%s: target_words %v, want %v",
					c.Name, got.Produced.TargetWords, c.Want.TargetWords)
			}
		}
	}
	t.Logf("%d ケース一致 (premium 経路 %d / キャッシュ経路 %d)",
		len(golden.BuildSentence), premiumPaths, cachePaths)

	if premiumPaths == 0 || cachePaths == 0 {
		t.Error("premium 経路とキャッシュ経路の両方を踏んでいない。golden が退化している")
	}
}

func TestDeliveryCommitGolden(t *testing.T) {
	golden := loadDeliveryGolden(t)
	now, err := time.Parse(time.RFC3339, golden.Now)
	if err != nil {
		t.Fatalf("now を読めない: %v", err)
	}

	outcomes := map[string]int{}
	for _, c := range golden.Commit {
		userData := deliveryUserData(t, c.UserData)
		token, restore, update, err := dailyCommitPlan(userData, now)

		var stopped *deliveryStoppedError
		outcome := "delivered"
		switch {
		case errors.Is(err, errDeliveryNotDue):
			outcome = "not_due"
		case errors.As(err, &stopped):
			outcome = "stopped"
		case err != nil:
			t.Fatalf("%s: 予期しないエラー: %v", c.Name, err)
		}
		outcomes[outcome]++
		if outcome != c.Outcome {
			t.Errorf("%s: outcome %q, want %q", c.Name, outcome, c.Outcome)
			continue
		}

		switch outcome {
		case "stopped":
			assertUpdates(t, c.Name+"/stopped", stopped.updates, c.StoppedUpdates)
		case "delivered":
			if token != c.Token {
				t.Errorf("%s: token %q, want %q", c.Name, token, c.Token)
			}
			assertUpdates(t, c.Name+"/update", update, c.UserUpdate)
			assertUpdates(t, c.Name+"/restore", restore, c.Restore)
		}
	}
	t.Logf("%d ケース一致 %v", len(golden.Commit), outcomes)

	for _, want := range []string{"delivered", "not_due", "stopped"} {
		if outcomes[want] == 0 {
			t.Errorf("%s のケースが無い。golden が退化している", want)
		}
	}
}

func TestDeliveryRollbackGolden(t *testing.T) {
	golden := loadDeliveryGolden(t)
	for i, c := range golden.Rollback {
		restore := make([]firestore.Update, 0, len(c.Restore))
		// Python の dict 順に依存しないよう、Go 側の並びに合わせて組み立てる。
		for _, path := range []string{
			"notify_tier", "notify_tier_misses", "last_notified_at",
		} {
			v, ok := c.Restore[path]
			if !ok {
				t.Fatalf("rollback[%d]: restore に %s が無い", i, path)
			}
			restore = append(restore, firestore.Update{
				Path: path, Value: goldenValue(t, path, v)})
		}
		got := rollbackUpdate(restore, c.DeleteToken)
		assertUpdates(t, fmt.Sprintf("rollback[%d]", i), got, c.UserUpdate)
	}
	t.Logf("%d ケース一致", len(golden.Rollback))
}

// assertUpdates は firestore.Update の集合が golden の dict と一致するか見る。
// 並び順は問わない（Firestore はフィールド名で解決するため）。
func assertUpdates(t *testing.T, name string, got []firestore.Update, want map[string]any) {
	t.Helper()
	if len(got) != len(want) {
		t.Errorf("%s: フィールド数 %d, want %d (got=%v want=%v)",
			name, len(got), len(want), got, want)
		return
	}
	for _, u := range got {
		w, ok := want[u.Path]
		if !ok {
			t.Errorf("%s: 想定外のフィールド %s", name, u.Path)
			continue
		}
		if !sameUpdateValue(t, u.Path, u.Value, w) {
			t.Errorf("%s: %s = %v, want %v", name, u.Path, u.Value, w)
		}
	}
}

func sameUpdateValue(t *testing.T, path string, got any, want any) bool {
	t.Helper()
	return fmt.Sprint(got) == fmt.Sprint(goldenValue(t, path, want))
}

// goldenValue は golden の記号（@server_timestamp など）を firestore の値へ戻す。
func goldenValue(t *testing.T, path string, v any) any {
	t.Helper()
	s, ok := v.(string)
	if !ok {
		return deliveryValue(t, path, v)
	}
	switch {
	case s == "@server_timestamp":
		return firestore.ServerTimestamp
	case s == "@delete":
		return firestore.Delete
	case strings.HasPrefix(s, "@increment:"):
		n, err := strconv.Atoi(strings.TrimPrefix(s, "@increment:"))
		if err != nil {
			t.Fatalf("%s: increment を読めない: %v", path, err)
		}
		return firestore.Increment(n)
	}
	return deliveryValue(t, path, v)
}
