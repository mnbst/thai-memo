package playbilling

import (
	"context"
	"errors"
	"net/http"
	"strings"
	"testing"
)

func TestVerifyOneTimePurchase(t *testing.T) {
	cases := []struct {
		name    string
		body    string
		status  Status
		wantErr error
	}{
		{"購入済み", `{"purchaseState":0,"productId":"premium_lifetime"}`, StatusActive, nil},
		{"productId なし", `{"purchaseState":0}`, StatusActive, nil},
		{"取消", `{"purchaseState":1}`, StatusExpired, nil},
		{"保留中", `{"purchaseState":2}`, "", ErrPurchasePending},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			transport := &replayTransport{body: c.body}
			client := &Client{HTTP: &http.Client{Transport: transport}}
			res, err := client.VerifyOneTimePurchase(
				context.Background(), "com.example", "premium_lifetime", "tok")
			if !strings.HasSuffix(transport.requested,
				"/applications/com.example/purchases/products/premium_lifetime/tokens/tok") {
				t.Fatalf("URL = %s", transport.requested)
			}
			if c.wantErr != nil {
				if !errors.Is(err, c.wantErr) {
					t.Fatalf("err = %v, want %v", err, c.wantErr)
				}
				return
			}
			if err != nil {
				t.Fatal(err)
			}
			if res.Status != c.status || res.ExpiresAt != nil {
				t.Fatalf("got %+v", res)
			}
		})
	}
}

func TestVerifyOneTimePurchaseRejectsOtherProduct(t *testing.T) {
	client := &Client{HTTP: &http.Client{Transport: &replayTransport{
		body: `{"purchaseState":0,"productId":"premium_monthly"}`}}}
	if _, err := client.VerifyOneTimePurchase(
		context.Background(), "p", "premium_lifetime", "tok"); err == nil {
		t.Fatal("別商品の購入を通してはいけない")
	}
}

func TestVerifyPurchaseKeepsLinkedPurchaseToken(t *testing.T) {
	client := &Client{HTTP: &http.Client{Transport: &replayTransport{body: `{
		"subscriptionState": "SUBSCRIPTION_STATE_ACTIVE",
		"linkedPurchaseToken": "old-token",
		"lineItems": [{"productId": "premium_annual", "expiryTime": "2027-01-01T00:00:00Z"}]
	}`}}}
	res, err := client.VerifyPurchase(context.Background(), "p", "premium_annual", "new-token")
	if err != nil {
		t.Fatal(err)
	}
	if res.LinkedPurchaseToken != "old-token" {
		t.Fatalf("LinkedPurchaseToken = %q", res.LinkedPurchaseToken)
	}
}
