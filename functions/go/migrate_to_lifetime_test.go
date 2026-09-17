package function

import (
	"testing"
	"time"

	"github.com/mnbst/thai-memo/functions/go/internal/appstore"
	"github.com/mnbst/thai-memo/functions/go/internal/quota"
	"github.com/mnbst/thai-memo/functions/go/internal/subscription"
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

	notify := func(notificationType, productID string) *appstore.Notification {
		n := &appstore.Notification{NotificationType: notificationType}
		n.TransactionInfo.ProductID = productID
		return n
	}

	for _, notificationType := range []string{
		"EXPIRED", "GRACE_PERIOD_EXPIRED", "DID_FAIL_TO_RENEW",
	} {
		got, revoked := keepPremiumForLifetime(expired, lifetimeUser("active"),
			notify(notificationType, productIDPremiumMonthly))
		if got.Tier != "premium" {
			t.Errorf("%s で移行済みを落としている: tier=%s", notificationType, got.Tier)
		}
		if revoked {
			t.Errorf("%s で買い切りの印まで外している", notificationType)
		}
		if got.Status != "expired" {
			t.Errorf("%s で subscription.status を書き換えている: %s",
				notificationType, got.Status)
		}
	}

	// 無償移行で得た権利は、元になった月額の返金・取消で剥がす
	//（「月額を買って返金する」を無償移行の入口にしない）。
	for _, notificationType := range []string{"REFUND", "REVOKE"} {
		got, revoked := keepPremiumForLifetime(expired, lifetimeUser("active"),
			notify(notificationType, productIDPremiumMonthly))
		if got.Tier != "free" {
			t.Errorf("%s なのに premium を残している", notificationType)
		}
		// 印を残すと、月額を買い直して解約するだけで premium が永久に戻る。
		if !revoked {
			t.Errorf("%s で tier だけ落として印を残している", notificationType)
		}
	}

	// 買い切りを購入した人は、無関係な月額の返金では権利を失わない。
	// 買い切りそのものの返金なら剥がす。
	purchased := func() map[string]any {
		u := lifetimeUser("active")
		sub := u["subscription"].(map[string]any)
		delete(sub, "lifetime_source")
		sub["lifetime_transaction_id"] = "tx-lifetime"
		return u
	}
	for _, notificationType := range []string{"REFUND", "REVOKE"} {
		got, revoked := keepPremiumForLifetime(expired, purchased(),
			notify(notificationType, productIDPremiumMonthly))
		if got.Tier != "premium" || revoked {
			t.Errorf("月額の %s で購入済みの買い切りまで剥がしている", notificationType)
		}
		got, revoked = keepPremiumForLifetime(expired, purchased(),
			notify(notificationType, productIDPremiumLifetime))
		if got.Tier != "free" || !revoked {
			t.Errorf("買い切りの %s なのに権利を残している", notificationType)
		}
	}

	// 印が無い人はこれまでどおり落ちる。
	plain := map[string]any{
		"tier": "premium",
		"subscription": map[string]any{
			"platform": "ios", "product_id": "premium_monthly", "status": "active",
		},
	}
	got, _ := keepPremiumForLifetime(expired, plain,
		notify("EXPIRED", productIDPremiumMonthly))
	if got.Tier != "free" {
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

func TestVerifyRevokedLifetimeDoesNotRestoreMark(t *testing.T) {
	record := subscriptionRecord("ios", productIDPremiumLifetime, "tx-refunded")
	applyVerifiedLifetimeState(record, true, "free")

	if record["lifetime"] != false {
		t.Errorf("返金済み買い切りの印が残っている: %v", record["lifetime"])
	}
	if record["lifetime_transaction_id"] != nil {
		t.Errorf("返金済み買い切りの取引IDが残っている: %v",
			record["lifetime_transaction_id"])
	}
}

func TestLifetimeVerificationPreservesMonthlyRecord(t *testing.T) {
	now := time.Date(2026, 10, 1, 0, 0, 0, 0, time.UTC)
	monthly := map[string]any{
		"platform": "ios", "product_id": productIDPremiumMonthly,
		"original_transaction_id": "tx-monthly", "status": "active",
		"expires_at": now.Add(24 * time.Hour),
	}
	lifetime := subscriptionRecord("ios", productIDPremiumLifetime, "tx-lifetime")
	lifetime["status"] = "active"
	lifetime["expires_at"] = nil

	got, tier := combineLifetimeVerification(lifetime, "premium", monthly, now)
	if tier != "premium" || got["product_id"] != productIDPremiumMonthly ||
		got["original_transaction_id"] != "tx-monthly" ||
		got["lifetime_transaction_id"] != "tx-lifetime" {
		t.Fatalf("月額レコードと買い切り印を共存できていない: tier=%s sub=%v", tier, got)
	}

	// 同じ買い切りが返金されても、月額が有効なら月額premiumを維持する。
	revoked := subscriptionRecord("ios", productIDPremiumLifetime, "tx-lifetime")
	applyVerifiedLifetimeState(revoked, true, "free")
	got, tier = combineLifetimeVerification(revoked, "free", got, now)
	if tier != "premium" || got["lifetime"] != false ||
		got["product_id"] != productIDPremiumMonthly {
		t.Fatalf("返金時に有効な月額まで失っている: tier=%s sub=%v", tier, got)
	}

	got["expires_at"] = now.Add(-subscription.ExpiryDemotionMargin - time.Hour)
	got["lifetime"] = true
	got["lifetime_transaction_id"] = "tx-lifetime"
	got, tier = combineLifetimeVerification(revoked, "free", got, now)
	if tier != "free" || got["lifetime"] != false {
		t.Fatalf("他の有効な権利がないのに維持している: tier=%s sub=%v", tier, got)
	}
}

func TestInvalidLifetimeDoesNotRevokeMigration(t *testing.T) {
	now := time.Date(2026, 10, 1, 0, 0, 0, 0, time.UTC)
	current := map[string]any{
		"platform": "ios", "product_id": productIDPremiumMonthly,
		"status": "expired", "expires_at": now.Add(-60 * 24 * time.Hour),
		"lifetime": true, "lifetime_source": "monthly_migration",
	}
	revoked := subscriptionRecord("ios", productIDPremiumLifetime, "other-refunded-tx")
	applyVerifiedLifetimeState(revoked, true, "free")

	got, tier := combineLifetimeVerification(revoked, "free", current, now)
	if tier != "premium" || got["lifetime"] != true ||
		got["lifetime_source"] != "monthly_migration" {
		t.Fatalf("無関係な買い切り検証で無償移行を剥がしている: tier=%s sub=%v", tier, got)
	}
}

func TestReleaseLifetimeKeepsSeparateMonthlyEntitlement(t *testing.T) {
	now := time.Date(2026, 10, 1, 0, 0, 0, 0, time.UTC)
	data := map[string]any{
		"tier": "premium",
		"subscription": map[string]any{
			"platform": "ios", "status": "active",
			"expires_at": now.Add(24 * time.Hour),
			"lifetime":   true, "lifetime_transaction_id": "tx-lifetime",
		},
	}

	byPath := map[string]any{}
	for _, update := range lifetimeReleaseUpdates(data, now) {
		byPath[update.Path] = update.Value
	}
	if byPath["subscription.lifetime"] != false {
		t.Error("旧所有者の買い切り印を外していない")
	}
	if _, demoted := byPath["tier"]; demoted {
		t.Error("別購入の有効な月額まで free に落としている")
	}

	// 期限直後は更新の通知がまだ届いていないことがある。dailyBatch と同じ幅
	// （ExpiryDemotionMargin）だけ見逃す。
	data["subscription"].(map[string]any)["expires_at"] = now.Add(-time.Hour)
	byPath = map[string]any{}
	for _, update := range lifetimeReleaseUpdates(data, now) {
		byPath[update.Path] = update.Value
	}
	if _, demoted := byPath["tier"]; demoted {
		t.Error("更新通知の遅延を見逃す幅の中なのに free に落としている")
	}

	data["subscription"].(map[string]any)["expires_at"] =
		now.Add(-subscription.ExpiryDemotionMargin - time.Hour)
	byPath = map[string]any{}
	for _, update := range lifetimeReleaseUpdates(data, now) {
		byPath[update.Path] = update.Value
	}
	if byPath["tier"] != "free" {
		t.Error("他に有効な権利がない旧所有者を free に落としていない")
	}
}

// TestLifetimeRefundClearsMark は、買い切りの返金・取消で印そのものを外すこと。
// 印が残ると、そのあと月額を買った人が解約後も premium のままになる。
// 月額の返金では外さない（買い切りの権利を巻き添えにしない）。
func TestLifetimeRefundClearsMark(t *testing.T) {
	free := appStoreDecision{Tier: "free", Status: "expired", Handled: true}

	// 買い切り購入者の doc（無償移行ではない）。
	purchasedData := map[string]any{
		"tier": "premium",
		"subscription": map[string]any{
			"platform": "ios", "product_id": "premium_lifetime",
			"status": "active", "lifetime": true,
			"lifetime_transaction_id": "tx-lifetime",
		},
	}

	clears := func(productID, notificationType string) bool {
		n := &appstore.Notification{NotificationType: notificationType}
		n.TransactionInfo.ProductID = productID
		d, revoked := keepPremiumForLifetime(free, purchasedData, n)
		for _, u := range appStoreUpdates(n, d, "premium", "uid", revoked) {
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

// TestVerifiedTierKeepsLifetime は、買い切り所有者を月額の検証で free に
// 落とさないこと。復元では買い切りと過去の月額が同時に流れ、検証の順序は
// 決まらない。月額が後着したときに落ちると、昇格経路が他に無いので戻らない。
func TestVerifiedTierKeepsLifetime(t *testing.T) {
	lifetimeSub := map[string]any{"platform": "ios", "lifetime": true}
	plainSub := map[string]any{"platform": "ios", "product_id": "premium_monthly"}

	if got := verifiedTier("free", false, lifetimeSub); got != "premium" {
		t.Errorf("月額（期限切れ）の検証で買い切り所有者を落としている: %s", got)
	}
	if got := verifiedTier("free", true, lifetimeSub); got != "free" {
		t.Errorf("買い切りそのものが無効なのに premium を残している: %s", got)
	}
	if got := verifiedTier("free", false, plainSub); got != "free" {
		t.Errorf("印が無いのに premium を残している: %s", got)
	}
	if got := verifiedTier("premium", false, plainSub); got != "premium" {
		t.Errorf("有効な月額を落としている: %s", got)
	}
}

// TestLifetimeTransactionIDIsKept は、買い切りの検証で返金通知用のキーを
// 別フィールドに残すこと。original_transaction_id は月額の検証で上書きされる。
func TestLifetimeTransactionIDIsKept(t *testing.T) {
	lifetime := subscriptionRecord("ios", productIDPremiumLifetime, "tx-lifetime")
	if lifetime["lifetime_transaction_id"] != "tx-lifetime" {
		t.Errorf("買い切りの取引IDを残していない: %v", lifetime["lifetime_transaction_id"])
	}

	monthly := subscriptionRecord("ios", productIDPremiumMonthly, "tx-monthly")
	if _, ok := monthly["lifetime_transaction_id"]; ok {
		t.Error("月額の検証が lifetime_transaction_id を書いている")
	}
}

// TestMigratedRefundClearsMark は、無償移行者の月額返金で tier だけでなく
// 印も外すこと。印が残ると、月額を買い直して解約するだけで premium が
// 永久に戻る（返金で抜け道を塞いだつもりが1手で復活する）。
func TestMigratedRefundClearsMark(t *testing.T) {
	free := appStoreDecision{Tier: "free", Status: "expired", Handled: true}

	for _, notificationType := range []string{"REFUND", "REVOKE"} {
		n := &appstore.Notification{NotificationType: notificationType}
		n.TransactionInfo.ProductID = productIDPremiumMonthly

		d, revoked := keepPremiumForLifetime(free, lifetimeUser("active"), n)
		byPath := map[string]any{}
		for _, u := range appStoreUpdates(n, d, "premium", "uid", revoked) {
			byPath[u.Path] = u.Value
		}

		if byPath["tier"] != "free" {
			t.Errorf("%s で移行者を落としていない", notificationType)
		}
		if byPath["subscription.lifetime"] != false {
			t.Errorf("%s で移行者の印を外していない: %v",
				notificationType, byPath["subscription.lifetime"])
		}
		if _, ok := byPath["subscription.lifetime_source"]; !ok {
			t.Errorf("%s で lifetime_source を消していない", notificationType)
		}
	}
}

// TestLifetimeBackfillPayload は、返金通知用のキーを持たない買い切り購入者に
// だけ埋め戻しが走ること。
func TestLifetimeBackfillPayload(t *testing.T) {
	now := time.Date(2026, 10, 1, 0, 0, 0, 0, time.UTC)
	purchased := func() map[string]any {
		return map[string]any{
			"tier": "premium",
			"subscription": map[string]any{
				"platform": "ios", "product_id": "premium_lifetime",
				"lifetime": true, "original_transaction_id": "tx-lifetime",
			},
		}
	}

	got := lifetimeBackfillPayload(purchased())
	if got == nil || got["lifetime_transaction_id"] != "tx-lifetime" {
		t.Errorf("買い切り購入者を埋め戻していない: %v", got)
	}

	// 既に持っている人には書かない。
	withKey := purchased()
	withKey["subscription"].(map[string]any)["lifetime_transaction_id"] = "tx-lifetime"
	if got := lifetimeBackfillPayload(withKey); got != nil {
		t.Errorf("埋め戻し済みの doc を書き直している: %v", got)
	}

	// 無償移行者は買い切りの購入自体が無い（product_id は月額のまま）。
	if got := lifetimeBackfillPayload(lifetimeUser("active")); got != nil {
		t.Errorf("無償移行者を埋め戻している: %v", got)
	}

	// 移行後にsubscriptionが更新されていなければ、移行元IDを安全に補える。
	migrated := lifetimeUser("active")
	migratedSub := migrated["subscription"].(map[string]any)
	migratedSub["original_transaction_id"] = "tx-migration-source"
	migratedSub["lifetime_migrated_at"] = now
	migratedSub["updated_at"] = now
	if got := lifetimeBackfillPayload(migrated); got == nil ||
		got["lifetime_source_transaction_id"] != "tx-migration-source" {
		t.Errorf("安全に特定できる移行元IDを補っていない: %v", got)
	}
	// 移行後に別の検証が走ったdocは、現在のIDを移行元だと推測しない。
	migratedSub["updated_at"] = now.Add(time.Hour)
	if got := lifetimeBackfillPayload(migrated); got != nil {
		t.Errorf("更新後の別取引IDを移行元として補っている: %v", got)
	}

	// free と、印の無いユーザーは対象外。
	freeUser := purchased()
	freeUser["tier"] = "free"
	if got := lifetimeBackfillPayload(freeUser); got != nil {
		t.Errorf("free ユーザーを埋め戻している: %v", got)
	}
	plain := map[string]any{
		"tier": "premium",
		"subscription": map[string]any{
			"platform": "ios", "product_id": "premium_monthly",
			"original_transaction_id": "tx-monthly",
		},
	}
	if got := lifetimeBackfillPayload(plain); got != nil {
		t.Errorf("買い切りでない doc を埋め戻している: %v", got)
	}
}

// TestBackfillAndDemoteShareSubscriptionPayload は、日次リセットが
// subscription へ書くぶんを取りこぼさないこと（片方の代入がもう片方を
// 丸ごと捨てない）。
func TestBackfillAndDemoteShareSubscriptionPayload(t *testing.T) {
	now := time.Date(2026, 10, 1, 0, 0, 0, 0, time.UTC)
	lapsed := map[string]any{
		"tier": "premium",
		"subscription": map[string]any{
			"platform": "ios", "product_id": "premium_monthly",
			"status": "active", "expires_at": now.Add(-72 * time.Hour),
		},
	}

	got := quotaResetPayload("lapsed", lapsed, now)
	sub, _ := got["subscription"].(map[string]any)
	if got["tier"] != "free" || sub["status"] != "expired" {
		t.Errorf("期限切れを落としていない: %v", got)
	}

	// 埋め戻しだけが走るケースでは tier に触らない。
	backfillOnly := map[string]any{
		"tier": "premium",
		"subscription": map[string]any{
			"platform": "ios", "product_id": "premium_lifetime",
			"lifetime": true, "original_transaction_id": "tx-lifetime",
		},
	}
	got = quotaResetPayload("backfill", backfillOnly, now)
	sub, _ = got["subscription"].(map[string]any)
	if _, demoted := got["tier"]; demoted {
		t.Error("買い切り購入者を落としている")
	}
	if sub["lifetime_transaction_id"] != "tx-lifetime" {
		t.Errorf("埋め戻しが payload に乗っていない: %v", sub)
	}
}
