package appstore

import "testing"

func TestValidateNotificationIdentity(t *testing.T) {
	t.Setenv("APP_STORE_BUNDLE_ID", "com.example.app")
	t.Setenv("APP_STORE_ENVIRONMENT", "production")
	t.Setenv("APP_STORE_APP_APPLE_ID", "12345")

	// APP_STORE_ENVIRONMENT=production でも Sandbox 通知は受け付ける
	// （審査・TestFlight の購入は prod の関数に Sandbox で届く）。
	valid := []Notification{
		{
			BundleID: "com.example.app", Environment: "Production", AppAppleID: 12345,
			TransactionInfo: TransactionInfo{Environment: "Production"},
		},
		{
			BundleID: "com.example.app", Environment: "Sandbox", AppAppleID: 12345,
			TransactionInfo: TransactionInfo{Environment: "Sandbox"},
		},
	}
	for _, tc := range valid {
		if err := validateNotificationIdentity(&tc); err != nil {
			t.Fatalf("valid notification rejected: %#v: %v", tc, err)
		}
	}

	cases := []Notification{
		{BundleID: "other", Environment: "Production", AppAppleID: 12345},
		{BundleID: "com.example.app", Environment: "", AppAppleID: 12345},
		{
			BundleID: "com.example.app", Environment: "Production", AppAppleID: 12345,
			TransactionInfo: TransactionInfo{Environment: "Sandbox"},
		},
		{BundleID: "com.example.app", Environment: "Production", AppAppleID: 999},
	}
	for _, tc := range cases {
		if err := validateNotificationIdentity(&tc); err == nil {
			t.Errorf("mismatched notification accepted: %#v", tc)
		}
	}
}
