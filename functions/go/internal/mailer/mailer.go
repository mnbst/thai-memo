// Package mailer は Gmail SMTP でプレーンテキストのメールを送る。
//
// JS 版は nodemailer の service:'gmail' を使っていた。nodemailer が暗黙にやっていた
// 件名の RFC2047 エンコードと本文の UTF-8 宣言は、ここでは自前で組む必要がある。
package mailer

import (
	"fmt"
	"mime"
	"net/smtp"
	"strings"
)

// gmailSMTP は nodemailer の service:'gmail' が指すホスト。
// 587 は STARTTLS。net/smtp の Auth は TLS 確立後にしか PLAIN を通さないので、
// StartTLS は smtp.SendMail が内部で行う。
const gmailSMTP = "smtp.gmail.com:587"

// Message は送信内容。すべて UTF-8。
type Message struct {
	FromName string // 表示名（非 ASCII 可）
	From     string // 送信元アドレス（= SMTP 認証ユーザー）
	To       string
	Subject  string
	Body     string
}

// Send は Gmail SMTP でメールを送る。
func Send(m Message, appPassword string) error {
	auth := smtp.PlainAuth("", m.From, appPassword, "smtp.gmail.com")
	if err := smtp.SendMail(gmailSMTP, auth, m.From, []string{m.To}, Build(m)); err != nil {
		return fmt.Errorf("メール送信に失敗: %w", err)
	}
	return nil
}

// Build は RFC5322 のメッセージを組み立てる。
// nodemailer が暗黙にやっていた件名のエンコードと UTF-8 宣言をここで行う。
func Build(m Message) []byte {
	from := m.From
	if m.FromName != "" {
		// 表示名は非 ASCII になりうるので必ずエンコードする。
		from = fmt.Sprintf("%s <%s>", mime.QEncoding.Encode("UTF-8", m.FromName), m.From)
	}

	var b strings.Builder
	b.WriteString("From: " + from + "\r\n")
	b.WriteString("To: " + m.To + "\r\n")
	b.WriteString("Subject: " + mime.QEncoding.Encode("UTF-8", m.Subject) + "\r\n")
	b.WriteString("MIME-Version: 1.0\r\n")
	b.WriteString("Content-Type: text/plain; charset=UTF-8\r\n")
	b.WriteString("Content-Transfer-Encoding: 8bit\r\n")
	b.WriteString("\r\n")
	// 本文の改行は CRLF に正規化する（SMTP のデータ行区切り）。
	b.WriteString(strings.ReplaceAll(strings.ReplaceAll(m.Body, "\r\n", "\n"), "\n", "\r\n"))

	return []byte(b.String())
}
