package function

import (
	"context"
	"encoding/json"
	"os"
	"sort"
	"strings"
	"testing"

	"github.com/mnbst/thai-memo/functions/go/internal/gemini"
	"github.com/mnbst/thai-memo/functions/go/internal/lang"
	"github.com/mnbst/thai-memo/functions/go/internal/quizgen"
	"github.com/mnbst/thai-memo/functions/go/internal/secrets"
)

// TestFixedDummyQuizLive はダミー確定の経路を実際に Gemini へ通す。
//
// 見るのは3つ。
//
//   - 渡したダミーがそのまま選択肢に入るか（モデルが差し替えないか）
//
//   - dummy_reasons が3件そろい、sanitize に落とされずに1問になるか
//
//   - 選択肢の発音（dummy_reasons から切り出す）が埋まるか
//
//     GOOGLE_CLOUD_PROJECT=thai-memo-dev QUIZ_DISTRACTOR_LIVE=1 \
//     go test ./ -run TestFixedDummyQuizLive -v
func TestFixedDummyQuizLive(t *testing.T) {
	if os.Getenv("QUIZ_DISTRACTOR_LIVE") == "" {
		t.Skip("QUIZ_DISTRACTOR_LIVE=1 で実行する")
	}
	ctx := context.Background()
	key, err := secrets.Get(ctx, "gemini-api-key")
	if err != nil {
		t.Skipf("gemini-api-key が要る: %v", err)
	}

	freqRank := loadLocalFreqRank(t)
	sorted := make([]rankedWord, 0, len(freqRank))
	for word, rank := range freqRank {
		sorted = append(sorted, rankedWord{word: word, rank: rank})
	}
	sort.Slice(sorted, func(i, j int) bool { return sorted[i].rank < sorted[j].rank })
	vocab := &quizVocab{freqRank: freqRank, sorted: sorted, pos: map[string]string{}}

	// 訳文の言語で理由・解説の言語が変わる。書式（発音の切り出し）は共通なので
	// 両方流す。
	l := lang.JA
	if os.Getenv("QUIZ_LANG") == "en" {
		l = lang.EN
	}
	service := &gemini.QuizService{APIKey: key, UID: "live-test", Tier: "premium", Lang: l}

	var ok, dropped, swapped, noPron int
	for _, row := range loadCorpusSample(t, 8) {
		seed := quizgen.QuizSentenceSeed{
			QuizFormat:           quizgen.FormatClozeChoice,
			ThaiText:             row.thai,
			Words:                row.words,
			KeyWord:              row.target,
			KeyWordPronunciation: row.targetPron,
			JapaneseTranslation:  "（省略）",
		}
		seed.FixedDummies = quizgen.PickDistractors(vocab, row.target, row.words, nil)
		seed.FixedDummyPronunciations = dummyPronunciations(seed.FixedDummies)
		if len(seed.FixedDummies) == 0 {
			t.Logf("― %s: ダミーを選べず（従来経路）", row.thai)
			continue
		}

		questions := service.GenerateQuizQuestions(ctx, []quizgen.QuizSentenceSeed{seed})
		if len(questions) == 0 {
			dropped++
			t.Errorf("× %s: 問題が作れなかった（ダミー %v）", row.thai, seed.FixedDummies)
			continue
		}
		q := questions[0]

		// 渡したダミーが選択肢に残っているか。
		missing := make([]string, 0, len(seed.FixedDummies))
		for _, d := range seed.FixedDummies {
			if !containsChoice(q.Choices, d) {
				missing = append(missing, d)
			}
		}
		if len(missing) > 0 {
			swapped++
			t.Errorf("× %s: 渡したダミーが選択肢に無い %v（選択肢 %v）",
				row.thai, missing, q.Choices)
			continue
		}
		blank := 0
		for _, p := range q.ChoicePronunciations {
			if strings.TrimSpace(p) == "" {
				blank++
			}
		}
		if blank > 0 {
			noPron++
		}
		ok++
		out, _ := json.Marshal(map[string]any{
			"blank":   q.BlankText,
			"correct": q.CorrectAnswer,
			"choices": q.Choices,
			"pron":    q.ChoicePronunciations,
			"reasons": q.DummyReasons,
			"explain": q.Explanation,
			"発音の空欄":   blank,
		})
		t.Logf("○ %s", out)
	}
	t.Logf("成立 %d / 落ちた %d / ダミー差し替え %d / 発音が空 %d", ok, dropped, swapped, noPron)
}

func containsChoice(choices []string, word string) bool {
	for _, c := range choices {
		if strings.TrimSpace(c) == strings.TrimSpace(word) {
			return true
		}
	}
	return false
}
