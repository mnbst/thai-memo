package function

import (
	"context"
	"crypto/rand"
	"crypto/rsa"
	"errors"
	"testing"
	"time"

	"firebase.google.com/go/v4/auth"
	"github.com/go-jose/go-jose/v4"
	"github.com/go-jose/go-jose/v4/jwt"
)

func signAppleToken(t *testing.T, key *rsa.PrivateKey, claims jwt.Claims) *jwt.JSONWebToken {
	t.Helper()
	signer, err := jose.NewSigner(jose.SigningKey{Algorithm: jose.RS256, Key: key},
		(&jose.SignerOptions{}).WithHeader("kid", "k1"))
	if err != nil {
		t.Fatal(err)
	}
	raw, err := jwt.Signed(signer).Claims(claims).Serialize()
	if err != nil {
		t.Fatal(err)
	}
	tok, err := jwt.ParseSigned(raw, []jose.SignatureAlgorithm{jose.RS256})
	if err != nil {
		t.Fatal(err)
	}
	return tok
}

func TestVerifyAppleClaims(t *testing.T) {
	key, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatal(err)
	}
	other, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatal(err)
	}
	pub := &jose.JSONWebKey{Key: &key.PublicKey, KeyID: "k1", Algorithm: "RS256"}
	now := time.Date(2026, 11, 18, 12, 0, 0, 0, time.UTC)
	valid := jwt.Claims{
		Issuer:   appleIssuer,
		Subject:  "001234.abcd",
		Audience: jwt.Audience{"com.thaimemo.thaiMemo"},
		IssuedAt: jwt.NewNumericDate(now.Add(-time.Minute)),
		Expiry:   jwt.NewNumericDate(now.Add(10 * time.Minute)),
	}

	tests := []struct {
		name    string
		signer  *rsa.PrivateKey
		mutate  func(c *jwt.Claims)
		wantSub string
	}{
		{"正しいトークンは sub を返す", key, func(*jwt.Claims) {}, "001234.abcd"},
		{"tester の手元用アプリも通す", key, func(c *jwt.Claims) { c.Audience = jwt.Audience{"com.thaimemo.Test"} }, "001234.abcd"},
		{"別の鍵の署名は通さない", other, func(*jwt.Claims) {}, ""},
		{"別アプリ宛ては通さない", key, func(c *jwt.Claims) { c.Audience = jwt.Audience{"com.example.other"} }, ""},
		{"発行元が違えば通さない", key, func(c *jwt.Claims) { c.Issuer = "https://evil.example.com" }, ""},
		{"期限切れは通さない", key, func(c *jwt.Claims) { c.Expiry = jwt.NewNumericDate(now.Add(-time.Hour)) }, ""},
		{"sub が無ければ通さない", key, func(c *jwt.Claims) { c.Subject = "" }, ""},
		{"exp が無ければ通さない", key, func(c *jwt.Claims) { c.Expiry = nil }, ""},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			c := valid
			tt.mutate(&c)
			sub, err := verifyAppleClaims(signAppleToken(t, tt.signer, c), pub, now)
			if tt.wantSub == "" {
				if err == nil {
					t.Fatalf("err = nil, sub = %q", sub)
				}
				return
			}
			if err != nil || sub != tt.wantSub {
				t.Fatalf("sub = %q, err = %v, want %q", sub, err, tt.wantSub)
			}
		})
	}
}

func TestCheckGoogleClaims(t *testing.T) {
	const prodIOS = "219961294368-52quesdb24i0e0b15sjo8d0tkm73vlq4.apps.googleusercontent.com"
	const testerServer = "763566155520-anliuk00tk1fv4d0nou0o48dhroevlfg.apps.googleusercontent.com"
	tests := []struct {
		name    string
		iss     string
		aud     string
		project string
		ok      bool
	}{
		{"prod の iOS クライアント", "https://accounts.google.com", prodIOS, "thai-memo-prod", true},
		{"tester のサーバー用クライアント", "accounts.google.com", testerServer, "thai-memo-67139", true},
		{"他の環境のクライアントは通さない", "accounts.google.com", testerServer, "thai-memo-prod", false},
		{"同じプロジェクトの別クライアントは通さない", "accounts.google.com", "219961294368-other.apps.googleusercontent.com", "thai-memo-prod", false},
		{"発行元が違えば通さない", "https://securetoken.google.com/thai-memo-prod", prodIOS, "thai-memo-prod", false},
		{"未登録のプロジェクト", "accounts.google.com", prodIOS, "unknown", false},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if err := checkGoogleClaims(tt.iss, tt.aud, tt.project); (err == nil) != tt.ok {
				t.Errorf("checkGoogleClaims err = %v, ok want %t", err, tt.ok)
			}
		})
	}
}

type fakeProviderUsers struct {
	err error
}

func (f fakeProviderUsers) GetUserByProviderUID(context.Context, string, string) (*auth.UserRecord, error) {
	if f.err != nil {
		return nil, f.err
	}
	return &auth.UserRecord{}, nil
}

// 「見つからない」は auth パッケージの内部エラーで、外から作れないので実物（live）でしか見ない。
func TestAccountExists(t *testing.T) {
	ctx := context.Background()
	got, err := accountExists(ctx, fakeProviderUsers{}, "apple.com", "s1")
	if err != nil || !got {
		t.Fatalf("登録済み: got %t err %v", got, err)
	}
	// 照会の失敗（見つからない以外）は存在しない扱いにせずエラーで返す。
	if _, err := accountExists(ctx, fakeProviderUsers{err: errors.New("boom")}, "apple.com", "s1"); err == nil {
		t.Fatal("照会失敗が握りつぶされた")
	}
}
