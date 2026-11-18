package function

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"slices"
	"sync"
	"time"

	"firebase.google.com/go/v4/auth"
	"github.com/go-jose/go-jose/v4"
	"github.com/go-jose/go-jose/v4/jwt"
	"google.golang.org/api/idtoken"

	"github.com/mnbst/thai-memo/functions/go/internal/callable"
	"github.com/mnbst/thai-memo/functions/go/internal/fbapp"
)

// checkAccountExists は、Apple / Google の ID トークンの持ち主がこのプロジェクトに
// アカウントを持っているかを返す。初回画面の「アカウントをお持ちの方」で使う。
//
// クライアントが Firebase に credential を渡す前に確かめるので、新規なら
// アカウントを作らずに断れる（匿名ユーザーへ紐づけてから消す必要が無い）。
// 調べられるのはトークンで本人と証明できたアカウントだけなので、他人の登録状況は漏れない。
//
// 入力: {"provider": "apple" | "google", "idToken": "..."}
// 出力: {"exists": bool}
func checkAccountExists(ctx context.Context, req *callable.Request) (any, error) {
	if _, err := req.RequireAuth(); err != nil {
		return nil, err
	}
	var in struct {
		Provider string `json:"provider"`
		IDToken  string `json:"idToken"`
	}
	if err := req.Bind(&in); err != nil {
		return nil, err
	}
	if in.IDToken == "" {
		return nil, callable.Errorf(callable.InvalidArgument, "idToken がありません")
	}

	var providerID, sub string
	var err error
	switch in.Provider {
	case "apple":
		providerID = "apple.com"
		sub, err = verifyAppleIDToken(ctx, in.IDToken, time.Now())
	case "google":
		providerID = "google.com"
		sub, err = verifyGoogleIDToken(ctx, in.IDToken, fbapp.ProjectID())
	default:
		return nil, callable.Errorf(callable.InvalidArgument, "provider が不正です: %q", in.Provider)
	}
	if err != nil {
		log.Printf("checkAccountExists: トークンを検証できない: provider=%s error=%v", in.Provider, err)
		return nil, callable.Errorf(callable.Unauthenticated, "サインイン情報を確認できませんでした")
	}

	client, err := fbapp.Auth(ctx)
	if err != nil {
		return nil, err
	}
	exists, err := accountExists(ctx, client, providerID, sub)
	if err != nil {
		log.Printf("checkAccountExists: 照会に失敗: provider=%s error=%v", in.Provider, err)
		return nil, callable.Errorf(callable.Internal, "アカウントを確認できませんでした")
	}
	log.Printf("checkAccountExists: provider=%s exists=%t", in.Provider, exists)
	return map[string]any{"exists": exists}, nil
}

// providerUserGetter は auth.Client のうち照会に使う部分（テストで差し替える）。
type providerUserGetter interface {
	GetUserByProviderUID(ctx context.Context, providerID, providerUID string) (*auth.UserRecord, error)
}

func accountExists(ctx context.Context, c providerUserGetter, providerID, sub string) (bool, error) {
	_, err := c.GetUserByProviderUID(ctx, providerID, sub)
	if err == nil {
		return true, nil
	}
	if auth.IsUserNotFound(err) {
		return false, nil
	}
	return false, err
}

// ==================== Apple ====================

const (
	appleIssuer  = "https://appleid.apple.com"
	appleKeysURL = "https://appleid.apple.com/auth/keys"
)

// appleAudiences は Apple の ID トークンの宛先として認めるバンドル ID。
// com.thaimemo.Test は tester の手元用アプリ。
var appleAudiences = []string{"com.thaimemo.thaiMemo", "com.thaimemo.Test"}

// appleKeys は Apple の公開鍵のキャッシュ。鍵が入れ替わったとき（kid が見つからない）は取り直す。
var appleKeys = &jwksCache{url: appleKeysURL, ttl: 6 * time.Hour}

func verifyAppleIDToken(ctx context.Context, raw string, now time.Time) (string, error) {
	tok, err := jwt.ParseSigned(raw, []jose.SignatureAlgorithm{jose.RS256})
	if err != nil {
		return "", fmt.Errorf("JWT を解釈できない: %w", err)
	}
	if len(tok.Headers) == 0 {
		return "", fmt.Errorf("ヘッダーが無い")
	}
	key, err := appleKeys.key(ctx, tok.Headers[0].KeyID)
	if err != nil {
		return "", err
	}
	return verifyAppleClaims(tok, key, now)
}

// verifyAppleClaims は署名と発行元・宛先・期限を確かめ、sub を返す。
func verifyAppleClaims(tok *jwt.JSONWebToken, key *jose.JSONWebKey, now time.Time) (string, error) {
	var claims jwt.Claims
	if err := tok.Claims(key, &claims); err != nil {
		return "", fmt.Errorf("署名を検証できない: %w", err)
	}
	if !slices.ContainsFunc(appleAudiences, claims.Audience.Contains) {
		return "", fmt.Errorf("宛先が違う: %v", claims.Audience)
	}
	if err := claims.ValidateWithLeeway(jwt.Expected{Issuer: appleIssuer, Time: now}, time.Minute); err != nil {
		return "", err
	}
	// ValidateWithLeeway は exp が無いトークンも通すので、ここで弾く。
	if claims.Expiry == nil {
		return "", fmt.Errorf("exp が無い")
	}
	if claims.Subject == "" {
		return "", fmt.Errorf("sub が無い")
	}
	return claims.Subject, nil
}

// jwksMinRefetch は取り直しの最短間隔。でたらめな kid のトークンを送り続けて
// Apple への取得を連発させられないようにする。
const jwksMinRefetch = time.Minute

// jwksCache は JWKS を取得して kid で引く。
type jwksCache struct {
	url string
	ttl time.Duration

	mu      sync.Mutex
	set     jose.JSONWebKeySet
	fetched time.Time
}

func (c *jwksCache) key(ctx context.Context, kid string) (*jose.JSONWebKey, error) {
	c.mu.Lock()
	defer c.mu.Unlock()
	if time.Since(c.fetched) < c.ttl {
		if keys := c.set.Key(kid); len(keys) > 0 {
			return &keys[0], nil
		}
	}
	if time.Since(c.fetched) >= jwksMinRefetch {
		if err := c.fetch(ctx); err != nil {
			return nil, err
		}
	}
	keys := c.set.Key(kid)
	if len(keys) == 0 {
		return nil, fmt.Errorf("鍵が見つからない: kid=%s", kid)
	}
	return &keys[0], nil
}

func (c *jwksCache) fetch(ctx context.Context) error {
	ctx, cancel := context.WithTimeout(ctx, 10*time.Second)
	defer cancel()
	r, err := http.NewRequestWithContext(ctx, http.MethodGet, c.url, nil)
	if err != nil {
		return err
	}
	res, err := http.DefaultClient.Do(r)
	if err != nil {
		return fmt.Errorf("公開鍵を取得できない: %w", err)
	}
	defer res.Body.Close()
	if res.StatusCode != http.StatusOK {
		return fmt.Errorf("公開鍵を取得できない: status=%d", res.StatusCode)
	}
	var set jose.JSONWebKeySet
	if err := json.NewDecoder(res.Body).Decode(&set); err != nil {
		return fmt.Errorf("公開鍵を解釈できない: %w", err)
	}
	c.set, c.fetched = set, time.Now()
	return nil
}

// ==================== Google ====================

// googleAudiences は環境ごとに Google の ID トークンの宛先として認める OAuth クライアント。
// iOS は iOS クライアント、Android はサーバー用クライアント（GoogleSignIn の
// serverClientId。lib/services/firebase_auth_service.dart）が宛先になる。
// クライアントを足したらここにも足すこと（漏れると Google で既存アカウントに入れない）。
var googleAudiences = map[string][]string{
	"thai-memo-prod": {
		"219961294368-52quesdb24i0e0b15sjo8d0tkm73vlq4.apps.googleusercontent.com", // iOS
		"219961294368-boa977qont6o95dl34vhl3o8v85uv7vh.apps.googleusercontent.com", // サーバー用（Android）
	},
	"thai-memo-67139": {
		"763566155520-ghi3sn3sq8j5e4fujj18bplrnug23j14.apps.googleusercontent.com", // iOS
		"763566155520-jeqi69fpcnu90v1kd8u8tndpl41ovvpi.apps.googleusercontent.com", // iOS（手元用 com.thaimemo.Test）
		"763566155520-anliuk00tk1fv4d0nou0o48dhroevlfg.apps.googleusercontent.com", // サーバー用（Android）
	},
}

// googleIssuers は Google の ID トークンの発行元。idtoken.Validate は発行元を見ない。
var googleIssuers = []string{"accounts.google.com", "https://accounts.google.com"}

func verifyGoogleIDToken(ctx context.Context, raw, projectID string) (string, error) {
	// 宛先は下で確かめるので、ここでは署名と期限だけ見る。
	p, err := idtoken.Validate(ctx, raw, "")
	if err != nil {
		return "", err
	}
	if err := checkGoogleClaims(p.Issuer, p.Audience, projectID); err != nil {
		return "", err
	}
	if p.Subject == "" {
		return "", fmt.Errorf("sub が無い")
	}
	return p.Subject, nil
}

func checkGoogleClaims(iss, aud, projectID string) error {
	if !slices.Contains(googleIssuers, iss) {
		return fmt.Errorf("発行元が違う: %s", iss)
	}
	if !slices.Contains(googleAudiences[projectID], aud) {
		return fmt.Errorf("宛先が違う: project=%s aud=%s", projectID, aud)
	}
	return nil
}
