package function

import (
	"encoding/json"
	"errors"
	"testing"

	"firebase.google.com/go/v4/auth"

	"github.com/mnbst/thai-memo/functions/go/internal/callable"
)

// authedRequest は認証済みの callable リクエストを組み立てる。
func authedRequest(data string) *callable.Request {
	return &callable.Request{
		Auth: &callable.Auth{
			UID:   "go-port-test-uid",
			Token: &auth.Token{UID: "go-port-test-uid"},
		},
		Data: json.RawMessage(data),
	}
}

// assertCallableError はエラーのコードと文言を確かめる。
// 文言はクライアントに出るので、JS 版と1文字も変えないこと。
func assertCallableError(t *testing.T, err error, code callable.Code, msg string) {
	t.Helper()
	if err == nil {
		t.Fatalf("エラーになるはずが nil")
	}
	var callErr *callable.Error
	if !errors.As(err, &callErr) {
		t.Fatalf("callable.Error ではない: %v", err)
	}
	if callErr.Code != code {
		t.Errorf("code: want %s, got %s", code, callErr.Code)
	}
	if callErr.Message != msg {
		t.Errorf("message:\n  want %q\n  got  %q", msg, callErr.Message)
	}
}
