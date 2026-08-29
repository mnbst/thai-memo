package function

import (
	"log"
	"strings"

	"github.com/mnbst/thai-memo/functions/go/internal/quizgen"
)

// buildQuizSources は選出した例文をランダム順に並べ、最大 maxQuestions 件を返す。
func buildQuizSources(selected []selectedSentence) []quizSeedSource {
	shuffled := append([]selectedSentence(nil), selected...)
	shuffleN(len(shuffled), func(i, j int) {
		shuffled[i], shuffled[j] = shuffled[j], shuffled[i]
	})
	if len(shuffled) > maxQuestions {
		shuffled = shuffled[:maxQuestions]
	}

	out := make([]quizSeedSource, 0, len(shuffled))
	for _, s := range shuffled {
		out = append(out, toQuizSeedSourceFromSelected(s))
	}
	return out
}

func toQuizSeedSourceFromSelected(sentence selectedSentence) quizSeedSource {
	data := sentence.Data
	str := func(key string) string {
		s, _ := data[key].(string)
		return s
	}

	return quizSeedSource{
		Seed: quizgen.QuizSentenceSeed{
			ThaiText:             str("thai_text"),
			Pronunciation:        str("pronunciation"),
			JapaneseTranslation:  str("japanese_translation"),
			KeyWord:              str("key_word"),
			KeyWordPronunciation: str("key_word_pronunciation"),
			KeyWordMeaning:       resolveKeyWordMeaning(data),
		},
		SentenceID:            sentence.ID,
		SrsInterval:           sentence.SrsInterval,
		JapaneseTranslation:   str("japanese_translation"),
		SentencePronunciation: str("pronunciation"),
		SentenceDetail:        buildSentenceDetail(data, sentence.ID, nil),
	}
}

// buildLearningQuizSource は学習フローから渡された例文を生成元にする。
func buildLearningQuizSource(payload map[string]any) (quizSeedSource, bool) {
	if payload == nil {
		return quizSeedSource{}, false
	}

	sentenceID := quizgen.NormalizeTextValue(payload["sentence_id"])
	thaiText := quizgen.NormalizeTextValue(payload["thai_text"])
	pronunciation := quizgen.NormalizeTextValue(payload["pronunciation"])
	japaneseTranslation := quizgen.NormalizeTextValue(payload["japanese_translation"])
	keyWord := quizgen.NormalizeTextValue(payload["key_word"])

	sentenceDetail := buildSentenceDetail(payload, sentenceID, &sentenceFallback{
		ThaiText:            thaiText,
		Pronunciation:       pronunciation,
		JapaneseTranslation: japaneseTranslation,
	})

	if sentenceID == "" || thaiText == "" || keyWord == "" {
		return quizSeedSource{}, false
	}

	return quizSeedSource{
		Seed: quizgen.QuizSentenceSeed{
			ThaiText:             thaiText,
			Pronunciation:        pronunciation,
			JapaneseTranslation:  japaneseTranslation,
			KeyWord:              keyWord,
			KeyWordPronunciation: quizgen.NormalizeTextValue(payload["key_word_pronunciation"]),
			KeyWordMeaning:       quizgen.NormalizeTextValue(payload["key_word_meaning"]),
		},
		SentenceID:            sentenceID,
		SrsInterval:           0,
		JapaneseTranslation:   japaneseTranslation,
		SentencePronunciation: pronunciation,
		SentenceDetail:        sentenceDetail,
	}, true
}

type sentenceFallback struct {
	ThaiText            string
	Pronunciation       string
	JapaneseTranslation string
}

// buildSentenceDetail は問題に添える例文の詳細。
// 単語分解も文脈も無ければ nil（クライアントへ送らない）。
func buildSentenceDetail(
	data map[string]any, sentenceID string, fallback *sentenceFallback,
) map[string]any {
	wordBreakdown, _ := data["word_breakdown"].([]any)

	context, hasContext := data["context"].(map[string]any)

	if len(wordBreakdown) == 0 && !hasContext {
		return nil
	}
	if wordBreakdown == nil {
		wordBreakdown = []any{}
	}

	pick := func(key string, fb string) string {
		if v := quizgen.NormalizeTextValue(data[key]); v != "" {
			return v
		}
		return fb
	}
	var fbThai, fbPron, fbTranslation string
	if fallback != nil {
		fbThai, fbPron, fbTranslation =
			fallback.ThaiText, fallback.Pronunciation, fallback.JapaneseTranslation
	}

	detail := map[string]any{
		"id":                   sentenceID,
		"thai_text":            pick("thai_text", fbThai),
		"pronunciation":        pick("pronunciation", fbPron),
		"japanese_translation": pick("japanese_translation", fbTranslation),
		"word_breakdown":       wordBreakdown,
	}
	if hasContext {
		detail["context"] = context
	}
	if tier, ok := data["generation_tier"].(string); ok {
		detail["generation_tier"] = tier
	}
	if keyWord, ok := data["key_word"].(string); ok {
		detail["target_words"] = []any{keyWord}
	}
	return detail
}

// resolveKeyWordMeaning は key_word の意味を決める。
// 保存済みの key_word_meaning が空なら word_breakdown から探す。
//
// ๆ（繰り返し記号）の有無で表記が揺れるため、付いている・いない両方を見る。
func resolveKeyWordMeaning(data map[string]any) string {
	keyWord := quizgen.NormalizeTextValue(data["key_word"])
	if stored := quizgen.NormalizeTextValue(data["key_word_meaning"]); stored != "" {
		return stored
	}

	wordBreakdown, _ := data["word_breakdown"].([]any)
	for _, raw := range wordBreakdown {
		item, ok := raw.(map[string]any)
		if !ok {
			continue
		}
		word := quizgen.NormalizeTextValue(item["word"])
		if word == keyWord || word == keyWord+"ๆ" || word+"ๆ" == keyWord {
			return quizgen.NormalizeTextValue(item["meaning"])
		}
	}
	return ""
}

// toQuizQuestion はモデル出力と生成元を合わせてクライアント向けの1問にする。
func toQuizQuestion(
	question quizgen.GeneratedQuizQuestion, source quizSeedSource,
) quizQuestion {
	choicePronunciations := question.ChoicePronunciations
	if choicePronunciations == nil {
		choicePronunciations = []string{}
	}

	return quizQuestion{
		SentenceID:            source.SentenceID,
		ThaiText:              question.ThaiText,
		BlankText:             question.BlankText,
		CorrectAnswer:         question.CorrectAnswer,
		CorrectAnswerMeaning:  question.CorrectAnswerMeaning,
		Choices:               question.Choices,
		ChoicePronunciations:  choicePronunciations,
		Pronunciation:         question.Pronunciation,
		Explanation:           question.Explanation,
		SrsInterval:           source.SrsInterval,
		JapaneseTranslation:   source.JapaneseTranslation,
		SentencePronunciation: source.SentencePronunciation,
		BlankSentencePronunciation: quizgen.BuildBlankSentencePronunciation(
			source.SentencePronunciation, source.Seed.KeyWordPronunciation),
		DummyReasons:   question.DummyReasons,
		SentenceDetail: source.SentenceDetail,
	}
}

// isQuizSeedSourceReady は生成元として使えるか。使えなければ理由をログに残す。
func isQuizSeedSourceReady(source quizSeedSource) bool {
	if quizgen.IsSeedReady(source.Seed) {
		return true
	}
	log.Printf("quiz_seed_skipped_unresolved_key_word sentenceId=%s keyWord=%q",
		source.SentenceID, source.Seed.KeyWord)
	return false
}

// matchesKeyWord はモデルが返した正解が、こちらの指定した key_word と一致するか。
func matchesKeyWord(question quizgen.GeneratedQuizQuestion, seed quizgen.QuizSentenceSeed) bool {
	return seed.KeyWord == "" ||
		strings.TrimSpace(question.CorrectAnswer) == strings.TrimSpace(seed.KeyWord)
}
