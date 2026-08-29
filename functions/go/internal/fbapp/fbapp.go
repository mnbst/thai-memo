// Package fbapp は Firebase Admin SDK のクライアントを遅延生成して使い回す。
//
// Cloud Functions のインスタンスは複数リクエストを跨いで生きるので、
// Firestore/Auth クライアントは1度だけ作る。init() で作らないのは、
// コールドスタート時に不要なクライアントの生成コストを払わないため。
package fbapp

import (
	"context"
	"fmt"
	"os"
	"sync"

	"cloud.google.com/go/firestore"
	firebase "firebase.google.com/go/v4"
	"firebase.google.com/go/v4/auth"
	"firebase.google.com/go/v4/messaging"
)

var (
	appOnce sync.Once
	app     *firebase.App
	appErr  error

	fsOnce sync.Once
	fsCli  *firestore.Client
	fsErr  error

	authOnce sync.Once
	authCli  *auth.Client
	authErr  error

	msgOnce sync.Once
	msgCli  *messaging.Client
	msgErr  error
)

// ProjectID は実行環境が示すプロジェクト ID。
// 2nd gen では FIREBASE_CONFIG が無いことがあるので、index.ts と同じ順で見る。
func ProjectID() string {
	for _, k := range []string{"GCLOUD_PROJECT", "GCP_PROJECT", "GOOGLE_CLOUD_PROJECT"} {
		if v := os.Getenv(k); v != "" {
			return v
		}
	}
	return ""
}

// App は Firebase App を返す。
func App(ctx context.Context) (*firebase.App, error) {
	appOnce.Do(func() {
		cfg := &firebase.Config{ProjectID: ProjectID()}
		app, appErr = firebase.NewApp(ctx, cfg)
		if appErr != nil {
			appErr = fmt.Errorf("firebase の初期化に失敗: %w", appErr)
		}
	})
	return app, appErr
}

// Firestore は Firestore クライアントを返す。
func Firestore(ctx context.Context) (*firestore.Client, error) {
	fsOnce.Do(func() {
		a, err := App(ctx)
		if err != nil {
			fsErr = err
			return
		}
		fsCli, fsErr = a.Firestore(ctx)
		if fsErr != nil {
			fsErr = fmt.Errorf("firestore クライアントの生成に失敗: %w", fsErr)
		}
	})
	return fsCli, fsErr
}

// Auth は Auth クライアントを返す。callable の ID token 検証に使う。
func Auth(ctx context.Context) (*auth.Client, error) {
	authOnce.Do(func() {
		a, err := App(ctx)
		if err != nil {
			authErr = err
			return
		}
		authCli, authErr = a.Auth(ctx)
		if authErr != nil {
			authErr = fmt.Errorf("auth クライアントの生成に失敗: %w", authErr)
		}
	})
	return authCli, authErr
}

// Messaging は FCM クライアントを返す。毎日例文の通知送信に使う。
func Messaging(ctx context.Context) (*messaging.Client, error) {
	msgOnce.Do(func() {
		a, err := App(ctx)
		if err != nil {
			msgErr = err
			return
		}
		msgCli, msgErr = a.Messaging(ctx)
		if msgErr != nil {
			msgErr = fmt.Errorf("messaging クライアントの生成に失敗: %w", msgErr)
		}
	})
	return msgCli, msgErr
}
