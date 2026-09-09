package function

import (
	"context"
	"fmt"
	"log"
	"net/mail"
	"strings"
	"sync"
	"time"

	"cloud.google.com/go/firestore"
	secretmanager "cloud.google.com/go/secretmanager/apiv1"
	"cloud.google.com/go/secretmanager/apiv1/secretmanagerpb"

	"github.com/mnbst/thai-memo/functions/go/internal/callable"
	"github.com/mnbst/thai-memo/functions/go/internal/fbapp"
	"github.com/mnbst/thai-memo/functions/go/internal/mailer"
)

// 問い合わせの宛先。JS 版と同じ。
const (
	contactAddress  = "gcp.demo.776@gmail.com"
	contactFromName = "まいにちタイ語"
	contactMaxLen   = 2000
	contactNameMax  = 100
	contactEmailMax = 320
	contactDailyMax = 5
	contactCooldown = time.Minute
)

var (
	gmailPwOnce sync.Once
	gmailPw     string
	gmailPwErr  error
)

// getGmailAppPassword は Secret Manager から gmail-app-password を読む。
// 値は変わらないので1度だけ取る。
func getGmailAppPassword(ctx context.Context) (string, error) {
	gmailPwOnce.Do(func() {
		client, err := secretmanager.NewClient(ctx)
		if err != nil {
			gmailPwErr = fmt.Errorf("secret manager クライアントの生成に失敗: %w", err)
			return
		}
		defer client.Close()

		name := fmt.Sprintf("projects/%s/secrets/gmail-app-password/versions/latest",
			fbapp.ProjectID())
		res, err := client.AccessSecretVersion(ctx,
			&secretmanagerpb.AccessSecretVersionRequest{Name: name})
		if err != nil {
			gmailPwErr = fmt.Errorf("gmail-app-password を読めない: %w", err)
			return
		}
		gmailPw = string(res.Payload.Data)
		if gmailPw == "" {
			gmailPwErr = fmt.Errorf("gmail-app-password is empty")
		}
	})
	return gmailPw, gmailPwErr
}

// sendContactEmail は functions/javascript/src/sendContactEmail.ts の移植。
func sendContactEmail(ctx context.Context, req *callable.Request) (any, error) {
	uid, err := req.RequireAuth()
	if err != nil {
		return nil, err
	}

	var in struct {
		Name    string `json:"name"`
		Email   string `json:"email"`
		Message string `json:"message"`
	}
	if err := req.Bind(&in); err != nil {
		return nil, err
	}

	if in.Name == "" || in.Email == "" || in.Message == "" {
		return nil, callable.Errorf(callable.InvalidArgument, "必須項目が不足しています")
	}
	if utf16Len(in.Name) > contactNameMax || len(in.Email) > contactEmailMax ||
		strings.ContainsAny(in.Name, "\r\n") {
		return nil, callable.Errorf(callable.InvalidArgument, "お名前またはメールアドレスが不正です")
	}
	parsedAddress, err := mail.ParseAddress(in.Email)
	if err != nil || parsedAddress.Address != in.Email {
		return nil, callable.Errorf(callable.InvalidArgument, "メールアドレスが不正です")
	}
	// JS の String#length は UTF-16 コードユニット数。ルーン数だと絵文字などで
	// 判定がずれるので、同じ数え方に合わせる。
	if utf16Len(in.Message) > contactMaxLen {
		return nil, callable.Errorf(callable.InvalidArgument,
			"メッセージは2000文字以内で入力してください")
	}

	// レート制限の消費は入力検証を全て通してから。先に数えると、サーバー自身が
	// 弾く入力でも日次5回の枠が減り、1分のクールダウンまで始まってしまう。
	if err := reserveContactSend(ctx, uid); err != nil {
		return nil, err
	}

	password, err := getGmailAppPassword(ctx)
	if err != nil {
		log.Printf("sendContactEmail: %v", err)
		return nil, callable.Errorf(callable.Internal, "メール送信に失敗しました")
	}

	body := strings.Join([]string{
		"お名前: " + in.Name,
		"メールアドレス: " + in.Email,
		"ユーザーID: " + uid,
		"",
		"--- メッセージ ---",
		in.Message,
	}, "\n")

	if err := mailer.Send(mailer.Message{
		FromName: contactFromName,
		From:     contactAddress,
		To:       contactAddress,
		Subject:  fmt.Sprintf("【お問い合わせ】%s様より", in.Name),
		Body:     body,
	}, password); err != nil {
		log.Printf("sendContactEmail: %v", err)
		return nil, callable.Errorf(callable.Internal, "メール送信に失敗しました")
	}

	// JS 版は何も返さない（クライアントには result: null が届く）。
	return nil, nil
}

func reserveContactSend(ctx context.Context, uid string) error {
	db, err := fbapp.Firestore(ctx)
	if err != nil {
		return callable.Errorf(callable.Internal, "メール送信を準備できませんでした")
	}
	ref := db.Collection("contact_rate_limits").Doc(uid)
	now := time.Now().UTC()
	day := now.Format("2006-01-02")
	return db.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		count := 0
		snap, err := tx.Get(ref)
		if err == nil && snap.Exists() {
			data := snap.Data()
			if last, ok := data["last_sent_at"].(time.Time); ok && now.Sub(last) < contactCooldown {
				return callable.Errorf(callable.ResourceExhausted, "しばらくしてから再度お試しください")
			}
			if storedDay, _ := data["day"].(string); storedDay == day {
				count = intValue(data["count"])
			}
		} else if err != nil && !isNotFoundErr(err) {
			return err
		}
		if count >= contactDailyMax {
			return callable.Errorf(callable.ResourceExhausted, "本日の送信上限に達しました")
		}
		return tx.Set(ref, map[string]any{
			"day": day, "count": count + 1, "last_sent_at": now,
		}, firestore.MergeAll)
	})
}

// utf16Len は JS の String#length と同じ数え方（UTF-16 コードユニット数）。
func utf16Len(s string) int {
	n := 0
	for _, r := range s {
		if r > 0xFFFF {
			n += 2 // サロゲートペア
		} else {
			n++
		}
	}
	return n
}
