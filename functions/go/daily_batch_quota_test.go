package function

import (
	"testing"
	"time"

	"github.com/mnbst/thai-memo/functions/go/internal/quota"
)

// TestQuotaResetKeepsLifetimePremium は買い切り購入を日次リセットで落とさないこと。
//
// 買い切りは expires_at を持たない。ストア購入で expires_at が無いものは
// 「期限判定が効かない premium」として free に落とす扱いなので、その分岐に
// 巻き込まれないことをここで押さえる（落ちると返金もしていない購入者が
// 翌日 free になる）。
func TestQuotaResetKeepsLifetimePremium(t *testing.T) {
	now := time.Date(2026, 9, 12, 15, 30, 0, 0, time.UTC)

	lifetime := map[string]any{
		"tier": "premium",
		"subscription": map[string]any{
			"platform":   "ios",
			"product_id": "premium_lifetime",
			"status":     "active",
			"lifetime":   true,
		},
	}
	got := quotaResetPayload("lifetime", lifetime, now)
	if got["remaining_sentences"] != quota.PremiumDailySentences {
		t.Errorf("買い切りが premium 扱いになっていない: %v", got["remaining_sentences"])
	}

	// 目印が無いストア購入は従来どおり落とす（この分岐を緩めていないこと）。
	noMark := map[string]any{
		"tier": "premium",
		"subscription": map[string]any{
			"platform":   "ios",
			"product_id": "premium_monthly",
			"status":     "active",
		},
	}
	got = quotaResetPayload("nomark", noMark, now)
	if got["remaining_sentences"] != quota.FreeDailySentences {
		t.Errorf("expires_at の無い月額が premium のまま残っている: %v",
			got["remaining_sentences"])
	}
}
