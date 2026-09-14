package function

import (
	"testing"
	"time"

	"github.com/mnbst/thai-memo/functions/go/internal/quota"
)

// lifetimeUser は買い切りへ移行済みのユーザー doc（月額の期限は過ぎている）。
func lifetimeUser(status string) map[string]any {
	return map[string]any{
		"tier": "premium",
		"subscription": map[string]any{
			"platform":        "ios",
			"product_id":      "premium_monthly",
			"status":          status,
			"expires_at":      time.Date(2026, 9, 1, 0, 0, 0, 0, time.UTC),
			"lifetime":        true,
			"lifetime_source": "monthly_migration",
		},
	}
}

// TestLifetimeMigrationSurvivesDailyBatch は、移行済みユーザーが日次リセットで
// free に落ちないこと。月額の期限はとっくに過ぎている状態で確かめる。
func TestLifetimeMigrationSurvivesDailyBatch(t *testing.T) {
	now := time.Date(2026, 10, 1, 15, 30, 0, 0, time.UTC)

	got := quotaResetPayload("migrated", lifetimeUser("expired"), now)
	if got["remaining_sentences"] != quota.PremiumDailySentences {
		t.Errorf("移行済みが premium 扱いになっていない: %v", got["remaining_sentences"])
	}
}

// TestLifetimeMigrationSurvivesAppStoreExpiry は、解約後に届く EXPIRED で
// 移行済みユーザーを落とさないこと。返金・取消は従来どおり落とすこと。
func TestLifetimeMigrationSurvivesAppStoreExpiry(t *testing.T) {
	expired := appStoreDecision{Tier: "free", Status: "expired", Handled: true}

	for _, notificationType := range []string{
		"EXPIRED", "GRACE_PERIOD_EXPIRED", "DID_FAIL_TO_RENEW",
	} {
		got := keepPremiumForLifetime(
			expired, lifetimeUser("active"), notificationType)
		if got.Tier != "premium" {
			t.Errorf("%s で移行済みを落としている: tier=%s", notificationType, got.Tier)
		}
		if got.Status != "expired" {
			t.Errorf("%s で subscription.status を書き換えている: %s",
				notificationType, got.Status)
		}
	}

	// 返金・取消は権利ごと剥がす（無償移行の抜け道にしない）。
	for _, notificationType := range []string{"REFUND", "REVOKE"} {
		got := keepPremiumForLifetime(
			expired, lifetimeUser("active"), notificationType)
		if got.Tier != "free" {
			t.Errorf("%s なのに premium を残している", notificationType)
		}
	}

	// 印が無い人はこれまでどおり落ちる。
	plain := map[string]any{
		"tier": "premium",
		"subscription": map[string]any{
			"platform": "ios", "product_id": "premium_monthly", "status": "active",
		},
	}
	if got := keepPremiumForLifetime(expired, plain, "EXPIRED"); got.Tier != "free" {
		t.Errorf("印が無いのに premium を残している")
	}
}
