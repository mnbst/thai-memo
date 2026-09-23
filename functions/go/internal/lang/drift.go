package lang

import (
	"strings"
	"unicode"
)

// モデルは稀に指定と違う言語で書く（2026-09、ja のクイズ解説が韓国語で出た）。
// プロンプトとスキーマの description では塞ぎきれないので、出力側で見つける。
//
// 見るのは「その言語ならまず出ない文字」だけ。タイ語とローマ字はどの言語の
// 出力にも混ざるので判定に使わない。

// hanOnlyThreshold は「仮名が無い日本語」を誤りと見なす、漢字の連続長。
//
// 語義は「猫」「水」のように漢字だけで正しいことがある。文の長さになっても
// 仮名が1文字も無いのは日本語ではない（中国語へのドリフト）。
//
// 数えるのは通算ではなく連続した並びの最長。「私（男性一人称）」のように
// 括弧や読点で区切られた語義を中国語と誤検知しない（2026-09、ผม の語義が
// 毎回ここで弾かれ、書き直しも直らず文ごと再生成になっていた）。
const hanOnlyThreshold = 8

// latinWordThreshold は、JA 欄を明らかな英文とみなすラテン語数。
// "LINE" や "OpenAI" のような固有名詞・略語だけの値は誤検出せず、
// "Thank you" のような短い英文は拾う。
const latinWordThreshold = 2

// IsWrongLanguage は text が l の言語で書かれていないか。空なら false。
func IsWrongLanguage(text string, l Lang) bool {
	if strings.TrimSpace(text) == "" {
		return false
	}
	hasKana, hasLetter := false, false
	hanRunMax, hanRun, latin, latinWords := 0, 0, 0, 0
	inLatinWord := false
	for _, r := range text {
		if unicode.IsLetter(r) {
			hasLetter = true
		}
		switch {
		case unicode.Is(unicode.Hangul, r), unicode.Is(unicode.Cyrillic, r):
			return true
		case unicode.Is(unicode.Hiragana, r), unicode.Is(unicode.Katakana, r):
			if l == EN {
				return true
			}
			hanRun = 0
			hasKana = true
		case unicode.Is(unicode.Han, r):
			if l == EN {
				return true
			}
			hanRun++
			if hanRun > hanRunMax {
				hanRunMax = hanRun
			}
		case unicode.Is(unicode.Latin, r):
			hanRun = 0
			latin++
			if !inLatinWord {
				latinWords++
			}
			inLatinWord = true
		default:
			hanRun = 0
			inLatinWord = false
		}
	}
	if l == EN {
		// タイ語だけなど、英字を1文字も含まない説明・訳文も弾く。
		return hasLetter && latin == 0
	}
	if hasKana {
		return false
	}
	if hanRunMax >= hanOnlyThreshold ||
		(hanRunMax == 0 && latinWords >= latinWordThreshold) {
		return true
	}
	// 日本語文字もラテン文字も無い文字列（タイ語だけなど）。
	return hasLetter && hanRunMax == 0 && latin == 0
}

// AnyWrongLanguage は1つでも l で書かれていない文字列があるか。
func AnyWrongLanguage(l Lang, texts ...string) bool {
	for _, text := range texts {
		if IsWrongLanguage(text, l) {
			return true
		}
	}
	return false
}
