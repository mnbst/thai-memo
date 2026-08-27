package playbilling

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"os"
	"strings"
	"testing"
)

type playGoldenCase struct {
	Name         string          `json:"name"`
	Response     json.RawMessage `json:"response"`
	RequestedURL string          `json:"requested_url"`
	Valid        bool            `json:"valid"`
	ExpiresAt    *int64          `json:"expires_at"`
	AutoRenewing bool            `json:"auto_renewing"`
	Status       string          `json:"status"`
}

type replayTransport struct {
	body      string
	requested string
}

func (r *replayTransport) RoundTrip(req *http.Request) (*http.Response, error) {
	r.requested = req.URL.String()
	return &http.Response{
		StatusCode: http.StatusOK,
		Body:       io.NopCloser(strings.NewReader(r.body)),
		Header:     http.Header{},
		Request:    req,
	}, nil
}

// TestVerifyPurchaseGolden は JS 実装（playBilling.ts:verifyPlayPurchase）と
// 同じ API レスポンスに対して同じ結論を出すことを確かめる。
//
// golden は本物の JS 実装に google-auth-library をスタブして通したもの
// （scripts/genPlayGolden.ts）。subscriptionState の全値と、期限や
// autoRenewingPlan が欠けた場合を含む。
func TestVerifyPurchaseGolden(t *testing.T) {
	raw, err := os.ReadFile("../../../javascript/scripts/play_golden.json")
	if err != nil {
		t.Fatalf("golden の読み込みに失敗: %v", err)
	}
	var cases []playGoldenCase
	if err := json.Unmarshal(raw, &cases); err != nil {
		t.Fatal(err)
	}
	if len(cases) == 0 {
		t.Fatal("golden が空")
	}

	seenStatus := map[string]int{}
	for _, c := range cases {
		t.Run(c.Name, func(t *testing.T) {
			transport := &replayTransport{body: string(c.Response)}
			client := &Client{HTTP: &http.Client{Transport: transport}}

			got, err := client.VerifyPurchase(context.Background(),
				"com.thaimemo.thai_memo", "premium_monthly", "token-abc123")
			if err != nil {
				t.Fatalf("JS は成功したのに Go は失敗した: %v", err)
			}
			seenStatus[string(got.Status)]++

			if got.Valid != c.Valid {
				t.Errorf("valid: want %v, got %v", c.Valid, got.Valid)
			}
			if string(got.Status) != c.Status {
				t.Errorf("status: want %s, got %s", c.Status, got.Status)
			}
			if got.AutoRenewing != c.AutoRenewing {
				t.Errorf("autoRenewing: want %v, got %v", c.AutoRenewing, got.AutoRenewing)
			}
			switch {
			case c.ExpiresAt == nil && got.ExpiresAt != nil:
				t.Errorf("expiresAt: JS は null、Go は %v", got.ExpiresAt)
			case c.ExpiresAt != nil && got.ExpiresAt == nil:
				t.Errorf("expiresAt: JS は %d、Go は null", *c.ExpiresAt)
			case c.ExpiresAt != nil && got.ExpiresAt.UnixMilli() != *c.ExpiresAt:
				t.Errorf("expiresAt: want %d, got %d",
					*c.ExpiresAt, got.ExpiresAt.UnixMilli())
			}
			if transport.requested != c.RequestedURL {
				t.Errorf("URL\n  JS = %s\n  Go = %s", c.RequestedURL, transport.requested)
			}
		})
	}

	t.Logf("%d ケース一致 %v", len(cases), seenStatus)
	for _, want := range []string{"active", "canceled", "expired", "grace_period"} {
		if seenStatus[want] == 0 {
			t.Errorf("status=%s のケースが無い。golden が退化している", want)
		}
	}
}
