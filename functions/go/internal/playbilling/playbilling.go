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
	"fmt"
	"io"
	"log"
	"net/http"
	"time"

	"golang.org/x/oauth2/google"
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
	ExpiresAt    *time.Time
	AutoRenewing bool
	Status       Status
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
	SubscriptionState string `json:"subscriptionState"`
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
	return google.DefaultClient(ctx, scope)
}

// VerifyPurchase は purchaseToken でサブスクリプション状態を問い合わせ、
// アプリ内で統一的に扱えるステータスにマッピングして返す。
func (c *Client) VerifyPurchase(
	ctx context.Context, packageName, subscriptionID, purchaseToken string,
) (*VerificationResult, error) {
	httpClient, err := c.httpClient(ctx)
	if err != nil {
		return nil, fmt.Errorf("Play API の認証に失敗: %w", err)
	}

	url := fmt.Sprintf("%s/applications/%s/purchases/subscriptionsv2/tokens/%s",
		apiBase, packageName, purchaseToken)
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return nil, err
	}

	res, err := httpClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer res.Body.Close()

	body, err := io.ReadAll(res.Body)
	if err != nil {
		return nil, err
	}
	if res.StatusCode < 200 || res.StatusCode >= 300 {
		return nil, fmt.Errorf("Play API error: %d %s", res.StatusCode, string(body))
	}

	var data subscriptionPurchaseV2
	if err := json.Unmarshal(body, &data); err != nil {
		return nil, fmt.Errorf("Play API のレスポンスをパースできない: %w", err)
	}

	return mapResult(packageName, subscriptionID, &data)
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
	// lineItems[0] にサブスクリプションの詳細（有効期限、自動更新状態）が含まれる
	var expiresAt *time.Time
	autoRenewing := false
	if len(data.LineItems) > 0 {
		item := data.LineItems[0]
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
	}

	if expiresAt == nil {
		// expiryTime が無いと期限判定が働かず永久 premium になるため expired 扱い
		log.Printf("Subscription has no expiryTime; treating as expired (packageName=%s, subscriptionId=%s, subscriptionState=%s)",
			packageName, subscriptionID, data.SubscriptionState)
		return &VerificationResult{
			Valid: true, ExpiresAt: nil,
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
		Valid: true, ExpiresAt: expiresAt,
		AutoRenewing: autoRenewing, Status: status,
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
