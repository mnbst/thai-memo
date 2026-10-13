package function

import (
	"context"
	"log"
	"os"
	"strings"
	"time"

	"cloud.google.com/go/firestore"

	"github.com/mnbst/thai-memo/functions/go/internal/callable"
	"github.com/mnbst/thai-memo/functions/go/internal/fbapp"
	"github.com/mnbst/thai-memo/functions/go/internal/premium"
	"github.com/mnbst/thai-memo/functions/go/internal/quota"
)

// Google Play のクローズドテストに参加したテスターへの特典。
//
// 対象は次のどちらか。当てはまれば users doc に closed_tester を立て（集計で
// テスターを抜き出す印）、プレミアム体験を配る。
//   - 製品版の公開前に Android アプリから呼んだ人。公開前の本番アプリは
//     テスターしか入れられないので、App Check で Android アプリと確かめられれば
//     テスターとみなす。期間は CLOSED_TEST_AUTO_GRANT_UNTIL（RFC3339）まで。
//     未設定なら自動では配らない。製品版を公開したら外すこと。
//   - closed_testers/{メールアドレス小文字} に載っている人（手で配る経路）。
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

// closedTestAutoGrantUntil は Android アプリへ自動で配る期限。未設定・解釈できない
// ときはゼロ値（自動では配らない）。
func closedTestAutoGrantUntil() time.Time {
	v := os.Getenv("CLOSED_TEST_AUTO_GRANT_UNTIL")
	if v == "" {
		return time.Time{}
	}
	t, err := time.Parse(time.RFC3339, v)
	if err != nil {
		log.Printf("CLOSED_TEST_AUTO_GRANT_UNTIL を解釈できない: %q", v)
		return time.Time{}
	}
	return t
}

// grantClosedTesterTrial はテスターに、一度だけプレミアム体験を配る。
//
// 14日は付与した時（対象になったあと最初に claimClosedTesterTrial を呼んだ時）から数える。
// 付与済み（closed_tester あり）なら何もしない。Android 以外でリストに無い人は
// 毎回1読み増えるだけ。戻り値は userData へ重ねるための書き込み内容（削除した
// キーは含まない）。
func grantClosedTesterTrial(
	ctx context.Context, db *firestore.Client, userRef *firestore.DocumentRef,
	userData map[string]any, email string, android bool, now time.Time,
) (map[string]any, error) {
	if _, done := userData["closed_tester"]; done {
		return nil, nil
	}
	source := ""
	if android && now.Before(closedTestAutoGrantUntil()) {
		source = "android"
	} else if email != "" {
		listed, err := db.Collection(closedTestersCollection).Doc(email).Get(ctx)
		if err != nil && !isNotFoundErr(err) {
			return nil, err
		}
		if err == nil && listed.Exists() {
			source = "list"
		}
	}
	if source == "" {
		return nil, nil
	}

	grant := map[string]any{
		"closed_tester":            true,
		"closed_tester_granted_at": now.UTC(),
		"closed_tester_source":     source,
		// 体験中は premium と同じ回数を出す（grantLegacyTrial と同じ）。
		"remaining_sentences": quota.PremiumDailySentences,
		"remaining_quizzes":   quota.PremiumDailyQuizzes,
		"premium_trial_expires_at": time.UnixMilli(
			premium.TrialExpiresAtMsFrom(now.UnixMilli(), closedTesterTrialDays)).UTC(),
	}
	result := map[string]any{}
	err := db.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
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
		log.Printf("Closed tester trial granted for user %s (%s)", userRef.ID, source)
	}
	return result, nil
}

// claimClosedTesterTrial はテスターの体験を受け取る callable。
//
// アプリは Android で、初回起動の流れの始め（語彙テスト・ペイウォールより前）と
// 起動のたびに呼ぶ。生成や語彙テストのついでに配ると、語彙テストを飛ばした人が
// 配られる前にペイウォールを見てしまう。
//
// 返り値:
//   - granted: 体験を持っている（今回付けた、または付与済み）
//   - active:  自動で配る期間中か。false なら以後アプリは呼ばなくてよい
func claimClosedTesterTrial(ctx context.Context, req *callable.Request) (any, error) {
	uid, err := req.RequireAuth()
	if err != nil {
		return nil, err
	}
	db, err := fbapp.Firestore(ctx)
	if err != nil {
		return nil, err
	}
	now := time.Now()
	userRef := db.Collection("users").Doc(uid)
	data := map[string]any{}
	if snap, err := userRef.Get(ctx); err == nil && snap.Exists() {
		data = snap.Data()
	} else if err != nil && !isNotFoundErr(err) {
		log.Printf("claimClosedTesterTrial: ユーザー doc を読めない: uid=%s error=%v", uid, err)
		return nil, callable.Errorf(callable.Internal, "特典を確認できませんでした")
	}
	if _, err := grantClosedTesterTrial(
		ctx, db, userRef, data, tokenEmail(req.Auth), req.IsAndroidApp(), now); err != nil {
		log.Printf("claimClosedTesterTrial: uid=%s error=%v", uid, err)
		return nil, callable.Errorf(callable.Internal, "特典を確認できませんでした")
	}
	// 付与済みでも、トランザクション内で既に付いていたときは result が空になる。
	// 体験を持っているかは doc を読み直して確かめる。
	granted := false
	if snap, err := userRef.Get(ctx); err == nil && snap.Exists() {
		_, granted = snap.Data()["closed_tester"]
	}
	return map[string]any{
		"granted": granted,
		"active":  now.Before(closedTestAutoGrantUntil()),
	}, nil
}
