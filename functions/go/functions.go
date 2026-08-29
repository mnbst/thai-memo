// Package function は Cloud Functions (2nd gen, go1xx ランタイム) のエントリポイントを
// 登録する。gcloud functions deploy の --entry-point にここで登録した名前を渡す。
//
// デプロイ（例）:
//
//	gcloud functions deploy resetLearningData \
//	  --gen2 --runtime=go126 --region=asia-northeast1 \
//	  --source=functions/go --entry-point=resetLearningData \
//	  --trigger-http --allow-unauthenticated
//
// 2nd gen は https://<region>-<project>.cloudfunctions.net/<name> の URL を保つので、
// JS/Python から Go へ差し替えてもクライアント（cloud_functions プラグイン）は無改修。
package function

import (
	"log"
	"net/http"

	"github.com/GoogleCloudPlatform/functions-framework-go/functions"

	"github.com/mnbst/thai-memo/functions/go/internal/callable"
	"github.com/mnbst/thai-memo/functions/go/internal/fbapp"
)

func init() {
	registerCallable("resetLearningData", resetLearningData)
	registerCallable("updateUvm", updateUvm)
	registerCallable("setUserTier", setUserTier)
	registerCallable("sendContactEmail", sendContactEmail)
	registerCallable("verifySubscription", verifySubscription)
	registerCallable("generateQuiz", generateQuiz)
	registerCallable("generateLearningQuiz", generateLearningQuiz)
	registerCallable("generateThaiSentence", generateThaiSentence)

	// 定期実行のバッチ。HTTP トリガーのままにして、tester/prod では
	// Cloud Scheduler が OIDC トークン付きで叩く（Terraform 管理）。
	functions.HTTP("subscriptionStatus", subscriptionStatusHTTP)
	functions.HTTP("dailyBatch", dailyBatchHTTP)
	functions.HTTP("deliverDailySentence", deliverDailySentenceHTTP)

	// Apple からのサーバー間通知（App Store Server Notifications V2）。
	functions.HTTP("handleAppStoreNotification", handleAppStoreNotificationHTTP)

	// Pub/Sub トリガー（Google Play RTDN）。
	functions.CloudEvent("handlePlayNotification", handlePlayNotificationEvent)
}

// registerCallable は callable ハンドラを functions-framework に登録する。
//
// ID token の検証クライアントはリクエスト到着時に作る。init() で作ると
// デプロイ時のビルド検証（コンテナ起動チェック）で認証情報を引きに行ってしまう。
func registerCallable(name string, h callable.Handler) {
	functions.HTTP(name, func(w http.ResponseWriter, r *http.Request) {
		verifier, err := fbapp.Auth(r.Context())
		if err != nil {
			log.Printf("%s: auth クライアントを用意できない: %v", name, err)
			http.Error(w, `{"error":{"status":"INTERNAL","message":"INTERNAL"}}`,
				http.StatusInternalServerError)
			return
		}
		callable.HTTP(name, verifier, h).ServeHTTP(w, r)
	})
}
