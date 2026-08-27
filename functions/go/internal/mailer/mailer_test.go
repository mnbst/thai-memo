package mailer

import (
	"mime"
	"strings"
	"testing"
)

func TestBuildEncodesNonASCIIHeaders(t *testing.T) {
	raw := string(Build(Message{
		FromName: "まいにちタイ語",
		From:     "sender@example.com",
		To:       "to@example.com",
		Subject:  "【お問い合わせ】山田様より",
		Body:     "お名前: 山田\n\n--- メッセージ ---\nこんにちは",
	}))

	head, body, ok := strings.Cut(raw, "\r\n\r\n")
	if !ok {
		t.Fatal("ヘッダと本文が空行で区切られていない")
	}

	// ヘッダに生の非 ASCII が残っていると受信側で化ける。
	for _, line := range strings.Split(head, "\r\n") {
		for _, r := range line {
			if r > 127 {
				t.Fatalf("ヘッダに生の非ASCIIが残っている: %q", line)
			}
		}
	}

	dec := new(mime.WordDecoder)
	subject := headerValue(t, head, "Subject")
	got, err := dec.DecodeHeader(subject)
	if err != nil {
		t.Fatal(err)
	}
	if got != "【お問い合わせ】山田様より" {
		t.Fatalf("Subject = %q", got)
	}

	from := headerValue(t, head, "From")
	if !strings.HasSuffix(from, "<sender@example.com>") {
		t.Fatalf("From = %q", from)
	}
	if name, err := dec.DecodeHeader(strings.TrimSpace(
		strings.TrimSuffix(from, "<sender@example.com>"))); err != nil || name != "まいにちタイ語" {
		t.Fatalf("From の表示名 = %q (err=%v)", name, err)
	}

	if !strings.Contains(head, "Content-Type: text/plain; charset=UTF-8") {
		t.Fatalf("charset 宣言が無い:\n%s", head)
	}

	// 本文の改行はすべて CRLF になっているはず。
	if strings.Contains(strings.ReplaceAll(body, "\r\n", ""), "\n") {
		t.Fatal("本文に裸の LF が残っている")
	}
	if !strings.Contains(body, "こんにちは") {
		t.Fatalf("本文が欠けている: %q", body)
	}
}

func headerValue(t *testing.T, head, name string) string {
	t.Helper()
	for _, line := range strings.Split(head, "\r\n") {
		if v, ok := strings.CutPrefix(line, name+": "); ok {
			return v
		}
	}
	t.Fatalf("ヘッダ %s が無い", name)
	return ""
}

func TestUTF16LengthMatchesJS(t *testing.T) {
	// JS の String#length は UTF-16 コードユニット数。
	// 絵文字（サロゲートペア）は 2 と数える。
	cases := map[string]int{
		"abc": 3,
		"あいう": 3,
		"👍":   2,
		"a👍b": 4,
	}
	for s, want := range cases {
		if got := utf16LenForTest(s); got != want {
			t.Errorf("utf16Len(%q) = %d, want %d", s, got, want)
		}
	}
}

// utf16LenForTest は send_contact_email.go の utf16Len と同じ実装。
// パッケージが別なのでここに写している（実装を変えたら両方直すこと）。
func utf16LenForTest(s string) int {
	n := 0
	for _, r := range s {
		if r > 0xFFFF {
			n += 2
		} else {
			n++
		}
	}
	return n
}
