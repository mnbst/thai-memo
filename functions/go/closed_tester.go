package function

import (
	"context"
	"log"
	"strings"
	"time"

	"cloud.google.com/go/firestore"

	"github.com/mnbst/thai-memo/functions/go/internal/callable"
	"github.com/mnbst/thai-memo/functions/go/internal/premium"
	"github.com/mnbst/thai-memo/functions/go/internal/quota"
)

// Google Play のクローズドテストに参加したテスターへの特典。
//
// Play からは「クローズドテストから入れた人か」を判別できないので、Play Console の
// テスターリストと同じメールアドレスを closed_testers/{メールアドレス小文字} に置き、
// ログイン中のメールアドレスと突き合わせる。一致したら users doc に closed_tester を
// 立て（集計でテスターを抜き出す印）、プレミアム体験を配る。
//
// 体験は新規ユーザー向けと同じ premium_trial_expires_at を使う。実効プレミアムの判定
// （premium.IsEffectivePremium）とアプリの体験表示がそのまま効く。
const (
	closedTestersCollection = "closed_testers"
	closedTesterTrialDays   = 14
)

// tokenEmail は検証済みトークンのメールアドレス（小文字）。未確認のアドレスは
// 本人のものと限らないので使わない。
func tokenEmail(a *callable.Auth) string {
	if a == nil || a.Token == nil {
		return ""
	}
	if verified, _ := a.Token.Claims["email_verified"].(bool); !verified {
		return ""
	}
	email, _ := a.Token.Claims["email"].(string)
	return strings.ToLower(strings.TrimSpace(email))
}

// grantClosedTesterTrial はテスターリストに載った人に、一度だけプレミアム体験を配る。
//
// 14日は付与した時（リストに載ったあと最初に生成・語彙テストを呼んだ時）から数える。
// 付与済み（closed_tester あり）なら何もしない。リストに無い人は毎回1読み増えるだけ。
// 戻り値は userData へ重ねるための書き込み内容（削除したキーは含まない）。
func grantClosedTesterTrial(
	ctx context.Context, db *firestore.Client, userRef *firestore.DocumentRef,
	userData map[string]any, email string, now time.Time,
) (map[string]any, error) {
	if email == "" {
		return nil, nil
	}
	if _, done := userData["closed_tester"]; done {
		return nil, nil
	}
	listed, err := db.Collection(closedTestersCollection).Doc(email).Get(ctx)
	if isNotFoundErr(err) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	if !listed.Exists() {
		return nil, nil
	}

	grant := map[string]any{
		"closed_tester":            true,
		"closed_tester_granted_at": now.UTC(),
		// 体験中は premium と同じ回数を出す（grantLegacyTrial と同じ）。
		"remaining_sentences": quota.PremiumDailySentences,
		"remaining_quizzes":   quota.PremiumDailyQuizzes,
		"premium_trial_expires_at": time.UnixMilli(
			premium.TrialExpiresAtMsFrom(now.UnixMilli(), closedTesterTrialDays)).UTC(),
	}
	result := map[string]any{}
	err = db.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		result = map[string]any{}
		snap, err := tx.Get(userRef)
		if err != nil && !isNotFoundErr(err) {
			return err
		}
		if err == nil && snap.Exists() {
			if _, done := snap.Data()["closed_tester"]; done {
				return nil
			}
		}
		result = grant
		write := map[string]any{
			// 以前の体験の終了印が残っていると、この体験の終わりに終了の案内が出ない。
			"premium_trial_ended_at": firestore.Delete,
		}
		for k, v := range grant {
			write[k] = v
		}
		return tx.Set(userRef, write, firestore.MergeAll)
	})
	if err != nil {
		return nil, err
	}
	if len(result) > 0 {
		log.Printf("Closed tester trial granted for user %s", userRef.ID)
	}
	return result, nil
}

// applyClosedTesterTrial は付与して userData に反映する。付与に失敗しても本処理は
// 止めない（特典の付与漏れは次の呼び出しで取り戻せる）。
func applyClosedTesterTrial(
	ctx context.Context, db *firestore.Client, userRef *firestore.DocumentRef,
	userData map[string]any, a *callable.Auth, now time.Time,
) {
	granted, err := grantClosedTesterTrial(ctx, db, userRef, userData, tokenEmail(a), now)
	if err != nil {
		log.Printf("closed tester trial: uid=%s error=%v", userRef.ID, err)
		return
	}
	if len(granted) == 0 {
		return
	}
	for k, v := range granted {
		userData[k] = v
	}
	delete(userData, "premium_trial_ended_at")
}
