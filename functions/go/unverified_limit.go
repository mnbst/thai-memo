package function

import (
	"context"
	"errors"
	"log"

	"cloud.google.com/go/firestore"

	"github.com/mnbst/thai-memo/functions/go/internal/callable"
	"github.com/mnbst/thai-memo/functions/go/internal/fbapp"
)

// App Check を通らないリクエストが LLM を呼べる回数（JST の1日あたり）。
//
// App Check を必須にしないのは、Play Integrity が使えない端末（Play の
// リリース前レポートの端末、審査用アカウントの端末、一部の実機）を締め出さないため
// （2026-10 の本番ログで、無効トークンは Android 33人中19人。大半が
// リリース前レポートのロボット）。代わりに回数で絞り、匿名認証で UID を
// 量産して Gemini を叩かれても損害を1日分で止める。
//
// UID は作り直せるので、本当の歯止めは unverifiedDailyTotalMax。
// unverifiedDailyPerUIDMax は1人で全体の枠を食い尽くさないための補助。
// 2026-10 の実績は全体で1日 11〜55回、1人あたり最大8回（ロボット1回分）。
const (
	unverifiedDailyPerUIDMax = 20
	unverifiedDailyTotalMax  = 200
)

// unverifiedLimitCollection は日ごとのカウンター。doc ID は JST の日付。
// クライアントからは読み書きさせない（firestore.rules に match が無い＝拒否）。
const unverifiedLimitCollection = "appcheck_rate_limits"

// limitUnverified は App Check を通らないリクエストを日次の回数上限で絞る。
//
// 上限超えは Unavailable にする。ResourceExhausted だとクライアントが
// 「本日の生成上限」と表示してしまう（acquireQuizLease のコメント参照）。
func limitUnverified(name string, h callable.Handler) callable.Handler {
	return func(ctx context.Context, req *callable.Request) (any, error) {
		// 未ログインはハンドラ側で弾くので数えない。
		if req.AppCheck == callable.AppCheckValid || req.Auth == nil {
			return h(ctx, req)
		}
		if err := reserveUnverifiedCall(ctx, name, req.Auth.UID); err != nil {
			return nil, err
		}
		return h(ctx, req)
	}
}

func reserveUnverifiedCall(ctx context.Context, name, uid string) error {
	db, err := fbapp.Firestore(ctx)
	if err != nil {
		return callable.Errorf(callable.Internal, "INTERNAL")
	}
	day := nowJST().Format("2006-01-02")
	ref := db.Collection(unverifiedLimitCollection).Doc(day)
	err = db.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		total, mine := 0, 0
		snap, err := tx.Get(ref)
		if err != nil && !isNotFoundErr(err) {
			return err
		}
		if err == nil && snap.Exists() {
			data := snap.Data()
			total = intValue(data["total"])
			if uids, ok := data["uids"].(map[string]any); ok {
				mine = intValue(uids[uid])
			}
		}
		if reason := unverifiedLimitReason(total, mine); reason != "" {
			// 全体の上限到達はこの行でアラートにする（terraform の appcheck_unverified_cap）。
			log.Printf("%s: unverified limit reached reason=%s uid=%s day=%s total=%d mine=%d",
				name, reason, uid, day, total, mine)
			return callable.Errorf(callable.Unavailable,
				"ただいま混み合っています。時間をおいてもう一度お試しください")
		}
		return tx.Set(ref, map[string]any{
			"total": firestore.Increment(1),
			"uids":  map[string]any{uid: firestore.Increment(1)},
		}, firestore.MergeAll)
	})
	if err == nil {
		return nil
	}
	var callErr *callable.Error
	if errors.As(err, &callErr) {
		return callErr
	}
	log.Printf("%s: unverified limit check failed uid=%s: %v", name, uid, err)
	return callable.Errorf(callable.Internal, "INTERNAL")
}

// unverifiedLimitReason は上限に達していればその種類（total / uid）を、
// 余裕があれば空文字を返す。total と mine はこの呼び出しを数える前の値。
func unverifiedLimitReason(total, mine int) string {
	if total >= unverifiedDailyTotalMax {
		return "total"
	}
	if mine >= unverifiedDailyPerUIDMax {
		return "uid"
	}
	return ""
}
