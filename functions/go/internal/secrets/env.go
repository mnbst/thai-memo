package secrets

import (
	"os"
	"strings"
)

// envOverride は secretId に対応する環境変数の値。
// 例: "gmail-app-password" -> GMAIL_APP_PASSWORD
func envOverride(secretID string) string {
	return os.Getenv(strings.ToUpper(strings.ReplaceAll(secretID, "-", "_")))
}
