package function

import (
	"strings"
	"testing"
)

func TestContactMail(t *testing.T) {
	t.Run("メールアドレスありはユーザーIDを含める", func(t *testing.T) {
		subject, body := contactMail("太郎", "a@example.com", "uid1", "本文")
		if subject != "【お問い合わせ】太郎様より" {
			t.Errorf("subject = %q", subject)
		}
		for _, want := range []string{"お名前: 太郎", "メールアドレス: a@example.com", "ユーザーID: uid1", "本文"} {
			if !strings.Contains(body, want) {
				t.Errorf("body に %q がない: %q", want, body)
			}
		}
	})
	t.Run("メールアドレスなしは匿名でユーザーIDを含めない", func(t *testing.T) {
		subject, body := contactMail("", "", "uid1", "本文")
		if subject != "【ご意見】匿名" {
			t.Errorf("subject = %q", subject)
		}
		if strings.Contains(body, "uid1") {
			t.Errorf("匿名なのにユーザーIDが入っている: %q", body)
		}
		if !strings.Contains(body, "お名前: 匿名") || !strings.Contains(body, "本文") {
			t.Errorf("body = %q", body)
		}
	})
}
