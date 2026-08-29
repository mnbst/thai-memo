package quizgen

import (
	"log"
	"math/rand"
	"regexp"
)

// Sanitizer はモデル出力の検査と整形。
type Sanitizer struct {
	// Shuffle は選択肢の並べ替え。nil なら乱数で並べ替える。
	// テストで順序を固定するために差し替えられるようにしている。
	Shuffle func([]string) []string
}

// DefaultSanitizer は本番用。
var DefaultSanitizer = &Sanitizer{}

func (s *Sanitizer) shuffle(choices []string) []string {
	out := append([]string(nil), choices...)
	if s.Shuffle != nil {
		return s.Shuffle(out)
	}
	rand.Shuffle(len(out), func(i, j int) { out[i], out[j] = out[j], out[i] })
	return out
}

// Questions は検査を通った問題だけを返す。落とした問題はログに残す。
func (s *Sanitizer) Questions(questions []GeneratedQuizQuestion) []GeneratedQuizQuestion {
	out := make([]GeneratedQuizQuestion, 0, len(questions))
	for _, q := range questions {
		if sanitized, ok := s.Question(q); ok {
			out = append(out, sanitized)
		}
	}
	return out
}

// Question は1問を検査・整形する。使えなければ ok=false。
//
// 落とす条件:
//   - 正解がタイ語でない
//   - タイ語の選択肢が4件に満たない
//   - ダミー3件それぞれに対応する理由が揃っていない
func (s *Sanitizer) Question(question GeneratedQuizQuestion) (GeneratedQuizQuestion, bool) {
	correctAnswer := stripChoiceAnnotation(question.CorrectAnswer)
	if !isThaiChoiceText(correctAnswer) {
		log.Printf("Dropping quiz question due to non-Thai correct answer: %q",
			question.CorrectAnswer)
		return GeneratedQuizQuestion{}, false
	}

	candidates := []string{correctAnswer}
	for _, choice := range question.Choices {
		stripped := stripChoiceAnnotation(choice)
		if isThaiChoiceText(stripped) {
			candidates = append(candidates, stripped)
		}
	}
	choices := uniqueTexts(candidates)
	if len(choices) > 4 {
		choices = choices[:4]
	}
	if len(choices) < 4 {
		log.Printf("Dropping quiz question due to insufficient Thai choices: correct=%q choices=%v",
			correctAnswer, question.Choices)
		return GeneratedQuizQuestion{}, false
	}

	dummyReasons, ok := sanitizeDummyReasons(question.DummyReasons, correctAnswer, choices)
	if !ok {
		log.Printf("Dropping quiz question due to incomplete dummy reasons: correct=%q choices=%v reasons=%v",
			correctAnswer, question.Choices, question.DummyReasons)
		return GeneratedQuizQuestion{}, false
	}

	shuffled := s.shuffle(choices)

	out := question
	out.ThaiText = normalizeText(question.ThaiText)
	out.BlankText = normalizeText(question.BlankText)
	out.CorrectAnswer = correctAnswer
	out.CorrectAnswerMeaning = normalizeText(question.CorrectAnswerMeaning)
	out.Choices = shuffled
	out.ChoicePronunciations = buildChoicePronunciations(
		shuffled, correctAnswer, question.Pronunciation, dummyReasons)
	out.Pronunciation = normalizeText(question.Pronunciation)
	out.Explanation = normalizeText(question.Explanation)
	out.JapaneseTranslation = normalizeText(question.JapaneseTranslation)
	out.SentencePronunciation = normalizeText(question.SentencePronunciation)
	out.DummyReasons = dummyReasons
	return out, true
}

// sanitizeDummyReasons はダミー3件それぞれに対応する理由を並べ直す。
// 対応が取れなければ ok=false（問題ごと落とす）。
func sanitizeDummyReasons(
	rawReasons []string, correctAnswer string, choices []string,
) ([]string, bool) {
	reasons := uniqueTexts(rawReasons)

	var dummyChoices []string
	for _, choice := range choices {
		if choice != correctAnswer {
			dummyChoices = append(dummyChoices, choice)
		}
	}

	if len(dummyChoices) != 3 || len(reasons) < 3 {
		return nil, false
	}

	matched := make([]string, 0, 3)
	for _, choice := range dummyChoices {
		found := ""
		for _, reason := range reasons {
			if indexOf(reason, choice) >= 0 {
				found = reason
				break
			}
		}
		if found == "" {
			return nil, false
		}
		matched = append(matched, found)
	}
	return matched, true
}

// buildChoicePronunciations は選択肢ごとの発音を組み立てる。
// 正解は例文データの発音、ダミーは理由の書式から切り出す。
func buildChoicePronunciations(
	choices []string, correctAnswer, correctAnswerPronunciation string,
	dummyReasons []string,
) []string {
	normalizedCorrect := normalizeText(correctAnswerPronunciation)

	out := make([]string, 0, len(choices))
	for _, choice := range choices {
		if choice == correctAnswer {
			out = append(out, normalizedCorrect)
			continue
		}
		pronunciation := ""
		for _, reason := range dummyReasons {
			if indexOf(reason, choice) >= 0 {
				pronunciation = extractDummyPronunciation(reason, choice)
				break
			}
		}
		out = append(out, pronunciation)
	}
	return out
}

// extractDummyPronunciation は「語（ローマ字 / 意味）：理由」の書式から
// ローマ字部分を切り出す。
//
// この書式はプロンプト側（DUMMY_REASON_FORMAT）で固定している。崩すと
// 4択の発音表示が空になる。
func extractDummyPronunciation(reason, choice string) string {
	re, err := regexp.Compile(regexp.QuoteMeta(choice) +
		`[` + jsSpace + `]*[（(][` + jsSpace + `]*([^/）)]+?)[` + jsSpace + `]*/`)
	if err != nil {
		return ""
	}
	m := re.FindStringSubmatch(reason)
	if m == nil {
		return ""
	}
	return normalizeText(m[1])
}
