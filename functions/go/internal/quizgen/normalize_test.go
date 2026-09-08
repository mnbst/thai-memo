package quizgen

import "testing"

// TestBlankKeepsWordBoundary は長い語の内側を空欄にしないことを見る。
// 例: เวลา（weelaa）の中の ลา（laa）。
func TestBlankKeepsWordBoundary(t *testing.T) {
	seed := QuizSentenceSeed{
		ThaiText:             "ผมมีเวลาลาพักร้อน",
		Words:                []string{"ผม", "มี", "เวลา", "ลา", "พักร้อน"},
		KeyWord:              "ลา",
		KeyWordPronunciation: "laa",
	}

	got := PrepareInputs([]QuizSentenceSeed{seed})[0]
	if want := "ผมมีเวลา___พักร้อน"; got.BlankText != want {
		t.Errorf("BlankText = %q, want %q", got.BlankText, want)
	}
}

// TestBlankSkippedWhenNotAWord は key_word が語として本文に無いとき、
// 部分一致で空欄を作らない（その例文を出題に使わない）ことを見る。
func TestBlankSkippedWhenNotAWord(t *testing.T) {
	seed := QuizSentenceSeed{
		ThaiText: "ผมมีเวลา",
		Words:    []string{"ผม", "มี", "เวลา"},
		KeyWord:  "ลา",
	}

	if IsSeedReady(seed) {
		t.Errorf("語の途中を空欄にして出題可能と判定した: %+v",
			PrepareInputs([]QuizSentenceSeed{seed})[0])
	}
}

// TestBlankSpansMultipleWords は ๆ のように分解が分かれる key_word でも
// 語の境界に揃えば空欄にできることを見る。
func TestBlankSpansMultipleWords(t *testing.T) {
	seed := QuizSentenceSeed{
		ThaiText: "เดินเร็วๆนะ",
		Words:    []string{"เดิน", "เร็ว", "ๆ", "นะ"},
		KeyWord:  "เร็วๆ",
	}

	got := PrepareInputs([]QuizSentenceSeed{seed})[0]
	if want := "เดิน___นะ"; got.BlankText != want {
		t.Errorf("BlankText = %q, want %q", got.BlankText, want)
	}
}

// TestBlankWithSpaces は本文・key_word のどこにスペースが入っても
// 語として突き合わせられ、本文のスペースは残ることを見る。
func TestBlankWithSpaces(t *testing.T) {
	for _, tc := range []struct{ name, thaiText, keyWord, want string }{
		{"語の前後にスペース", "เดิน เร็ว นะ", "เร็ว", "เดิน ___ นะ"},
		{"文頭にスペース", " เร็วนะ", "เร็ว", " ___นะ"},
		{"文末にスペース", "เดิน เร็ว ", "เร็ว", "เดิน ___ "},
		{"key_word の途中にスペース", "เดินเร็ว ๆนะ", "เร็วๆ", "เดิน___นะ"},
		{"key_word 側だけスペース", "เดินเร็วๆนะ", "เร็ว ๆ", "เดิน___นะ"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			seed := QuizSentenceSeed{
				ThaiText: tc.thaiText,
				Words:    []string{"เดิน", "เร็ว", "ๆ", "นะ"},
				KeyWord:  tc.keyWord,
			}
			got, ok := buildBlankText(seed.ThaiText, seed.KeyWord, seed.Words)
			if !ok || got != tc.want {
				t.Errorf("BlankText = %q (ok=%v), want %q", got, ok, tc.want)
			}
		})
	}
}

// TestBlankFallsBackWithoutWords は word_breakdown が無い・本文とずれている
// ときは従来どおり部分一致で空欄を作ることを見る。
func TestBlankFallsBackWithoutWords(t *testing.T) {
	for name, words := range map[string][]string{
		"語なし":   nil,
		"本文とずれ": {"ผม", "ไม่มีคำนี้"},
	} {
		t.Run(name, func(t *testing.T) {
			seed := QuizSentenceSeed{
				ThaiText: "ผมมีเวลา", Words: words, KeyWord: "มี",
			}
			got := PrepareInputs([]QuizSentenceSeed{seed})[0]
			if want := "ผม___เวลา"; got.BlankText != want {
				t.Errorf("BlankText = %q, want %q", got.BlankText, want)
			}
		})
	}
}

// TestBlankSentencePronunciationKeepsWordBoundary は発音側でも
// 語の途中（weelaa の laa）を空欄にしないことを見る。
func TestBlankSentencePronunciationKeepsWordBoundary(t *testing.T) {
	for _, tc := range []struct {
		name              string
		sentence, keyWord string
		want              string
	}{
		{"語の途中は空欄にしない", "phǒm mii weelaa", "laa", ""},
		{"語として合えば空欄にする", "phǒm mii weelaa laa", "laa", "phǒm mii weelaa ___"},
		{"複数語の発音も合わせる", "phǒm kin khâao phàt", "khâao phàt", "phǒm kin ___"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			got := BuildBlankSentencePronunciation(tc.sentence, tc.keyWord)
			if got != tc.want {
				t.Errorf("= %q, want %q", got, tc.want)
			}
		})
	}
}
