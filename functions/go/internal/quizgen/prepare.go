package quizgen

// blankTarget は空欄にする語とその読み・意味。
type blankTarget struct {
	Word          string
	Pronunciation string
	Meaning       string
}

// resolveBlankTarget は key_word が本文中に見つかるときだけ空欄の対象を返す。
func resolveBlankTarget(sentence QuizSentenceSeed) (blankTarget, bool) {
	thaiText := normalizeText(sentence.ThaiText)
	keyWord := normalizeText(sentence.KeyWord)

	if keyWord == "" {
		return blankTarget{}, false
	}
	if _, ok := buildBlankText(thaiText, keyWord); !ok {
		return blankTarget{}, false
	}

	return blankTarget{
		Word:          keyWord,
		Pronunciation: normalizeText(sentence.KeyWordPronunciation),
		Meaning:       normalizeText(sentence.KeyWordMeaning),
	}, true
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
		blank, blankOK := buildBlankText(thaiText, correctAnswer)
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
	return p.CorrectAnswer != "" && containsBlank(p.BlankText)
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
		}

		if !hasPrepared || p.CorrectAnswer == "" || !containsBlank(p.BlankText) {
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
func BuildBlankSentencePronunciation(
	sentencePronunciation, keyWordPronunciation string,
) string {
	sentence := normalizeText(sentencePronunciation)
	keyWord := normalizeText(keyWordPronunciation)
	if sentence == "" || keyWord == "" {
		return ""
	}
	i := indexOf(sentence, keyWord)
	if i < 0 {
		return ""
	}
	// JS の String#replace は最初の1件だけ置換する
	return sentence[:i] + blankText + sentence[i+len(keyWord):]
}
