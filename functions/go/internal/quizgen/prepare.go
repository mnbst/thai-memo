package quizgen

import "strings"

func quizFormatOf(sentence QuizSentenceSeed) string {
	if sentence.QuizFormat == FormatMeaningChoice {
		return FormatMeaningChoice
	}
	return FormatClozeChoice
}

// blankTarget は空欄にする語とその読み・意味。
type blankTarget struct {
	Word          string
	Pronunciation string
	Meaning       string
}

// resolveBlankTarget は key_word が本文中に見つかるときだけ空欄の対象を返す。
//
// 見つからないときは ๆ の有無だけ違う表記も試す。LLM は選定語「จี」を本文で
// 「จีๆ」と書くことがあり、そのとき key_word は語として一致しない
// （sentence.matchKeyWord が発音・意味の照合で同じ揺れを吸収している）。
// ここで拾わないと、その例文はクイズを作れず確認クイズが必ず失敗する。
func resolveBlankTarget(sentence QuizSentenceSeed) (blankTarget, bool) {
	thaiText := normalizeText(sentence.ThaiText)
	keyWord := normalizeText(sentence.KeyWord)

	if keyWord == "" {
		return blankTarget{}, false
	}
	word := ""
	for _, candidate := range KeyWordVariants(keyWord) {
		if _, ok := buildBlankText(thaiText, candidate, sentence.Words); ok {
			word = candidate
			break
		}
	}
	if word == "" {
		return blankTarget{}, false
	}

	return blankTarget{
		Word:          word,
		Pronunciation: normalizeText(sentence.KeyWordPronunciation),
		Meaning:       normalizeText(sentence.KeyWordMeaning),
	}, true
}

// repeatMark はタイ語の繰り返し記号 ๆ。
const repeatMark = "ๆ"

// KeyWordVariants は key_word と、ๆ の有無だけ違う表記を返す（key_word 自身が先頭）。
func KeyWordVariants(keyWord string) []string {
	word := normalizeText(keyWord)
	if word == "" {
		return nil
	}
	if trimmed := strings.TrimSuffix(word, repeatMark); trimmed != word {
		return []string{word, trimmed}
	}
	return []string{word, word + repeatMark}
}

// MatchesKeyWord は正解が key_word と同じ語かを返す。ๆ の有無は同一視する。
func MatchesKeyWord(correctAnswer, keyWord string) bool {
	answer := normalizeText(correctAnswer)
	for _, candidate := range KeyWordVariants(keyWord) {
		if answer == candidate {
			return true
		}
	}
	return false
}

// PrepareInputs は各例文の穴埋め位置を確定させる。
func PrepareInputs(sentences []QuizSentenceSeed) []PreparedQuizSentenceSeed {
	out := make([]PreparedQuizSentenceSeed, 0, len(sentences))
	for i, sentence := range sentences {
		target, ok := resolveBlankTarget(sentence)
		thaiText := normalizeText(sentence.ThaiText)

		correctAnswer := normalizeText(sentence.KeyWord)
		pronunciation := ""
		meaning := ""
		if ok {
			correctAnswer = target.Word
			pronunciation = target.Pronunciation
			meaning = target.Meaning
		}

		// 空欄を作れなければ本文をそのまま入れる（後段の検査で落ちる）
		blank, blankOK := buildBlankText(thaiText, correctAnswer, sentence.Words)
		if !blankOK {
			blank = thaiText
		}

		out = append(out, PreparedQuizSentenceSeed{
			SourceIndex:          i,
			ThaiText:             thaiText,
			BlankText:            blank,
			CorrectAnswer:        correctAnswer,
			Pronunciation:        pronunciation,
			CorrectAnswerMeaning: meaning,
			JapaneseTranslation:  normalizeText(sentence.JapaneseTranslation),
			QuizFormat:           sentence.QuizFormat,
			MeaningChoices:       uniqueTexts(sentence.MeaningChoices),
		})
	}
	return out
}

// IsSeedReady はその例文でクイズを作れるか（空欄を作れるか）を返す。
func IsSeedReady(sentence QuizSentenceSeed) bool {
	prepared := PrepareInputs([]QuizSentenceSeed{sentence})
	if len(prepared) == 0 {
		return false
	}
	p := prepared[0]
	if p.QuizFormat == FormatMeaningChoice {
		return p.CorrectAnswer != "" &&
			p.CorrectAnswerMeaning != "" &&
			len(p.MeaningChoices) == 4 &&
			containsText(p.MeaningChoices, p.CorrectAnswerMeaning)
	}
	return p.CorrectAnswer != "" && containsBlank(p.BlankText)
}

func containsText(values []string, target string) bool {
	for _, value := range values {
		if value == target {
			return true
		}
	}
	return false
}

// ApplyRuleBasedFields はモデルの出力に、こちらで確定済みの項目を合成する。
//
// blank_text / correct_answer / 発音 / 意味 / 訳文はモデルに作らせず、
// 例文データから決める。モデルはダミーと理由と解説だけを担当する。
func ApplyRuleBasedFields(
	drafts []Draft, sentences []QuizSentenceSeed,
) []GeneratedQuizQuestion {
	prepared := PrepareInputs(sentences)

	out := make([]GeneratedQuizQuestion, 0, len(drafts))
	for i, draft := range drafts {
		index := i
		var p PreparedQuizSentenceSeed
		hasPrepared := i < len(prepared)
		if hasPrepared {
			p = prepared[i]
		}

		question := GeneratedQuizQuestion{
			SourceIndex:          &index,
			ThaiText:             p.ThaiText,
			BlankText:            p.BlankText,
			CorrectAnswer:        p.CorrectAnswer,
			CorrectAnswerMeaning: p.CorrectAnswerMeaning,
			ChoicePronunciations: []string{},
			Pronunciation:        p.Pronunciation,
			Explanation:          draft.Explanation,
			DummyReasons:         draft.DummyReasons,
			QuizFormat:           p.QuizFormat,
		}

		if hasPrepared && p.QuizFormat == FormatMeaningChoice &&
			p.CorrectAnswer != "" && p.CorrectAnswerMeaning != "" &&
			len(p.MeaningChoices) == 4 {
			question.Choices = append([]string(nil), p.MeaningChoices...)
		} else if !hasPrepared || p.CorrectAnswer == "" || !containsBlank(p.BlankText) {
			// 空欄を作れていない。正解を選択肢に混ぜず、後段の検査に落とさせる。
			question.Choices = draft.Dummies
		} else {
			question.Choices = append([]string{p.CorrectAnswer}, draft.Dummies...)
		}

		out = append(out, question)
	}
	return out
}

// BuildBlankSentencePronunciation は例文の発音のうち、
// 空欄にした語の発音を "___" に差し替える。
// どちらかが空、または見つからなければ空文字。
//
// 例文の発音は語ごとの発音をスペースで繋いだもの（word_gap.go 参照）なので、
// 語の切れ目に合う出現だけを空欄にする。部分一致で採ると weelaa の中の laa の
// ように語の途中を空欄にしてしまう。
func BuildBlankSentencePronunciation(
	sentencePronunciation, keyWordPronunciation string,
) string {
	sentence := normalizeText(sentencePronunciation)
	keyWord := normalizeText(keyWordPronunciation)
	if sentence == "" || keyWord == "" {
		return ""
	}

	tokens := strings.Split(sentence, " ")
	keyTokens := strings.Split(keyWord, " ")
	for i := 0; i+len(keyTokens) <= len(tokens); i++ {
		if !equalTokens(tokens[i:i+len(keyTokens)], keyTokens) {
			continue
		}
		out := append([]string(nil), tokens[:i]...)
		out = append(out, blankText)
		out = append(out, tokens[i+len(keyTokens):]...)
		return strings.Join(out, " ")
	}
	return ""
}

// equalTokens は語の並びが等しいか。
func equalTokens(a, b []string) bool {
	for i := range b {
		if a[i] != b[i] {
			return false
		}
	}
	return true
}
