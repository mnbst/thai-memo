package callable

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"firebase.google.com/go/v4/auth"
)

type fakeVerifier struct {
	uid    string
	claims map[string]any
	err    error
}

func (f fakeVerifier) VerifyIDToken(_ context.Context, _ string) (*auth.Token, error) {
	if f.err != nil {
		return nil, f.err
	}
	return &auth.Token{UID: f.uid, Claims: f.claims}, nil
}

func post(h http.HandlerFunc, body string, bearer string) *httptest.ResponseRecorder {
	r := httptest.NewRequest(http.MethodPost, "/", strings.NewReader(body))
	if bearer != "" {
		r.Header.Set("Authorization", "Bearer "+bearer)
	}
	w := httptest.NewRecorder()
	h(w, r)
	return w
}

func TestSuccessEnvelope(t *testing.T) {
	h := HTTP("t", nil, func(_ context.Context, req *Request) (any, error) {
		var in struct {
			N int `json:"n"`
		}
		if err := req.Bind(&in); err != nil {
			return nil, err
		}
		return map[string]any{"doubled": in.N * 2}, nil
	})

	w := post(h, `{"data":{"n":21}}`, "")
	if w.Code != 200 {
		t.Fatalf("status = %d, want 200", w.Code)
	}
	var got struct {
		Result struct {
			Doubled int `json:"doubled"`
		} `json:"result"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &got); err != nil {
		t.Fatal(err)
	}
	if got.Result.Doubled != 42 {
		t.Fatalf("doubled = %d, want 42", got.Result.Doubled)
	}
}

func TestUnauthenticatedMatchesJSWording(t *testing.T) {
	h := HTTP("t", nil, func(_ context.Context, req *Request) (any, error) {
		_, err := req.RequireAuth()
		return nil, err
	})

	w := post(h, `{"data":{}}`, "")
	if w.Code != 401 {
		t.Fatalf("status = %d, want 401", w.Code)
	}
	var got struct {
		Error struct {
			Status  string `json:"status"`
			Message string `json:"message"`
		} `json:"error"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &got); err != nil {
		t.Fatal(err)
	}
	if got.Error.Status != "UNAUTHENTICATED" {
		t.Fatalf("status = %q", got.Error.Status)
	}
	// JS 版 (resetLearningData.ts) と同じ文言。クライアントの表示が変わらないこと。
	if got.Error.Message != "認証が必要です" {
		t.Fatalf("message = %q", got.Error.Message)
	}
}

func TestVerifiedTokenReachesHandler(t *testing.T) {
	h := HTTP("t", fakeVerifier{uid: "u1", claims: map[string]any{"admin": true}},
		func(_ context.Context, req *Request) (any, error) {
			uid, err := req.RequireAuth()
			if err != nil {
				return nil, err
			}
			return map[string]any{"uid": uid, "admin": req.Auth.HasClaim("admin")}, nil
		})

	w := post(h, `{"data":{}}`, "tok")
	if w.Code != 200 {
		t.Fatalf("status = %d body = %s", w.Code, w.Body)
	}
	if !strings.Contains(w.Body.String(), `"uid":"u1"`) ||
		!strings.Contains(w.Body.String(), `"admin":true`) {
		t.Fatalf("body = %s", w.Body)
	}
}

func TestInvalidTokenRejectedBeforeHandler(t *testing.T) {
	called := false
	h := HTTP("t", fakeVerifier{err: errors.New("bad")},
		func(_ context.Context, _ *Request) (any, error) {
			called = true
			return nil, nil
		})

	w := post(h, `{"data":{}}`, "tok")
	if w.Code != 401 {
		t.Fatalf("status = %d, want 401", w.Code)
	}
	if called {
		t.Fatal("不正トークンでハンドラが呼ばれてはいけない")
	}
}

func TestUnknownErrorIsNotLeaked(t *testing.T) {
	h := HTTP("t", nil, func(_ context.Context, _ *Request) (any, error) {
		return nil, errors.New("db password is hunter2")
	})

	w := post(h, `{"data":{}}`, "")
	if w.Code != 500 {
		t.Fatalf("status = %d, want 500", w.Code)
	}
	if strings.Contains(w.Body.String(), "hunter2") {
		t.Fatalf("内部エラーの詳細が漏れている: %s", w.Body)
	}
}

func TestPreflight(t *testing.T) {
	h := HTTP("t", nil, func(_ context.Context, _ *Request) (any, error) { return nil, nil })
	r := httptest.NewRequest(http.MethodOptions, "/", nil)
	w := httptest.NewRecorder()
	h(w, r)
	if w.Code != http.StatusNoContent {
		t.Fatalf("status = %d", w.Code)
	}
	if !strings.Contains(w.Header().Get("Access-Control-Allow-Headers"), "X-Firebase-AppCheck") {
		t.Fatalf("headers = %q", w.Header().Get("Access-Control-Allow-Headers"))
	}
}
