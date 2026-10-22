package dailysentence

import (
	"fmt"
	"strings"

	"github.com/mnbst/thai-memo/functions/go/internal/lang"
)

// 通知タイトルの言語別テンプレート。本文は例文そのもの（タイ文・発音・訳）なので
// 訳文の言語で決まるが、タイトルはサーバー側の文言なのでここで出し分ける。
//
// 「今日のタイ語」は1日1回を思わせ、1日に何度も届く premium の配信と
// 食い違うので使わない。キーワードがあればそれから始める。
var notificationTitle = map[lang.Lang]struct{ plain, wordOnly, withWord string }{
	lang.JA: {"🇹🇭 タイ語の例文", "🇹🇭 %s", "🇹🇭 %s（%s）"},
	lang.EN: {"🇹🇭 Thai practice", "🇹🇭 %s", "🇹🇭 %s (%s)"},
	lang.KO: {"🇹🇭 태국어 예문", "🇹🇭 %s", "🇹🇭 %s (%s)"},
}

// セット配信のときにタイトルへ添える本数。1本目の key_word しか本文に出ないので、
// 「今日は何本届いたか」はここでしか伝わらない。
// 残り本数（withWord）と総数（plain）で数え方が変わることに注意。
var notificationSetSuffix = map[lang.Lang]struct{ plain, withWord string }{
	lang.JA: {" · %d本", " ほか%d本"},
	lang.EN: {" · %d sentences", " +%d more"},
	lang.KO: {" · %d문장", " 외 %d문장"},
}

// BuildNotificationText は通知のタイトルと本文を組み立てる。
//
// タイ文字だけだと何の通知か判別しづらいので、タイトルにキーワードと
// その意味を載せて「新しい例文が届いた」と一目で分かるようにする。
// 本文は タイ文 / 発音 / 訳 の3行。3行は並列な項目ではなく1つの例文の3側面なので、
// 同じ記号を並べず、発音は括弧・訳は矢印で役割を書き分ける。
// 発音が無い例文もあるので行ごとに省く。
// setSize が2以上（5本セット配信）なら本数をタイトルに添える。
// daily_sentence_handlers.py:build_notification_text:219 の移植。
func BuildNotificationText(
	sentence map[string]any, setSize int, l lang.Lang,
) (title, body string) {
	tmpl, ok := notificationTitle[l]
	if !ok {
		tmpl = notificationTitle[lang.JA]
	}
	suffix, ok := notificationSetSuffix[l]
	if !ok {
		suffix = notificationSetSuffix[lang.JA]
	}

	keyWord := trimmedField(sentence, "key_word")
	meaning := trimmedField(sentence, "key_word_meaning")
	switch {
	case keyWord != "" && meaning != "":
		title = fmt.Sprintf(tmpl.withWord, keyWord, meaning)
	case keyWord != "":
		title = fmt.Sprintf(tmpl.wordOnly, keyWord)
	default:
		title = tmpl.plain
	}
	if setSize > 1 {
		if keyWord != "" {
			title += fmt.Sprintf(suffix.withWord, setSize-1)
		} else {
			title += fmt.Sprintf(suffix.plain, setSize)
		}
	}

	lines := make([]string, 0, 3)
	if thai := trimmedField(sentence, "thai_text"); thai != "" {
		lines = append(lines, thai)
	}
	if pron := trimmedField(sentence, "pronunciation"); pron != "" {
		lines = append(lines, "（"+pron+"）")
	}
	if tr := trimmedField(sentence, "japanese_translation"); tr != "" {
		lines = append(lines, "→ "+tr)
	}
	return title, strings.Join(lines, "\n")
}

func trimmedField(m map[string]any, key string) string {
	s, _ := m[key].(string)
	return strings.TrimSpace(s)
}
