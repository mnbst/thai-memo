package function

import (
	"context"
	"fmt"
	"log"
	"math/rand"

	"cloud.google.com/go/firestore"

	"github.com/mnbst/thai-memo/functions/go/internal/lang"
	"github.com/mnbst/thai-memo/functions/go/internal/quizgen"
	"github.com/mnbst/thai-memo/functions/go/internal/spellunit"
)

// toSpellingSource は生成元を綴り4択に変える。
// key_word が単音節として引けないときは変えない（従来の形式のまま）。
func toSpellingSource(
	source quizSeedSource, l lang.Lang, rnd *rand.Rand,
) (quizSeedSource, bool) {
	seed := source.Seed
	if seed.KeyWord == "" || seed.KeyWordPronunciation == "" || seed.KeyWordMeaning == "" {
		return source, false
	}

	ix, err := spellunit.LoadIndex()
	if err != nil {
		log.Printf("spelling_quiz_index_unavailable error=%v", err)
		return source, false
	}
	dummies, ok := ix.Distractors(seed.KeyWord, rnd)
	if !ok {
		return source, false
	}

	texts := make([]string, 0, len(dummies))
	for _, d := range dummies {
		texts = append(texts, d.Text)
	}

	source.Seed.QuizFormat = quizgen.FormatSpellingChoice
	source.Seed.FixedDummies = texts
	source.Seed.FixedDummyPronunciations = nil
	source.Seed.MeaningChoices = nil
	source.Seed.FixedExplanation = spellingExplanation(l, seed)
	return source, true
}

// spellingExplanation は解説。モデルを呼ばないのでここで書く。
// 部品ごとの違いは spelling_parts を見て画面が組み立てるので、
// ここでは「ほかは実在しない綴り」だけを言う。
func spellingExplanation(l lang.Lang, seed quizgen.QuizSentenceSeed) string {
	if l == lang.EN {
		return fmt.Sprintf("%s is the real spelling. The other three do not exist in Thai.",
			seed.KeyWord)
	}
	return fmt.Sprintf("実在する綴りは %s だけで、ほかの3つはタイ語にありません。",
		seed.KeyWord)
}

// spellingBreakdownOf は正解の綴りの分解。音の順の部品・書く順の字・
// 声調の3要素を返す。ダミーは非語なので分解しない（見せるのは正解だけ）。
func spellingBreakdownOf(
	word string,
) ([]spellunit.Part, []spellunit.Glyph, *spellunit.ToneRule) {
	ix, err := spellunit.LoadIndex()
	if err != nil {
		return nil, nil, nil
	}
	parts, ok := ix.Parts(word)
	if !ok {
		return nil, nil, nil
	}
	glyphs, _ := ix.Glyphs(word)
	var rule *spellunit.ToneRule
	if r, ok := ix.ToneRule(word); ok {
		rule = &r
	}
	return parts, glyphs, rule
}

// applySpellingObservations は綴り4択の回答を部品データに反映し、
// 正解した語には通過フラグを立てる。
//
// 記録するのは綴り4択に答えたときだけ。出題そのものが
// spellingQuizEnabled で囲ってあるので、記録と出題は同じ条件で開閉する
// （別々に条件を置くと、記録が止まった部品が弱いままになって出題を
// 呼び続ける）。
//
// どの部品を測ったかは、正解と選択肢の差から毎回計算する。出題時の
// ダミーを保存しておく必要は無い。
func applySpellingObservations(
	ctx context.Context, db *firestore.Client, uid string, results []map[string]any,
) {
	var obs []spellunit.Observation
	var ix *spellunit.Index
	passed := map[string][]string{}
	for _, raw := range results {
		if format, _ := raw["quiz_format"].(string); format != quizgen.FormatSpellingChoice {
			continue
		}
		word, _ := raw["word"].(string)
		selected, _ := raw["selected_answer"].(string)
		isCorrect, _ := raw["is_correct"].(bool)
		choices := textsOf(raw["choices"])
		if word == "" || selected == "" || len(choices) == 0 {
			continue
		}
		if ix == nil {
			loaded, err := spellunit.LoadIndex()
			if err != nil {
				log.Printf("spelling_units_index_unavailable error=%v", err)
				return
			}
			ix = loaded
		}
		obs = append(obs, ix.Observations(word, choices, selected, isCorrect)...)
		if isCorrect {
			// 正解した語は次から従来の穴埋めへ回す。初見で当たるなら
			// 綴りは見えているので、同じ語をもう一度出す意味が無い。
			passed[word] = append(passed[word], quizgen.FormatSpellingChoice)
		}
	}
	markBeginnerPassed(ctx, db, uid, passed)
	if len(obs) == 0 {
		return
	}
	if err := spellunit.Apply(ctx, db, uid, obs); err != nil {
		log.Printf("spelling_units_update_failed uid=%s error=%v", uid, err)
	}
}

// textsOf は callable の配列を文字列の並びにする。
func textsOf(value any) []string {
	items, ok := value.([]any)
	if !ok {
		return nil
	}
	out := make([]string, 0, len(items))
	for _, item := range items {
		if s, ok := item.(string); ok && s != "" {
			out = append(out, s)
		}
	}
	return out
}
