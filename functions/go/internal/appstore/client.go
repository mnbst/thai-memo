package appstore

import (
	"context"
	"crypto/ecdsa"
	"crypto/rand"
	"crypto/sha256"
	"crypto/x509"
	"encoding/base64"
	"encoding/json"
	"encoding/pem"
	"errors"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"strings"
	"time"

	"github.com/mnbst/thai-memo/functions/go/internal/applejws"
	"github.com/mnbst/thai-memo/functions/go/internal/secrets"
)

// defaultBundleID は APP_STORE_BUNDLE_ID 未設定時の現行本番 ID。
const defaultBundleID = "com.thaimemo.thaiMemo"

// jwtLifetime は App Store Server API 認証用 JWT の有効期限（JS 版の '20m'）。
const jwtLifetime = 20 * time.Minute

// Client は App Store Server API を叩く。
type Client struct {
	// HTTP は差し替え用。nil なら http.DefaultClient。
	HTTP *http.Client
	// Verifier は通知・レスポンスの署名検証。nil なら本番のピン留め。
	Verifier *applejws.Verifier
	// Now はテスト用。nil なら time.Now。
	Now func() time.Time
}

// Default は本番設定のクライアント。
var Default = &Client{}

func (c *Client) httpClient() *http.Client {
	if c.HTTP != nil {
		return c.HTTP
	}
	return http.DefaultClient
}

func (c *Client) verifier() *applejws.Verifier {
	if c.Verifier != nil {
		return c.Verifier
	}
	return applejws.DefaultVerifier
}

func (c *Client) now() time.Time {
	if c.Now != nil {
		return c.Now()
	}
	return time.Now()
}

// generateJWT は App Store Server API 認証用の JWT（ES256）を作る。
//
// 必要なシークレットを Secret Manager から取る:
//   - appstore-connect-key: App Store Connect で生成した秘密鍵（.p8 の中身）
//   - appstore-key-id: API キーの Key ID
//   - appstore-issuer-id: App Store Connect の Issuer ID
//
// Bundle ID は APP_STORE_BUNDLE_ID 環境変数（未設定時は現行本番 ID）。
func (c *Client) generateJWT(ctx context.Context) (string, error) {
	privateKeyPEM, err := secrets.Get(ctx, "appstore-connect-key")
	if err != nil {
		return "", err
	}
	keyID, err := secrets.Get(ctx, "appstore-key-id")
	if err != nil {
		return "", err
	}
	issuerID, err := secrets.Get(ctx, "appstore-issuer-id")
	if err != nil {
		return "", err
	}

	bundleID := os.Getenv("APP_STORE_BUNDLE_ID")
	if bundleID == "" {
		bundleID = defaultBundleID
	}

	key, err := parsePKCS8ECKey(privateKeyPEM)
	if err != nil {
		return "", err
	}

	now := c.now()
	header := map[string]any{"alg": "ES256", "kid": keyID, "typ": "JWT"}
	claims := map[string]any{
		"iss": issuerID,
		"iat": now.Unix(),
		"exp": now.Add(jwtLifetime).Unix(),
		"aud": "appstoreconnect-v1",
		"bid": bundleID,
	}

	return signES256(header, claims, key)
}

func parsePKCS8ECKey(pemStr string) (*ecdsa.PrivateKey, error) {
	block, _ := pem.Decode([]byte(strings.TrimSpace(pemStr)))
	if block == nil {
		return nil, errors.New("appstore-connect-key が PEM ではない")
	}
	parsed, err := x509.ParsePKCS8PrivateKey(block.Bytes)
	if err != nil {
		return nil, fmt.Errorf("appstore-connect-key のパースに失敗: %w", err)
	}
	key, ok := parsed.(*ecdsa.PrivateKey)
	if !ok {
		return nil, errors.New("appstore-connect-key が ECDSA 鍵ではない")
	}
	return key, nil
}

// signES256 は JWS compact 形式で署名する。ES256 の署名は r||s の 64 バイト
// 固定長で、DER ではない（jose と同じ形）。
func signES256(header, claims map[string]any, key *ecdsa.PrivateKey) (string, error) {
	headerJSON, err := json.Marshal(header)
	if err != nil {
		return "", err
	}
	claimsJSON, err := json.Marshal(claims)
	if err != nil {
		return "", err
	}

	signingInput := base64.RawURLEncoding.EncodeToString(headerJSON) + "." +
		base64.RawURLEncoding.EncodeToString(claimsJSON)

	digest := sha256.Sum256([]byte(signingInput))
	r, s, err := ecdsa.Sign(rand.Reader, key, digest[:])
	if err != nil {
		return "", err
	}

	sig := make([]byte, 64)
	r.FillBytes(sig[:32])
	s.FillBytes(sig[32:])

	return signingInput + "." + base64.RawURLEncoding.EncodeToString(sig), nil
}

// environments は 404 フォールバックのための環境ペアを返す。
//
// 設定側の環境を優先し、404 なら反対側を試す。
// TestFlight / Sandbox で購入したトランザクションは本番 API に存在せず
// 404（errorCode 4040010: Transaction id not found）になるため、
// フォールバックしないとテスターの購入検証が必ず失敗する。
func environments() (primary, fallback string) {
	if os.Getenv("APP_STORE_ENVIRONMENT") == "production" {
		return "api.storekit", "api.storekit-sandbox"
	}
	return "api.storekit-sandbox", "api.storekit"
}

func (c *Client) get(ctx context.Context, url, jwt string) (*http.Response, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Authorization", "Bearer "+jwt)
	return c.httpClient().Do(req)
}

func readBody(res *http.Response) string {
	defer res.Body.Close()
	b, err := io.ReadAll(res.Body)
	if err != nil {
		return ""
	}
	return string(b)
}

// ExtractTransactionID は StoreKit 2 の serverVerificationData（JWS 形式）から
// 実際の transactionId を取り出す。JWS でなければ入力をそのまま返す。
func ExtractTransactionID(token string) string {
	if len(strings.Split(token, ".")) != 3 {
		return token
	}
	var payload struct {
		TransactionID string `json:"transactionId"`
	}
	// デコード失敗時はそのまま使用（JS 版と同じ）
	if err := applejws.DecodePayload(token, &payload); err != nil {
		return token
	}
	if payload.TransactionID == "" {
		return token
	}
	return payload.TransactionID
}

// VerifyPurchase は App Store Server API v1 でトランザクションを検証する。
//
// transactionID を使って Apple のサーバーにトランザクション情報を問い合わせ、
// サブスクリプションの有効性（期限切れ・返金済みかどうか）を判定する。
func (c *Client) VerifyPurchase(ctx context.Context, transactionID string) (*VerificationResult, error) {
	transactionID = ExtractTransactionID(transactionID)

	jwt, err := c.generateJWT(ctx)
	if err != nil {
		return nil, err
	}

	primary, fallback := environments()
	environment := primary

	res, err := c.get(ctx,
		fmt.Sprintf("https://%s.apple.com/inApps/v1/transactions/%s", environment, transactionID),
		jwt)
	if err != nil {
		return nil, err
	}

	if res.StatusCode == http.StatusNotFound {
		log.Printf("App Store API 404 on %s; retrying on %s (transactionId=%s, body=%s)",
			primary, fallback, transactionID, readBody(res))
		environment = fallback
		res, err = c.get(ctx,
			fmt.Sprintf("https://%s.apple.com/inApps/v1/transactions/%s", environment, transactionID),
			jwt)
		if err != nil {
			return nil, err
		}
	}

	if res.StatusCode < 200 || res.StatusCode >= 300 {
		body := readBody(res)
		log.Printf("App Store API error: %d (transactionId=%s, environment=%s, body=%s)",
			res.StatusCode, transactionID, environment, body)
		return nil, fmt.Errorf("App Store API error: %d", res.StatusCode)
	}

	var body struct {
		SignedTransactionInfo string `json:"signedTransactionInfo"`
	}
	raw := readBody(res)
	if err := json.Unmarshal([]byte(raw), &body); err != nil {
		return nil, fmt.Errorf("App Store API のレスポンスをパースできない: %w", err)
	}

	if err := c.verifier().Verify(body.SignedTransactionInfo); err != nil {
		return nil, err
	}
	var tx TransactionInfo
	if err := applejws.DecodePayload(body.SignedTransactionInfo, &tx); err != nil {
		return nil, err
	}

	// 自動更新サブスクなら expiresDate は必ず来る。無い場合に premium を付与すると
	// 期限判定が働かず永久 premium になるため、expired として扱う。
	if tx.ExpiresDate == nil {
		log.Printf("Transaction has no expiresDate; treating as expired (transactionId=%s, originalTransactionId=%s)",
			transactionID, tx.OriginalTransactionID)
	}

	isExpired := true
	if tx.ExpiresDate != nil {
		isExpired = *tx.ExpiresDate < c.now().UnixMilli()
	}
	isRevoked := tx.RevocationDate != nil

	// 自動更新状態は transaction API には含まれないため subscriptions API から取る。
	// 取得失敗時（nil）は従来通り autoRenewing=true / active にフォールバックする。
	renewalInfo := c.fetchRenewalInfo(ctx, tx.OriginalTransactionID, jwt, environment)
	autoRenewing := true
	if renewalInfo != nil {
		autoRenewing = renewalInfo.AutoRenewStatus == 1
	}

	var status Status
	switch {
	case isRevoked || isExpired:
		status = StatusExpired
	case renewalInfo != nil && renewalInfo.AutoRenewStatus == 0:
		// 解約済み（自動更新OFF）だが期限内 → premium は期限まで維持
		status = StatusCanceled
	default:
		status = StatusActive
	}

	return &VerificationResult{
		Valid:                 !isRevoked,
		ProductID:             tx.ProductID,
		OriginalTransactionID: tx.OriginalTransactionID,
		ExpiresAt:             tx.ExpiresDate,
		AutoRenewing:          autoRenewing,
		Status:                status,
	}, nil
}

// fetchRenewalInfo は Get All Subscription Statuses API から最新の RenewalInfo を取る。
//
// transaction API のレスポンスには autoRenewStatus が含まれないため、
// /inApps/v1/subscriptions/{originalTransactionId} から signedRenewalInfo を取得する。
// 取得・検証に失敗しても購入検証自体は成立させたいので、失敗時は nil を返す。
func (c *Client) fetchRenewalInfo(
	ctx context.Context, originalTransactionID, jwt, environment string,
) *RenewalInfo {
	res, err := c.get(ctx,
		fmt.Sprintf("https://%s.apple.com/inApps/v1/subscriptions/%s",
			environment, originalTransactionID),
		jwt)
	if err != nil {
		log.Printf("Failed to fetch renewal info: %v", err)
		return nil
	}
	if res.StatusCode < 200 || res.StatusCode >= 300 {
		readBody(res)
		log.Printf("App Store subscriptions API error: %d (originalTransactionId=%s)",
			res.StatusCode, originalTransactionID)
		return nil
	}

	var body struct {
		Data []struct {
			LastTransactions []struct {
				OriginalTransactionID string `json:"originalTransactionId"`
				SignedRenewalInfo     string `json:"signedRenewalInfo"`
			} `json:"lastTransactions"`
		} `json:"data"`
	}
	if err := json.Unmarshal([]byte(readBody(res)), &body); err != nil {
		log.Printf("Failed to fetch renewal info: %v", err)
		return nil
	}

	var signed string
	for _, group := range body.Data {
		for _, tx := range group.LastTransactions {
			if tx.OriginalTransactionID == originalTransactionID {
				signed = tx.SignedRenewalInfo
				break
			}
		}
		if signed != "" {
			break
		}
	}
	if signed == "" {
		return nil
	}

	if err := c.verifier().Verify(signed); err != nil {
		log.Printf("Failed to fetch renewal info: %v", err)
		return nil
	}
	var renewal RenewalInfo
	if err := applejws.DecodePayload(signed, &renewal); err != nil {
		log.Printf("Failed to fetch renewal info: %v", err)
		return nil
	}
	return &renewal
}

// ParseNotification は App Store Server Notifications V2 のペイロードを
// 署名検証してパースする。
//
// Apple からの通知は二重 JWS 構造:
//  1. 外側の JWS: 通知全体（notificationType, data を含む）← 署名検証する
//  2. 内側の JWS: data.signedTransactionInfo と data.signedRenewalInfo
//     ← デコードのみ（外側の署名で Apple 発行が担保されるため）
func (c *Client) ParseNotification(signedPayload string) (*Notification, error) {
	if err := c.verifier().Verify(signedPayload); err != nil {
		return nil, err
	}

	var notification struct {
		NotificationType string `json:"notificationType"`
		Subtype          string `json:"subtype"`
		SignedDate       *int64 `json:"signedDate"`
		Data             struct {
			SignedTransactionInfo string `json:"signedTransactionInfo"`
			SignedRenewalInfo     string `json:"signedRenewalInfo"`
		} `json:"data"`
	}
	if err := applejws.DecodePayload(signedPayload, &notification); err != nil {
		return nil, err
	}

	out := &Notification{
		NotificationType: notification.NotificationType,
		Subtype:          notification.Subtype,
		SignedDate:       notification.SignedDate,
	}
	if err := applejws.DecodePayload(
		notification.Data.SignedTransactionInfo, &out.TransactionInfo,
	); err != nil {
		return nil, err
	}
	if notification.Data.SignedRenewalInfo != "" {
		var renewal RenewalInfo
		if err := applejws.DecodePayload(
			notification.Data.SignedRenewalInfo, &renewal,
		); err != nil {
			return nil, err
		}
		out.RenewalInfo = &renewal
	}
	return out, nil
}
