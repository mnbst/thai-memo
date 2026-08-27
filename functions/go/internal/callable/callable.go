// Package callable は Firebase の callable プロトコル（firebase-functions の
// onCall が話すもの）を Go で実装する。
//
// Go 版 Firebase Functions SDK は存在しないので、クライアント（Flutter の
// cloud_functions プラグイン）が期待する電文を自前で満たす必要がある。
// 電文が変わるとクライアント改修が必要になるため、ここは JS/Python 実装との
// 互換性が最優先。
//
//	リクエスト:  POST {"data": <任意>}
//	              Authorization: Bearer <Firebase ID token>
//	成功:        200 {"result": <任意>}
//	失敗:        <code に対応する HTTP status> {"error": {"status","message","details"}}
package callable

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"net/http"
	"strings"

	"firebase.google.com/go/v4/auth"
)

// Code は callable のエラーコード（gRPC の canonical code 名）。
type Code string

const (
	OK                 Code = "OK"
	Cancelled          Code = "CANCELLED"
	Unknown            Code = "UNKNOWN"
	InvalidArgument    Code = "INVALID_ARGUMENT"
	DeadlineExceeded   Code = "DEADLINE_EXCEEDED"
	NotFound           Code = "NOT_FOUND"
	AlreadyExists      Code = "ALREADY_EXISTS"
	PermissionDenied   Code = "PERMISSION_DENIED"
	ResourceExhausted  Code = "RESOURCE_EXHAUSTED"
	FailedPrecondition Code = "FAILED_PRECONDITION"
	Aborted            Code = "ABORTED"
	OutOfRange         Code = "OUT_OF_RANGE"
	Unimplemented      Code = "UNIMPLEMENTED"
	Internal           Code = "INTERNAL"
	Unavailable        Code = "UNAVAILABLE"
	DataLoss           Code = "DATA_LOSS"
	Unauthenticated    Code = "UNAUTHENTICATED"
)

// httpStatus は firebase-functions/common/providers/https.ts の対応表。
// クライアントは HTTP status ではなく body の status を見るが、
// 中間のプロキシやログの見え方が変わるので合わせておく。
var httpStatus = map[Code]int{
	OK:                 200,
	Cancelled:          499,
	Unknown:            500,
	InvalidArgument:    400,
	DeadlineExceeded:   504,
	NotFound:           404,
	AlreadyExists:      409,
	PermissionDenied:   403,
	ResourceExhausted:  429,
	FailedPrecondition: 400,
	Aborted:            409,
	OutOfRange:         400,
	Unimplemented:      501,
	Internal:           500,
	Unavailable:        503,
	DataLoss:           500,
	Unauthenticated:    401,
}

// Error は HttpsError 相当。ハンドラはこれを返すとクライアントに
// FirebaseFunctionsException として伝わる。
type Error struct {
	Code    Code
	Message string
	Details any
}

func (e *Error) Error() string { return fmt.Sprintf("%s: %s", e.Code, e.Message) }

// Errorf は HttpsError を組み立てる。
func Errorf(code Code, format string, args ...any) *Error {
	return &Error{Code: code, Message: fmt.Sprintf(format, args...)}
}

// Auth は検証済みの呼び出し元。未認証なら nil。
type Auth struct {
	UID   string
	Token *auth.Token
}

// HasClaim は custom claim が true かを見る（setUserTier の admin 判定用）。
func (a *Auth) HasClaim(name string) bool {
	if a == nil || a.Token == nil {
		return false
	}
	v, ok := a.Token.Claims[name].(bool)
	return ok && v
}

// Request はハンドラに渡る要求。Data は生 JSON のままなので、
// ハンドラ側で Bind して型付きの構造体に落とす。
type Request struct {
	Auth *Auth
	Data json.RawMessage
	// Raw は稀に header などが要るハンドラ向け。通常は使わない。
	Raw *http.Request
}

// Bind は data を v にデコードする。失敗は INVALID_ARGUMENT。
func (r *Request) Bind(v any) error {
	if len(r.Data) == 0 || string(r.Data) == "null" {
		return nil
	}
	if err := json.Unmarshal(r.Data, v); err != nil {
		return Errorf(InvalidArgument, "リクエストの形式が不正です: %v", err)
	}
	return nil
}

// RequireAuth は認証必須のハンドラ冒頭で使う。JS 側の
// `if (!request.auth?.uid) throw new HttpsError('unauthenticated', '認証が必要です')`
// と同じメッセージを返す（クライアントの表示文言が変わらないように）。
func (r *Request) RequireAuth() (string, error) {
	if r.Auth == nil || r.Auth.UID == "" {
		return "", Errorf(Unauthenticated, "認証が必要です")
	}
	return r.Auth.UID, nil
}

// Handler は callable 一つ分の処理。返り値が {"result": ...} になる。
type Handler func(ctx context.Context, req *Request) (any, error)

// Verifier は ID token を検証する。テストで差し替えられるようにインタフェース。
type Verifier interface {
	VerifyIDToken(ctx context.Context, idToken string) (*auth.Token, error)
}

// HTTP は Handler を functions-framework に渡せる http.HandlerFunc にする。
//
// verify が nil のときは認証をスキップする（ローカル検証用）。本番では
// 必ず Firebase Auth クライアントを渡すこと。
func HTTP(name string, verify Verifier, h Handler) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		// CORS: cloud_functions プラグインは Web でのみ preflight を出すが、
		// 将来 Web 対応する場合に備えて JS SDK と同じ応答をしておく。
		w.Header().Set("Access-Control-Allow-Origin", "*")
		if r.Method == http.MethodOptions {
			w.Header().Set("Access-Control-Allow-Methods", "POST")
			w.Header().Set("Access-Control-Allow-Headers",
				"Content-Type,Authorization,X-Firebase-AppCheck,X-Firebase-Client")
			w.Header().Set("Access-Control-Max-Age", "3600")
			w.WriteHeader(http.StatusNoContent)
			return
		}
		if r.Method != http.MethodPost {
			writeError(w, name, Errorf(InvalidArgument, "POST のみ受け付けます"))
			return
		}

		ctx := r.Context()

		var body struct {
			Data json.RawMessage `json:"data"`
		}
		if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
			writeError(w, name, Errorf(InvalidArgument, "リクエストの形式が不正です"))
			return
		}

		req := &Request{Data: body.Data, Raw: r}

		if tok := bearerToken(r); tok != "" && verify != nil {
			decoded, err := verify.VerifyIDToken(ctx, tok)
			if err != nil {
				// JS SDK は不正トークンを 401 で弾く（ハンドラを呼ばない）。
				writeError(w, name, Errorf(Unauthenticated, "認証トークンが無効です"))
				return
			}
			req.Auth = &Auth{UID: decoded.UID, Token: decoded}
		}

		result, err := h(ctx, req)
		if err != nil {
			writeError(w, name, err)
			return
		}

		w.Header().Set("Content-Type", "application/json")
		if err := json.NewEncoder(w).Encode(map[string]any{"result": result}); err != nil {
			log.Printf("%s: レスポンスの書き出しに失敗: %v", name, err)
		}
	}
}

func bearerToken(r *http.Request) string {
	h := r.Header.Get("Authorization")
	if len(h) > 7 && strings.EqualFold(h[:7], "Bearer ") {
		return strings.TrimSpace(h[7:])
	}
	return ""
}

func writeError(w http.ResponseWriter, name string, err error) {
	var ce *Error
	if !errors.As(err, &ce) {
		// 想定外のエラーは中身をクライアントに漏らさない（JS SDK と同じ）。
		log.Printf("%s: 未処理のエラー: %v", name, err)
		ce = &Error{Code: Internal, Message: "INTERNAL"}
	}

	status, ok := httpStatus[ce.Code]
	if !ok {
		status = 500
	}

	payload := map[string]any{
		"status":  string(ce.Code),
		"message": ce.Message,
	}
	if ce.Details != nil {
		payload["details"] = ce.Details
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(map[string]any{"error": payload})
}
