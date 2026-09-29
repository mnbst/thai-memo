package function

import (
	"testing"

	"github.com/mnbst/thai-memo/functions/go/internal/appstore"
)

func TestDecideRenewalPrefChange(t *testing.T) {
	upgrade := &appstore.Notification{
		NotificationType: "DID_CHANGE_RENEWAL_PREF",
		Subtype:          "UPGRADE",
		TransactionInfo:  appstore.TransactionInfo{ProductID: "premium_annual"},
	}
	d := decideAppStoreNotification(upgrade)
	if !d.Handled || d.Tier != "premium" || d.Status != "active" {
		t.Errorf("UPGRADE は即時に切り替わるので premium / active: %+v", d)
	}
	updates := updatesToMap(appStoreUpdates(upgrade, d, "premium", "uid", false))
	if updates["subscription.product_id"] != "premium_annual" {
		t.Errorf("切り替え先の商品を記録する: %v", updates["subscription.product_id"])
	}

	downgrade := &appstore.Notification{
		NotificationType: "DID_CHANGE_RENEWAL_PREF",
		Subtype:          "DOWNGRADE",
		TransactionInfo:  appstore.TransactionInfo{ProductID: "premium_annual"},
	}
	if decideAppStoreNotification(downgrade).Handled {
		t.Error("DOWNGRADE は次回更新から効くので、ここでは何もしない")
	}
}
