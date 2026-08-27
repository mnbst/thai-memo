package appstore

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/mnbst/thai-memo/functions/go/internal/applejws"
)

type appstoreGolden struct {
	NowMS           int64  `json:"now_ms"`
	RootFingerprint string `json:"root_fingerprint"`
	PrivateKeyPEM   string `json:"private_key_pem"`
	Cases           []struct {
		Name          string  `json:"name"`
		Env           *string `json:"env"`
		TransactionID string  `json:"transaction_id"`
		Routes        []struct {
			Match    string `json:"match"`
			Response struct {
				Status int    `json:"status"`
				Body   string `json:"body"`
			} `json:"response"`
		} `json:"routes"`
		RequestedURLs []string `json:"requested_urls"`
		OK            bool     `json:"ok"`
		Error         *string  `json:"error"`
		Result        *struct {
			Valid                 bool   `json:"valid"`
			OriginalTransactionID string `json:"original_transaction_id"`
			ExpiresAt             *int64 `json:"expires_at"`
			AutoRenewing          bool   `json:"auto_renewing"`
			Status                string `json:"status"`
		} `json:"result"`
	} `json:"cases"`
}

// stubTransport は golden のルート定義どおりに応答し、叩かれた URL を記録する。
type stubTransport struct {
	routes []struct {
		match  string
		status int
		body   string
	}
	requested []string
}

func (s *stubTransport) RoundTrip(req *http.Request) (*http.Response, error) {
	url := req.URL.String()
	s.requested = append(s.requested, url)
	for _, r := range s.routes {
		if strings.Contains(url, r.match) {
			return &http.Response{
				StatusCode: r.status,
				Body:       io.NopCloser(strings.NewReader(r.body)),
				Header:     http.Header{},
				Request:    req,
			}, nil
		}
	}
	return nil, &noRouteError{url: url}
}

type noRouteError struct{ url string }

func (e *noRouteError) Error() string { return "no stub route for " + e.url }

// TestVerifyPurchaseGolden は JS 実装（appStoreServer.ts:verifyAppStorePurchase）と
// 同じ HTTP レスポンスに対して同じ結論を出すことを確かめる。
//
// golden は本物の JS 実装に fetch と Secret Manager をスタブして通したもの
// （scripts/genAppStoreGolden.ts）。ステータス判定だけでなく、叩いた URL の
// 順序（本番→サンドボックスのフォールバック）まで比べる。
func TestVerifyPurchaseGolden(t *testing.T) {
	raw, err := os.ReadFile("../../../javascript/scripts/appstore_golden.json")
	if err != nil {
		t.Fatalf("golden の読み込みに失敗: %v", err)
	}
	var golden appstoreGolden
	if err := json.Unmarshal(raw, &golden); err != nil {
		t.Fatal(err)
	}
	if len(golden.Cases) == 0 {
		t.Fatal("golden が空")
	}

	// Secret Manager を叩かせず、JS 側と同じ鍵・ID を使わせる。
	t.Setenv("APPSTORE_CONNECT_KEY", golden.PrivateKeyPEM)
	t.Setenv("APPSTORE_KEY_ID", "TESTKEYID1")
	t.Setenv("APPSTORE_ISSUER_ID", "11111111-2222-3333-4444-555555555555")

	now := time.UnixMilli(golden.NowMS)

	var okCount, ngCount int
	for _, c := range golden.Cases {
		t.Run(c.Name, func(t *testing.T) {
			if c.Env != nil {
				t.Setenv("APP_STORE_ENVIRONMENT", *c.Env)
			} else {
				t.Setenv("APP_STORE_ENVIRONMENT", "")
			}

			transport := &stubTransport{}
			for _, r := range c.Routes {
				transport.routes = append(transport.routes, struct {
					match  string
					status int
					body   string
				}{r.Match, r.Response.Status, r.Response.Body})
			}

			client := &Client{
				HTTP:     &http.Client{Transport: transport},
				Verifier: &applejws.Verifier{RootFingerprint: golden.RootFingerprint},
				Now:      func() time.Time { return now },
			}

			result, err := client.VerifyPurchase(context.Background(), c.TransactionID)

			if !c.OK {
				ngCount++
				if err == nil {
					t.Fatalf("JS は失敗した（%s）のに Go は成功した", *c.Error)
				}
				if err.Error() != *c.Error {
					t.Errorf("エラー文言が違う\n  JS = %s\n  Go = %s", *c.Error, err)
				}
			} else {
				okCount++
				if err != nil {
					t.Fatalf("JS は成功したのに Go は失敗した: %v", err)
				}
				want := c.Result
				if result.Valid != want.Valid {
					t.Errorf("valid: want %v, got %v", want.Valid, result.Valid)
				}
				if result.OriginalTransactionID != want.OriginalTransactionID {
					t.Errorf("originalTransactionId: want %s, got %s",
						want.OriginalTransactionID, result.OriginalTransactionID)
				}
				if string(result.Status) != want.Status {
					t.Errorf("status: want %s, got %s", want.Status, result.Status)
				}
				if result.AutoRenewing != want.AutoRenewing {
					t.Errorf("autoRenewing: want %v, got %v",
						want.AutoRenewing, result.AutoRenewing)
				}
				switch {
				case want.ExpiresAt == nil && result.ExpiresAt != nil:
					t.Errorf("expiresAt: JS は null、Go は %d", *result.ExpiresAt)
				case want.ExpiresAt != nil && result.ExpiresAt == nil:
					t.Errorf("expiresAt: JS は %d、Go は null", *want.ExpiresAt)
				case want.ExpiresAt != nil && *want.ExpiresAt != *result.ExpiresAt:
					t.Errorf("expiresAt: want %d, got %d",
						*want.ExpiresAt, *result.ExpiresAt)
				}
			}

			// 叩いた URL が同じであること（環境の選択とフォールバックの確認）
			if len(transport.requested) != len(c.RequestedURLs) {
				t.Fatalf("叩いた URL の数が違う\n  JS = %v\n  Go = %v",
					c.RequestedURLs, transport.requested)
			}
			for i, want := range c.RequestedURLs {
				if transport.requested[i] != want {
					t.Errorf("URL[%d]\n  JS = %s\n  Go = %s",
						i, want, transport.requested[i])
				}
			}
		})
	}

	t.Logf("%d ケース一致（成功 %d / 失敗 %d）", len(golden.Cases), okCount, ngCount)
	if okCount == 0 || ngCount == 0 {
		t.Error("成功ケースか失敗ケースのどちらかが無い。golden が退化している")
	}
}
