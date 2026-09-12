package function

import (
	"context"
	"log"
	"os"
	"time"

	"cloud.google.com/go/firestore"

	"github.com/mnbst/thai-memo/functions/go/internal/callable"
	"github.com/mnbst/thai-memo/functions/go/internal/fbapp"
	"github.com/mnbst/thai-memo/functions/go/internal/subscription"
)

// migrateToLifetime は月額課金中のユーザーを買い切りプランへ無償で移行する。
//
// 買い切り商品を売りつけるのではなく、いま払っている人の subscription に
// lifetime の印を付けるだけ。これで期限切れによる降格の経路（dailyBatch /
// subscriptionStatus / ストア通知）が全て素通りになり、月額の自動更新を
// 止めたあとも premium が残る。
//
// 購入記録（product_id / original_transaction_id）は書き換えない。実際に
// 買ったのは月額であって、履歴を偽ると返金・問い合わせの追跡ができなくなる。
//
// 自動更新の停止はユーザー本人がストアで行う（アプリからは止められない）。
// ここで止まったことにはしないので、案内文言と実装がずれない。
func migrateToLifetime(ctx context.Context, req *callable.Request) (any, error) {
	uid, err := req.RequireAuth()
	if err != nil {
		return nil, err
	}

	// premium はサインイン済みアカウントのみ。verifySubscription と同じ扱い。
	if req.Auth != nil && req.Auth.Token != nil &&
		req.Auth.Token.Firebase.SignInProvider == "anonymous" {
		return nil, callable.Errorf(callable.FailedPrecondition,
			"プレミアムのご利用にはサインインが必要です")
	}

	if time.Now().After(migrationDeadline()) {
		return nil, callable.Errorf(callable.FailedPrecondition,
			"無償移行の受付は終了しました")
	}

	db, err := fbapp.Firestore(ctx)
	if err != nil {
		return nil, err
	}
	userRef := db.Collection("users").Doc(uid)

	var alreadyMigrated bool
	if err := db.RunTransaction(ctx, func(
		ctx context.Context, tx *firestore.Transaction,
	) error {
		alreadyMigrated = false

		snap, err := tx.Get(userRef)
		if err != nil || !snap.Exists() {
			return callable.Errorf(callable.NotFound, "ユーザーが見つかりません")
		}
		data := snap.Data()

		sub, _ := data["subscription"].(map[string]any)
		if subscription.IsLifetime(sub) {
			// 二度押し・再送。すでに移行済みなら成功として返す。
			alreadyMigrated = true
			return nil
		}

		if tier, _ := data["tier"].(string); tier != "premium" {
			return callable.Errorf(callable.FailedPrecondition,
				"移行できるのはプレミアムをご利用中の方だけです")
		}

		// 対象はリリース時点で課金していた方の名簿（doc の目印）に限る。
		//
		// 端末側の「案内済み」フラグは再インストールで消えるので、それだけでは
		// 「月額を1ヶ月買う→入れ直す→無償移行→解約」で 600 円の買い切りが
		// 成立してしまう。名簿はリリース前に立てるので、後から買った人は入らない。
		if eligible, _ := data["lifetime_migration_eligible"].(bool); !eligible {
			return callable.Errorf(callable.FailedPrecondition,
				"無償移行の対象ではありません")
		}

		// 対象はストア購入の課金者に限る。手動付与（platform=manual）や
		// 体験トライアルは「継続してくださっている方」ではない。
		if !subscription.IsStorePlatform(sub["platform"]) {
			return callable.Errorf(callable.FailedPrecondition,
				"ストアでご購入いただいたプランのみ移行できます")
		}
		status, _ := sub["status"].(string)
		switch status {
		case "active", "canceled", "grace_period":
			// 移行できる
		default:
			return callable.Errorf(callable.FailedPrecondition,
				"有効なご契約が見つかりません")
		}

		return tx.Set(userRef, map[string]any{
			"subscription": map[string]any{
				"lifetime": true,
				// 無償移行の記録。買い切りを購入した人と区別できるようにする。
				"lifetime_source":      "monthly_migration",
				"lifetime_migrated_at": firestore.ServerTimestamp,
				"updated_at":           firestore.ServerTimestamp,
			},
		}, firestore.MergeAll)
	}); err != nil {
		return nil, err
	}

	log.Printf("migrateToLifetime: uid=%s already=%t", uid, alreadyMigrated)
	return map[string]any{"status": "ok", "already_migrated": alreadyMigrated}, nil
}

// lifetimeMigrationDeadline は無償移行の受付期限（JST 2026-10-31 23:59:59）。
//
// 案内を出したかどうかの記録は端末側（SharedPreferences）にしかなく、
// 再インストールで消える。サーバーにも期限を置いて「いまなら無料」を実際に
// 有限にしないと、リリース後に月額を買った人がこの callable を直接叩いて
// 永久プレミアムを取れてしまう。
// LIFETIME_MIGRATION_DEADLINE（RFC3339）で上書きできる。
var lifetimeMigrationDeadline = time.Date(2026, 10, 31, 23, 59, 59, 0,
	time.FixedZone("JST", 9*60*60))

func migrationDeadline() time.Time {
	if v := os.Getenv("LIFETIME_MIGRATION_DEADLINE"); v != "" {
		if t, err := time.Parse(time.RFC3339, v); err == nil {
			return t
		}
		log.Printf("LIFETIME_MIGRATION_DEADLINE を解釈できない: %q", v)
	}
	return lifetimeMigrationDeadline
}
