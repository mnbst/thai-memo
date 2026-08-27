// Package secrets は GCP Secret Manager からシークレットを読む。
// functions/javascript/src/services/secretManager.ts と
// services/appStoreServer.ts:getSecret の移植。
package secrets

import (
	"context"
	"fmt"
	"strings"
	"sync"
	"time"

	secretmanager "cloud.google.com/go/secretmanager/apiv1"
	"cloud.google.com/go/secretmanager/apiv1/secretmanagerpb"

	"github.com/mnbst/thai-memo/functions/go/internal/fbapp"
)

// ttl はキャッシュの有効期間。
//
// 無期限に持つと、キーを漏洩などでローテートしても、生きているインスタンスが
// 古いキーを使い続けてしまう。Cloud Functions のインスタンスは負荷が続けば
// 1 時間より長く生きる。移植元の Python 版（llm_providers.py）と同じ 1 時間。
const ttl = time.Hour

type entry struct {
	value     string
	fetchedAt time.Time
}

var (
	mu     sync.Mutex
	cache  = map[string]entry{}
	client *secretmanager.Client
)

// Get は secretId の最新バージョンを読む。読んだ値は ttl のあいだ覚える。
//
// 環境変数（secretId を大文字にしてハイフンをアンダースコアへ置換した名前）が
// 設定されていればそちらを優先する。ローカル実行とテストのため。
//
// JS 側は2系統に分かれていて、secretManager.ts（Gemini/OpenAI キー）はこの
// 環境変数フォールバックを持つが、appStoreServer.ts の getSecret は持たない。
// Go 側は前者に揃えた。prod では該当の環境変数を設定していないので実挙動は
// 変わらないが、appstore-* を環境変数で差し替えられる点だけ JS と違う。
func Get(ctx context.Context, secretID string) (string, error) {
	if v := strings.TrimSpace(envOverride(secretID)); v != "" {
		return v, nil
	}

	mu.Lock()
	defer mu.Unlock()

	if e, ok := cache[secretID]; ok && time.Since(e.fetchedAt) < ttl {
		return e.value, nil
	}

	if client == nil {
		c, err := secretmanager.NewClient(ctx)
		if err != nil {
			return "", fmt.Errorf("secret manager クライアントの生成に失敗: %w", err)
		}
		client = c
	}

	name := fmt.Sprintf("projects/%s/secrets/%s/versions/latest",
		fbapp.ProjectID(), secretID)
	res, err := client.AccessSecretVersion(ctx,
		&secretmanagerpb.AccessSecretVersionRequest{Name: name})
	if err != nil {
		return "", fmt.Errorf("%s を読めない: %w", secretID, err)
	}

	value := string(res.Payload.Data)
	if value == "" {
		return "", fmt.Errorf("Secret %s is empty", secretID)
	}
	cache[secretID] = entry{value: value, fetchedAt: time.Now()}
	return value, nil
}
