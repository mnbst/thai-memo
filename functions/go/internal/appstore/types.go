// Package appstore は App Store Server API v1 のクライアント。
// functions/javascript/src/services/appStoreServer.ts の移植。
//
// 認証は JWT（ES256 署名）。必要なシークレットは Secret Manager から取る。
// 通知ペイロードの署名検証は internal/applejws が担当する。
package appstore

// Status はアプリ内で統一的に扱うサブスクリプションの状態。
type Status string

const (
	StatusActive      Status = "active"
	StatusCanceled    Status = "canceled"
	StatusExpired     Status = "expired"
	StatusGracePeriod Status = "grace_period"
)

// VerificationResult は App Store 購入検証の結果。
type VerificationResult struct {
	Valid                 bool
	OriginalTransactionID string
	// ExpiresAt は有効期限。無い場合は nil。
	ExpiresAt    *int64 // エポックミリ秒
	AutoRenewing bool
	Status       Status
}

// TransactionInfo は Apple のトランザクション情報（JWS デコード後）。
//
// OriginalTransactionID はサブスクリプションの初回購入時のトランザクションID。
// 更新・復元時も同じ値が使われるため、ユーザー検索のキーとして Firestore に保存する。
type TransactionInfo struct {
	OriginalTransactionID string `json:"originalTransactionId"`
	TransactionID         string `json:"transactionId"`
	ProductID             string `json:"productId"`
	// ExpiresDate はサブスクリプションの有効期限（エポックミリ秒）。
	ExpiresDate *int64 `json:"expiresDate"`
	// RevocationDate は返金・取消日。存在する場合はサブスクリプション無効。
	RevocationDate *int64 `json:"revocationDate"`
	Type           string `json:"type"`
	Environment    string `json:"environment"`
}

// RenewalInfo は Apple の更新情報（JWS デコード後）。
//
// AutoRenewStatus は自動更新の状態（1=ON, 0=OFF）。
// ExpirationIntent は期限切れの理由
// （1=ユーザーキャンセル, 2=課金エラー, 3=同意なし, 4=商品変更）。
type RenewalInfo struct {
	AutoRenewStatus       int    `json:"autoRenewStatus"`
	OriginalTransactionID string `json:"originalTransactionId"`
	ProductID             string `json:"productId"`
	ExpirationIntent      *int   `json:"expirationIntent"`
}

// Notification は App Store Server Notifications V2 の通知（署名検証・パース済み）。
type Notification struct {
	NotificationType string
	Subtype          string
	TransactionInfo  TransactionInfo
	RenewalInfo      *RenewalInfo
}
