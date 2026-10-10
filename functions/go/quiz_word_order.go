package function

import (
	"fmt"
	"math/rand"
	"strings"

	"github.com/mnbst/thai-memo/functions/go/internal/lang"
	"github.com/mnbst/thai-memo/functions/go/internal/quizgen"
)

// 並び替え（word_order）をまとめクイズに差し込む層。
//
// key_word を含む連続した4語を混ぜて並べ直させる。実用タイ語検定の
// 並べ替え問題と同じ形で、語彙スコアで下限は設けない（5級もカタカナ・
// ローマ字で出る）。入門用の形式（綴り4択）に変わった問題には触らない。

// wordOrderPerQuiz はまとめクイズ1回に混ぜる並び替えの数。
const wordOrderPerQuiz = 1

// applyWordOrder は従来の穴埋めのままの問題から wordOrderPerQuiz 問を並び替えに
// 変える。showPronunciation はタイルの読みを最初から見せるか（入門用の対象者）。
// 差し替えた問題数を返す。
func applyWordOrder(
	sources []quizSeedSource, l lang.Lang, showPronunciation bool, rnd *rand.Rand,
) int {
	applied := 0
	for _, i := range rnd.Perm(len(sources)) {
		if applied >= wordOrderPerQuiz {
			break
		}
		if sources[i].Seed.QuizFormat != quizgen.FormatClozeChoice {
			continue
		}
		converted, ok := toWordOrderSource(sources[i], l, showPronunciation, rnd)
		if !ok {
			continue
		}
		sources[i] = converted
		applied++
	}
	return applied
}

// toWordOrderSource は生成元を並び替えに変える。作れなければ変えない。
func toWordOrderSource(
	source quizSeedSource, l lang.Lang, showPronunciation bool, rnd *rand.Rand,
) (quizSeedSource, bool) {
	seed := source.Seed
	if seed.KeyWord == "" {
		return source, false
	}
	wo, ok := quizgen.BuildWordOrder(seed.ThaiText,
		wordOrderWordsOf(source.SentenceDetail), seed.KeyWord, rnd)
	if !ok {
		return source, false
	}
	source.Seed.QuizFormat = quizgen.FormatWordOrder
	source.Seed.FixedExplanation = wordOrderExplanation(l, wo)
	source.WordOrder = &wo
	source.WordOrderShowPronunciation = showPronunciation
	return source, true
}

// wordOrderWordsOf は例文の詳細から語と読みを出現順に取り出す。
func wordOrderWordsOf(detail map[string]any) []quizgen.WordOrderWord {
	wordBreakdown, _ := detail["word_breakdown"].([]any)
	out := make([]quizgen.WordOrderWord, 0, len(wordBreakdown))
	for _, raw := range wordBreakdown {
		item, ok := raw.(map[string]any)
		if !ok {
			continue
		}
		out = append(out, quizgen.WordOrderWord{
			Text:          quizgen.NormalizeTextValue(item["word"]),
			Pronunciation: quizgen.NormalizeTextValue(item["pronunciation"]),
		})
	}
	return out
}

// wordOrderExplanation は解説。モデルを呼ばないのでここで書く。
func wordOrderExplanation(l lang.Lang, wo quizgen.WordOrder) string {
	order := strings.Join(wo.Answer, " → ")
	if l == lang.EN {
		return fmt.Sprintf("Correct order: %s", order)
	}
	return fmt.Sprintf("正しい並び: %s", order)
}

// wordOrderQuestion はクライアント向けの1問。choices はタイル（混ぜた並び）、
// correct_answer は key_word（UVM の更新対象）。
func wordOrderQuestion(source quizSeedSource) quizQuestion {
	wo := source.WordOrder
	seed := source.Seed
	blank := func(prefix, suffix string) string {
		return strings.TrimSpace(strings.Join([]string{prefix, "___", suffix}, " "))
	}
	return quizQuestion{
		SentenceID:            source.SentenceID,
		ThaiText:              quizgen.NormalizeText(seed.ThaiText),
		BlankText:             blank(wo.Prefix, wo.Suffix),
		CorrectAnswer:         seed.KeyWord,
		CorrectAnswerMeaning:  seed.KeyWordMeaning,
		Choices:               wo.Tiles,
		ChoicePronunciations:  wo.TilePronunciations,
		Pronunciation:         seed.KeyWordPronunciation,
		Explanation:           seed.FixedExplanation,
		SrsInterval:           source.SrsInterval,
		JapaneseTranslation:   source.JapaneseTranslation,
		SentencePronunciation: source.SentencePronunciation,
		BlankSentencePronunciation: blank(
			wo.PrefixPronunciation, wo.SuffixPronunciation),
		DummyReasons:               []string{},
		SentenceDetail:             source.SentenceDetail,
		QuizFormat:                 quizgen.FormatWordOrder,
		WordOrderAnswer:            wo.Answer,
		WordOrderPrefix:            wo.Prefix,
		WordOrderSuffix:            wo.Suffix,
		WordOrderShowPronunciation: source.WordOrderShowPronunciation,
	}
}
