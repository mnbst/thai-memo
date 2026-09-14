package function

import (
	"testing"
	"time"

	"github.com/mnbst/thai-memo/functions/go/internal/appstore"
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

// TestVerifyKeepsLifetimeMark は、月額の検証が買い切りの印を消さないこと。
//
// 買い切り購入者・無償移行者は月額も持っている（自動更新も続く）。その
// 自動更新ぶんが購入ストリームから検証されたときに印が消えると、解約時に
// free へ落ちてしまい、受付期限後は取り返せない。
func TestVerifyKeepsLifetimeMark(t *testing.T) {
	monthly := subscriptionRecord("ios", productIDPremiumMonthly, "tx-1")
	if _, ok := monthly["lifetime"]; ok {
		t.Errorf("月額の検証が lifetime を書いている: %v", monthly["lifetime"])
	}

	android := subscriptionRecord("android", productIDPremiumMonthly, "token-1")
	if _, ok := android["lifetime"]; ok {
		t.Errorf("Android 月額の検証が lifetime を書いている: %v", android["lifetime"])
	}

	lifetime := subscriptionRecord("ios", productIDPremiumLifetime, "tx-2")
	if lifetime["lifetime"] != true {
		t.Errorf("買い切りの検証で印が立っていない: %v", lifetime["lifetime"])
	}
}

// TestLifetimeRefundClearsMark は、買い切りの返金・取消で印そのものを外すこと。
// 印が残ると、そのあと月額を買った人が解約後も premium のままになる。
// 月額の返金では外さない（買い切りの権利を巻き添えにしない）。
func TestLifetimeRefundClearsMark(t *testing.T) {
	free := appStoreDecision{Tier: "free", Status: "expired", Handled: true}

	clears := func(productID, notificationType string) bool {
		n := &appstore.Notification{NotificationType: notificationType}
		n.TransactionInfo.ProductID = productID
		for _, u := range appStoreUpdates(n, free, "premium", "uid") {
			if u.Path == "subscription.lifetime" {
				return u.Value == false
			}
		}
		return false
	}

	for _, notificationType := range []string{"REFUND", "REVOKE"} {
		if !clears(productIDPremiumLifetime, notificationType) {
			t.Errorf("買い切りの %s で印を外していない", notificationType)
		}
		if clears(productIDPremiumMonthly, notificationType) {
			t.Errorf("月額の %s で買い切りの印まで外している", notificationType)
		}
	}
	if clears(productIDPremiumLifetime, "EXPIRED") {
		t.Error("EXPIRED で買い切りの印を外している")
	}
}
