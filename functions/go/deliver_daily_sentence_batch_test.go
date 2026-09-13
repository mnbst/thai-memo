package function

import (
	"context"
	"fmt"
	"testing"
	"time"

	"cloud.google.com/go/firestore"

	"github.com/mnbst/thai-memo/functions/go/internal/dailysentence"
)

// batchUserData は配信条件を満たす user doc（golden の「配信する」ケースと同じ形）。
func batchUserData(now time.Time) map[string]any {
	return map[string]any{
		"fcm_token":                  "tok",
		"daily_reminder_enabled":     true,
		"timezone":                   "UTC",
		"remaining_sentences":        int64(20),
		"daily_sentence_generated":   false,
		"preferred_generation_hour":  int64(now.UTC().Hour()),
		"last_sentence_generated_at": now.Add(-24 * time.Hour),
		"app_version":                "1.4.8",
	}
}

func TestBuildSentencesBatch(t *testing.T) {
	now := time.Date(2026, 8, 27, 1, 0, 0, 0, time.UTC)
	for _, c := range []struct {
		name string
		tier string
		want bool // premium 経路で返るか
	}{
		{"premium は LLM で5本", "premium", true},
		{"free はキャッシュで5本", "free", false},
	} {
		userData := batchUserData(now)
		userData["tier"] = c.tier
		stub := &stubProducer{}
		d := &deliverer{Producer: stub}

		got := d.buildSentences(context.Background(), "uid", userData, now, dailysentence.DailyBatchSize)
		if got == nil {
			t.Fatalf("%s: 例文が返らなかった", c.name)
		}
		if len(got.Produced) != dailysentence.DailyBatchSize {
			t.Errorf("%s: 本数 %d, want %d", c.name, len(got.Produced), dailysentence.DailyBatchSize)
		}
		if got.UsePremiumSpec != c.want {
			t.Errorf("%s: use_premium_spec %v, want %v", c.name, got.UsePremiumSpec, c.want)
		}
		// 選定はセットで1回。本数は n としてまとめて渡す。
		if len(stub.counts) == 0 || stub.counts[len(stub.counts)-1] != dailysentence.DailyBatchSize {
			t.Errorf("%s: ProduceBatch の本数 %v, want 末尾が %d",
				c.name, stub.counts, dailysentence.DailyBatchSize)
		}
		// key_word はセット内で重複しない。
		seen := map[string]bool{}
		for _, p := range got.Produced {
			w := p.TargetWords[0]
			if seen[w] {
				t.Errorf("%s: key_word %q が重複", c.name, w)
			}
			seen[w] = true
		}
	}
}

// TestDailyCommitPlanConsumesBatch はクォータが配信本数ぶん減ることを確かめる。
// free は5本/日なので、ここが1本のままだと枠が合わない。
func TestDailyCommitPlanConsumesBatch(t *testing.T) {
	now := time.Date(2026, 8, 27, 1, 0, 0, 0, time.UTC)
	_, _, update, err := dailyCommitPlan(batchUserData(now), now, 5)
	if err != nil {
		t.Fatalf("配信できるはずが %v", err)
	}
	assertUpdates(t, "commit/5本", update, map[string]any{
		"remaining_sentences":      "@increment:-5",
		"daily_sentence_generated": true,
		"last_notified_at":         "@server_timestamp",
		"notify_tier":              0,
		"notify_tier_misses":       0,
	})
}

// TestRollbackUpdateRestoresBatch は通知失敗時に本数ぶん戻すことを確かめる。
func TestRollbackUpdateRestoresBatch(t *testing.T) {
	restore := []firestore.Update{
		{Path: "notify_tier", Value: 0},
		{Path: "notify_tier_misses", Value: 0},
		{Path: "last_notified_at", Value: firestore.Delete},
	}
	got := rollbackUpdate(restore, false, 5)
	assertUpdates(t, "rollback/5本", got, map[string]any{
		"remaining_sentences":      "@increment:5",
		"daily_sentence_generated": false,
		"notify_tier":              0,
		"notify_tier_misses":       0,
		"last_notified_at":         "@delete",
	})
}

// TestBuildNotificationSetData は通知の Data にセット情報が載ることを確かめる。
// sentence_id は5本セットを知らない旧版が見るので、1本目の doc ID を残す。
func TestBuildNotificationSetData(t *testing.T) {
	msg := buildNotification("tok", "set1", 5,
		map[string]any{"key_word": "กิน", "thai_text": "ฉันกินข้าว"}, "ja")
	want := map[string]string{
		"type":           "daily_sentence",
		"sentence_id":    "set1",
		"daily_set_id":   "set1",
		"daily_set_size": "5",
	}
	if fmt.Sprint(msg.Data) != fmt.Sprint(want) {
		t.Errorf("Data = %v, want %v", msg.Data, want)
	}
}

// TestDailyCommitPlanPremiumKeepsQuota は premium 配信で
// remaining_sentences に触らないことを確かめる（consumed=0）。
func TestDailyCommitPlanPremiumKeepsQuota(t *testing.T) {
	now := time.Date(2026, 8, 27, 1, 0, 0, 0, time.UTC)
	_, _, update, err := dailyCommitPlan(batchUserData(now), now, 0)
	if err != nil {
		t.Fatalf("配信できるはずが %v", err)
	}
	assertUpdates(t, "commit/premium", update, map[string]any{
		"daily_sentence_generated": true,
		"last_notified_at":         "@server_timestamp",
		"notify_tier":              0,
		"notify_tier_misses":       0,
	})
}

// TestRollbackUpdatePremiumKeepsQuota は消費していない配信の巻き戻しで
// remaining_sentences を増やさないことを確かめる。
func TestRollbackUpdatePremiumKeepsQuota(t *testing.T) {
	got := rollbackUpdate([]firestore.Update{{Path: "notify_tier", Value: 0}}, false, 0)
	assertUpdates(t, "rollback/premium", got, map[string]any{
		"daily_sentence_generated": false,
		"notify_tier":              0,
	})
}
