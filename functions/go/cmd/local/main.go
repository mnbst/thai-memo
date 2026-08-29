// Command local は Cloud Functions のエントリポイントをローカルで起動する。
// デプロイ前の動作確認用（Firestore エミュレータと組み合わせて使う）。
//
//	FIRESTORE_EMULATOR_HOST=localhost:8080 GCLOUD_PROJECT=thai-memo-dev \
//	FUNCTION_TARGET=resetLearningData PORT=8081 go run ./cmd/local
package main

import (
	"log"
	"os"

	"github.com/GoogleCloudPlatform/functions-framework-go/funcframework"

	_ "github.com/mnbst/thai-memo/functions/go"
)

func main() {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}
	if err := funcframework.Start(port); err != nil {
		log.Fatalf("funcframework.Start: %v", err)
	}
}
