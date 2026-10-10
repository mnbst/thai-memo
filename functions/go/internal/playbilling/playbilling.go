// Package playbilling は Google Play Developer API v3（Subscriptions v2）の
// クライアント。functions/javascript/src/services/playBilling.ts の移植。
//
// 認証は ADC（Application Default Credentials）。Cloud Functions 上では
// プロジェクトのサービスアカウントが自動的に使われる。Google Play Console で
// 該当サービスアカウントに「財務データの閲覧」権限が必要。
package playbilling

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net/http"
	"net/url"
	"time"

	"golang.org/x/oauth2/google"
)

const (
	playHTTPTimeout     = 30 * time.Second
	playMaxResponseSize = 4 << 20
)

// apiBase は Google Play Developer API v3 のベース URL。
const apiBase = "https://androidpublisher.googleapis.com/androidpublisher/v3"

// scope は API アクセスに必要な OAuth2 スコープ。
const scope = "https://www.googleapis.com/auth/androidpublisher"

// Status はアプリ内で統一的に扱うサブスクリプションの状態
// （Google Play の詳細な状態をマッピングしたもの）。
type Status string

const (
	StatusActive      Status = "active"
	StatusCanceled    Status = "canceled"
	StatusExpired     Status = "expired"
	StatusGracePeriod Status = "grace_period"
)

// VerificationResult は Play 購入検証の結果。
type VerificationResult struct {
	Valid        bool
	ProductID    string
	ExpiresAt    *time.Time
	AutoRenewing bool
	Status       Status
	// LinkedPurchaseToken はプラン切り替え前の購入トークン（切り替えでなければ空）。
	LinkedPurchaseToken string
}

// subscriptionPurchaseV2 は Subscriptions v2 API のレスポンス。
//
// SubscriptionState の値:
//   - ACTIVE: 有効（自動更新される）
//   - CANCELED: キャンセル済み（現在の期間終了まで有効）
//   - IN_GRACE_PERIOD: 支払い猶予期間（決済失敗後の一定期間、まだサービス提供する）
//   - ON_HOLD: 保留中（決済失敗が続きサービス停止だが、回復の余地あり）
//   - PAUSED: 一時停止（ユーザーが自ら一時停止した）
//   - EXPIRED: 期限切れ（完全に終了）
type subscriptionPurchaseV2 struct {
	Kind      string `json:"kind"`
	LineItems []struct {
		ProductID        string `json:"productId"`
		ExpiryTime       string `json:"expiryTime"`
		AutoRenewingPlan *struct {
			AutoRenewEnabled bool `json:"autoRenewEnabled"`
		} `json:"autoRenewingPlan"`
	} `json:"lineItems"`
	SubscriptionState   string `json:"subscriptionState"`
	LinkedPurchaseToken string `json:"linkedPurchaseToken"`
}

// Client は Play Developer API を叩く。
type Client struct {
	// HTTP は差し替え用。nil なら ADC で認証したクライアントを作る。
	HTTP *http.Client
}

// Default は本番設定のクライアント。
var Default = &Client{}

func (c *Client) httpClient(ctx context.Context) (*http.Client, error) {
	if c.HTTP != nil {
		return c.HTTP, nil
	}
	client, err := google.DefaultClient(ctx, scope)
	if err != nil {
		return nil, err
	}
	copy := *client
	copy.Timeout = playHTTPTimeout
	return &copy, nil
}

// VerifyPurchase は purchaseToken でサブスクリプション状態を問い合わせ、
// アプリ内で統一的に扱えるステータスにマッピングして返す。
func (c *Client) VerifyPurchase(
	ctx context.Context, packageName, subscriptionID, purchaseToken string,
) (*VerificationResult, error) {
	var data subscriptionPurchaseV2
	if err := c.get(ctx, fmt.Sprintf("%s/applications/%s/purchases/subscriptionsv2/tokens/%s",
		apiBase, url.PathEscape(packageName), url.PathEscape(purchaseToken)), &data); err != nil {
		return nil, err
	}
	return mapResult(packageName, subscriptionID, &data)
}

// productPurchase は purchases.products.get（一時購入）のレスポンス。
//
// PurchaseState: 0=購入済み, 1=取消（返金含む）, 2=保留中（コンビニ払い等の未払い）
type productPurchase struct {
	PurchaseState *int   `json:"purchaseState"`
	ProductID     string `json:"productId"`
	OrderID       string `json:"orderId"`
}

// ErrPurchasePending は支払いが済んでいない一時購入。権利は付けずに
// 支払い完了後の再配信（purchaseStream）を待つ。
var ErrPurchasePending = errors.New("Play one-time purchase is pending")

// VerifyOneTimePurchase は買い切り（一時購入）の purchaseToken を検証する。
//
// 買い切りは期限を持たないので ExpiresAt は常に nil。購入済みなら active、
// 取消・返金済みなら expired を返す。
func (c *Client) VerifyOneTimePurchase(
	ctx context.Context, packageName, productID, purchaseToken string,
) (*VerificationResult, error) {
	var data productPurchase
	if err := c.get(ctx, fmt.Sprintf("%s/applications/%s/purchases/products/%s/tokens/%s",
		apiBase, url.PathEscape(packageName), url.PathEscape(productID),
		url.PathEscape(purchaseToken)), &data); err != nil {
		return nil, err
	}
	return mapOneTimeResult(productID, &data)
}

func mapOneTimeResult(productID string, data *productPurchase) (*VerificationResult, error) {
	// productId はレスポンスに含まれないことがある。含まれるなら一致を確かめる。
	if data.ProductID != "" && data.ProductID != productID {
		return nil, fmt.Errorf("Play API response is for product %q, not %q",
			data.ProductID, productID)
	}
	if data.PurchaseState == nil {
		return nil, errors.New("Play API response has no purchaseState")
	}
	status := StatusExpired
	switch *data.PurchaseState {
	case 0:
		status = StatusActive
	case 2:
		return nil, ErrPurchasePending
	}
	return &VerificationResult{
		Valid: true, ProductID: productID, Status: status,
	}, nil
}

// get は Play Developer API へ GET し、JSON を out へ読む。
func (c *Client) get(ctx context.Context, endpoint string, out any) error {
	httpClient, err := c.httpClient(ctx)
	if err != nil {
		return fmt.Errorf("Play API の認証に失敗: %w", err)
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, endpoint, nil)
	if err != nil {
		return err
	}

	res, err := httpClient.Do(req)
	if err != nil {
		return err
	}
	defer res.Body.Close()

	body, err := io.ReadAll(io.LimitReader(res.Body, playMaxResponseSize))
	if err != nil {
		return err
	}
	if res.StatusCode < 200 || res.StatusCode >= 300 {
		return fmt.Errorf("Play API error: %d %s", res.StatusCode, string(body))
	}

	if err := json.Unmarshal(body, out); err != nil {
		return fmt.Errorf("Play API のレスポンスをパースできない: %w", err)
	}
	return nil
}

// mapResult はレスポンスをアプリ内の4種のステータスへ落とす。
//
// CANCELED: ユーザーがキャンセルしたが現在の期間は有効
// （Firestore では tier='premium' を維持）
// IN_GRACE_PERIOD / ON_HOLD: 決済失敗だが回復の余地あり → grace_period として premium 維持
// その他（EXPIRED, PAUSED 等）: サービス提供を停止 → expired として tier='free' に
func mapResult(
	packageName, subscriptionID string, data *subscriptionPurchaseV2,
) (*VerificationResult, error) {
	// purchaseToken はプラン変更時に複数 lineItems を返すことがある。
	// クライアント申告の商品ではなく、Play が返した同一商品だけを採用する。
	var expiresAt *time.Time
	autoRenewing := false
	foundProduct := false
	for _, item := range data.LineItems {
		if item.ProductID != subscriptionID {
			continue
		}
		foundProduct = true
		if item.ExpiryTime != "" {
			t, err := parseExpiryTime(item.ExpiryTime)
			if err != nil {
				return nil, err
			}
			expiresAt = t
		}
		if item.AutoRenewingPlan != nil {
			autoRenewing = item.AutoRenewingPlan.AutoRenewEnabled
		}
		break
	}
	if !foundProduct {
		if len(data.LineItems) == 0 {
			// 商品明細が無いレスポンスは entitlement を付与せず expired 扱い。
			// これは従来の安全側フォールバックと同じで、商品不一致とは区別する。
			log.Printf("Subscription has no lineItems; treating as expired (packageName=%s, subscriptionId=%s, subscriptionState=%s)",
				packageName, subscriptionID, data.SubscriptionState)
			return &VerificationResult{
				Valid: true, ProductID: subscriptionID, ExpiresAt: nil,
				AutoRenewing: false, Status: StatusExpired,
			}, nil
		}
		return nil, fmt.Errorf("Play API response does not contain subscriptionId %q", subscriptionID)
	}

	if expiresAt == nil {
		// expiryTime が無いと期限判定が働かず永久 premium になるため expired 扱い
		log.Printf("Subscription has no expiryTime; treating as expired (packageName=%s, subscriptionId=%s, subscriptionState=%s)",
			packageName, subscriptionID, data.SubscriptionState)
		return &VerificationResult{
			Valid: true, ProductID: subscriptionID, ExpiresAt: nil,
			AutoRenewing: autoRenewing, Status: StatusExpired,
		}, nil
	}

	var status Status
	switch data.SubscriptionState {
	case "SUBSCRIPTION_STATE_ACTIVE":
		status = StatusActive
	case "SUBSCRIPTION_STATE_CANCELED":
		status = StatusCanceled
	case "SUBSCRIPTION_STATE_IN_GRACE_PERIOD", "SUBSCRIPTION_STATE_ON_HOLD":
		status = StatusGracePeriod
	default:
		status = StatusExpired
	}

	return &VerificationResult{
		Valid: true, ProductID: subscriptionID, ExpiresAt: expiresAt,
		AutoRenewing: autoRenewing, Status: status,
		LinkedPurchaseToken: data.LinkedPurchaseToken,
	}, nil
}

// parseExpiryTime は Play の RFC 3339 タイムスタンプを読む。
// JS の new Date(string) 相当。
func parseExpiryTime(s string) (*time.Time, error) {
	t, err := time.Parse(time.RFC3339Nano, s)
	if err != nil {
		return nil, fmt.Errorf("expiryTime をパースできない (%q): %w", s, err)
	}
	return &t, nil
}
