package function

import (
	"context"
	"log"
	"os"
	"time"

	"cloud.google.com/go/firestore"

	"github.com/mnbst/thai-memo/functions/go/internal/callable"
	"github.com/mnbst/thai-memo/functions/go/internal/fbapp"
	"github.com/mnbst/thai-memo/functions/go/internal/quota"
	"github.com/mnbst/thai-memo/functions/go/internal/subscription"
)

// migrateToLifetime は月額を購入した（している）ユーザーを買い切りプランへ
// 無償で移行する。対象はリリース時点の課金者に加えて、過去に月額を買って
// いまは切れている方も含む。
//
// 買い切り商品を売りつけるのではなく、払ってくださった人の subscription に
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

		// 対象はリリース時点の名簿（doc の目印）に限る。いま課金中の方に加えて、
		// 過去に月額を購入した履歴のある方（解約・期限切れ済み）も含む。
		//
		// 端末側の「案内済み」フラグは再インストールで消えるので、それだけでは
		// 「月額を1ヶ月買う→入れ直す→無償移行→解約」で 600 円の買い切りが
		// 成立してしまう。名簿はリリース前に立てるので、後から買った人は入らない。
		// tier は見ない。期限切れの方は free に落ちているが、それは名簿に
		// 載っている以上「過去に払ってくださった方」であることと矛盾しない。
		if eligible, _ := data["lifetime_migration_eligible"].(bool); !eligible {
			return callable.Errorf(callable.FailedPrecondition,
				"無償移行の対象ではありません")
		}

		// 見るのは「ストアで買った記録があるか」だけ。subscription は
		// verifySubscription がストア検証を通ったときにだけ書くので、
		// platform がストアなら購入履歴があるということ。status（active /
		// canceled / expired …）は問わない。過去に買って切れている方も対象。
		// 手動付与（platform=manual）や体験トライアルはここで外れる。
		if !subscription.IsStorePlatform(sub["platform"]) {
			return callable.Errorf(callable.FailedPrecondition,
				"ストアでのご購入履歴が見つかりません")
		}

		payload := map[string]any{
			// 期限切れの方は free に落ちているので、ここで premium へ戻す。
			// 以後は lifetime の印が期限切れ判定を素通りさせる。
			"tier": "premium",
			"subscription": map[string]any{
				"lifetime": true,
				// 無償移行の記録。買い切りを購入した人と区別できるようにする。
				"lifetime_source":      "monthly_migration",
				"lifetime_migrated_at": firestore.ServerTimestamp,
				"updated_at":           firestore.ServerTimestamp,
			},
		}
		// free から戻した人は回数も premium にしておく。次の日次リセットまで
		// free の残数のままだと、移行した直後に使えない時間ができる
		//（verifySubscription の昇格と同じ扱い）。
		if tier, _ := data["tier"].(string); tier != "premium" {
			payload["remaining_sentences"] = quota.PremiumDailySentences
			payload["remaining_quizzes"] = quota.PremiumDailyQuizzes
		}

		return tx.Set(userRef, payload, firestore.MergeAll)
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
