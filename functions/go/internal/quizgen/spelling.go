package quizgen

import "log"

// BuildSpellingQuestion は綴り4択の1問をモデル無しで組み立てる。
//
// 出題は「読み＋意味」→ タイ語の綴りを選ぶ。選択肢は正解と、1次元だけ
// 違う非語のダミー3件（spellunit が作る）。ダミーは実在しない綴りなので
// 「なぜ違うか」の理由文は書けない（書けば正解が割れる）。
func BuildSpellingQuestion(seed QuizSentenceSeed) (GeneratedQuizQuestion, bool) {
	prepared := PrepareInputs([]QuizSentenceSeed{seed})
	if len(prepared) == 0 {
		return GeneratedQuizQuestion{}, false
	}
	p := prepared[0]
	index := 0

	question := GeneratedQuizQuestion{
		SourceIndex:          &index,
		ThaiText:             p.ThaiText,
		BlankText:            p.BlankText,
		CorrectAnswer:        p.CorrectAnswer,
		CorrectAnswerMeaning: p.CorrectAnswerMeaning,
		Choices:              append([]string{p.CorrectAnswer}, p.FixedDummies...),
		ChoicePronunciations: []string{},
		Pronunciation:        p.Pronunciation,
		Explanation:          p.FixedExplanation,
		JapaneseTranslation:  p.JapaneseTranslation,
		QuizFormat:           FormatSpellingChoice,
	}
	return DefaultSanitizer.Question(question)
}

// spellingQuestion は綴り4択の検査。
//
// 落とす条件はタイ語の選択肢が4件揃わないことだけ。ダミー理由は
// 作らないので、穴埋めのような理由との突き合わせはしない。
func (s *Sanitizer) spellingQuestion(
	question GeneratedQuizQuestion,
) (GeneratedQuizQuestion, bool) {
	correctAnswer := stripChoiceAnnotation(question.CorrectAnswer)
	if !isThaiChoiceText(correctAnswer) ||
		normalizeText(question.Pronunciation) == "" ||
		normalizeText(question.CorrectAnswerMeaning) == "" {
		log.Printf("Dropping spelling quiz due to invalid answer: word=%q", question.CorrectAnswer)
		return GeneratedQuizQuestion{}, false
	}

	candidates := []string{correctAnswer}
	for _, choice := range question.Choices {
		if stripped := stripChoiceAnnotation(choice); isThaiChoiceText(stripped) {
			candidates = append(candidates, stripped)
		}
	}
	choices := uniqueTexts(candidates)
	if len(choices) != 4 {
		log.Printf("Dropping spelling quiz due to invalid choices: correct=%q choices=%v",
			correctAnswer, question.Choices)
		return GeneratedQuizQuestion{}, false
	}

	out := question
	out.QuizFormat = FormatSpellingChoice
	out.ThaiText = normalizeText(question.ThaiText)
	out.BlankText = normalizeText(question.BlankText)
	out.CorrectAnswer = correctAnswer
	out.CorrectAnswerMeaning = normalizeText(question.CorrectAnswerMeaning)
	out.Choices = s.shuffle(choices)
	// 選択肢ごとの発音は出さない。出せば読みと突き合わせるだけで答えが割れる。
	out.ChoicePronunciations = []string{}
	out.Pronunciation = normalizeText(question.Pronunciation)
	out.Explanation = normalizeText(question.Explanation)
	out.JapaneseTranslation = normalizeText(question.JapaneseTranslation)
	out.SentencePronunciation = normalizeText(question.SentencePronunciation)
	out.DummyReasons = []string{}
	return out, true
}
