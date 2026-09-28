package appstore

import "testing"

func TestResolveUpgraded(t *testing.T) {
	monthly := &TransactionInfo{OriginalTransactionID: "o1", TransactionID: "t1", ProductID: "premium_monthly"}
	upgraded := &TransactionInfo{OriginalTransactionID: "o1", TransactionID: "t1", ProductID: "premium_monthly", IsUpgraded: true}
	yearly := &TransactionInfo{OriginalTransactionID: "o1", TransactionID: "t2", ProductID: "premium_annual"}

	if got, err := resolveUpgraded(monthly, yearly); err != nil || got != monthly {
		t.Errorf("切り替えていない取引はそのまま使う: got=%v err=%v", got, err)
	}
	if got, err := resolveUpgraded(upgraded, yearly); err != nil || got != yearly {
		t.Errorf("切り替えた取引は最新の取引で判定する: got=%v err=%v", got, err)
	}
	if _, err := resolveUpgraded(upgraded, nil); err == nil {
		t.Error("最新が取れなければエラーにする（free を書かない）")
	}
	if _, err := resolveUpgraded(upgraded, upgraded); err == nil {
		t.Error("最新が古い取引のままならエラーにする")
	}
	other := &TransactionInfo{OriginalTransactionID: "o2", TransactionID: "t3", ProductID: "premium_annual"}
	if _, err := resolveUpgraded(upgraded, other); err == nil {
		t.Error("別の購読の取引には乗り換えない")
	}
}
