package function

import (
	"testing"

	"firebase.google.com/go/v4/auth"

	"github.com/mnbst/thai-memo/functions/go/internal/callable"
)

func TestTokenEmail(t *testing.T) {
	tests := []struct {
		name string
		auth *callable.Auth
		want string
	}{
		{"確認済みは小文字にして使う", &callable.Auth{Token: &auth.Token{Claims: map[string]any{
			"email": " Tester@Example.com ", "email_verified": true}}}, "tester@example.com"},
		{"未確認は使わない", &callable.Auth{Token: &auth.Token{Claims: map[string]any{
			"email": "tester@example.com", "email_verified": false}}}, ""},
		{"確認の印が無ければ使わない", &callable.Auth{Token: &auth.Token{Claims: map[string]any{
			"email": "tester@example.com"}}}, ""},
		{"トークンが無い", &callable.Auth{}, ""},
		{"未認証", nil, ""},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := tokenEmail(tt.auth); got != tt.want {
				t.Errorf("tokenEmail = %q, want %q", got, tt.want)
			}
		})
	}
}
