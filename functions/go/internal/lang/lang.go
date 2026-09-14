// Package lang は訳文・解説の言語（app_language）の正規化。
// functions/javascript/src/utils/lang.ts の移植。
// Python 側の constants.resolve_lang と同じ規則にすること。
package lang

import "strings"

// Lang は対応言語。
type Lang string

const (
	JA Lang = "ja"
	EN Lang = "en"

	// Default は既定言語。
	Default = JA
)

// Resolve はリクエストの lang を対応言語に正規化する。
//
// lang を送らない旧クライアントは ja になる（後方互換）。未知の値も ja に倒す。
// 日本語ユーザーに英語の解説が返る事故のほうが、既定言語のまま返すより害が大きい。
func Resolve(value any) Lang {
	s, ok := value.(string)
	if !ok {
		return Default
	}
	switch Lang(strings.ToLower(strings.TrimSpace(s))) {
	case JA:
		return JA
	case EN:
		return EN
	}
	return Default
}

// Parse は保存済みの値を対応言語として読む。
//
// Resolve と違い既定へ倒さない。未知・空なら ok=false を返す。
// 「言語が分からない doc」と「ja の doc」を区別したい側（例文プールの
// 振り分け）が使う。取り違えると訳文の言語が混ざる。
func Parse(s string) (Lang, bool) {
	switch Lang(strings.ToLower(strings.TrimSpace(s))) {
	case JA:
		return JA, true
	case EN:
		return EN, true
	}
	return "", false
}
