package quizgen

import (
	"encoding/json"
	"os"
	"reflect"
	"testing"

	"github.com/mnbst/thai-memo/functions/go/internal/lang"
)

type quizGolden struct {
	Prompts struct {
		SystemJA string `json:"system_ja"`
		SystemEN string `json:"system_en"`
	} `json:"prompts"`
	PrepareCases []struct {
		Sentences    []QuizSentenceSeed         `json:"sentences"`
		Prepared     []PreparedQuizSentenceSeed `json:"prepared"`
		Ready        []bool                     `json:"ready"`
		UserPromptJA string                     `json:"user_prompt_ja"`
		UserPromptEN string                     `json:"user_prompt_en"`
		Drafts       []Draft                    `json:"drafts"`
		Applied      []GeneratedQuizQuestion    `json:"applied"`
	} `json:"prepare_cases"`
	SanitizeCases []struct {
		Input  GeneratedQuizQuestion  `json:"input"`
		Output *GeneratedQuizQuestion `json:"output"`
	} `json:"sanitize_cases"`
	BlankPronunciationCases []struct {
		SentencePronunciation string `json:"sentence_pronunciation"`
		KeyWordPronunciation  string `json:"key_word_pronunciation"`
		Output                string `json:"output"`
	} `json:"blank_pronunciation_cases"`
}

func loadQuizGolden(t *testing.T) *quizGolden {
	t.Helper()
	raw, err := os.ReadFile("../../testdata/javascript/quiz_golden.json")
	if err != nil {
		t.Fatalf("golden の読み込みに失敗: %v", err)
	}
	var golden quizGolden
	if err := json.Unmarshal(raw, &golden); err != nil {
		t.Fatal(err)
	}
	return &golden
}

// TestSystemPromptGolden はシステムプロンプトが JS 版と1バイトも違わないことを確かめる。
//
// プロンプトは生成物の質を直接左右するうえ、dummy_reasons の書式は
// extractDummyPronunciation が依存している。差分は必ず落とす。
func TestSystemPromptGolden(t *testing.T) {
	golden := loadQuizGolden(t)

	for _, tc := range []struct {
		l    lang.Lang
		want string
	}{
		{lang.JA, golden.Prompts.SystemJA},
		{lang.EN, golden.Prompts.SystemEN},
	} {
		t.Run(string(tc.l), func(t *testing.T) {
			if tc.want == "" {
				t.Fatal("golden が空")
			}
			got := SystemPrompt(tc.l)
			if got == tc.want {
				return
			}
			t.Errorf("システムプロンプトが JS と違う（JS %d バイト / Go %d バイト）",
				len(tc.want), len(got))
			t.Errorf("最初の相違: %s", firstDiff(tc.want, got))
		})
	}

	// ja と en が同一なら、言語切り替えが効いていない
	if golden.Prompts.SystemJA == golden.Prompts.SystemEN {
		t.Error("ja と en のプロンプトが同一。golden が退化している")
	}
}

// TestPrepareAndApplyGolden は穴埋め位置の確定・ユーザープロンプト・
// ルールベース合成を JS 版と突き合わせる。
func TestPrepareAndApplyGolden(t *testing.T) {
	golden := loadQuizGolden(t)
	if len(golden.PrepareCases) == 0 {
		t.Fatal("golden が空")
	}

	var readyTrue, readyFalse int
	for i, c := range golden.PrepareCases {
		got := PrepareInputs(c.Sentences)
		if !reflect.DeepEqual(got, c.Prepared) {
			t.Errorf("case %d: PrepareInputs\n  JS = %+v\n  Go = %+v", i, c.Prepared, got)
		}

		for j, sentence := range c.Sentences {
			gotReady := IsSeedReady(sentence)
			if gotReady != c.Ready[j] {
				t.Errorf("case %d/%d: IsSeedReady JS=%v Go=%v (%+v)",
					i, j, c.Ready[j], gotReady, sentence)
			}
			if c.Ready[j] {
				readyTrue++
			} else {
				readyFalse++
			}
		}

		if got := BuildPrompt(c.Sentences, lang.JA); got != c.UserPromptJA {
			t.Errorf("case %d: ja のユーザープロンプトが違う\n%s", i,
				firstDiff(c.UserPromptJA, got))
		}
		if got := BuildPrompt(c.Sentences, lang.EN); got != c.UserPromptEN {
			t.Errorf("case %d: en のユーザープロンプトが違う\n%s", i,
				firstDiff(c.UserPromptEN, got))
		}

		gotApplied := ApplyRuleBasedFields(c.Drafts, c.Sentences)
		if !reflect.DeepEqual(normalizeQuestions(gotApplied), normalizeQuestions(c.Applied)) {
			t.Errorf("case %d: ApplyRuleBasedFields\n  JS = %+v\n  Go = %+v",
				i, c.Applied, gotApplied)
		}
	}

	t.Logf("%d ケース一致（IsSeedReady: true %d / false %d）",
		len(golden.PrepareCases), readyTrue, readyFalse)
	if readyTrue == 0 || readyFalse == 0 {
		t.Error("IsSeedReady の両方の分岐が踏まれていない。golden が退化している")
	}
}

// TestSanitizeGolden は問題の検査・整形を JS 版と突き合わせる。
//
// 選択肢の並べ替えは乱数なので、golden 生成側で Math.random を固定して
// 元の順序が保たれるようにしてある。Go 側も恒等の Shuffle を使う。
func TestSanitizeGolden(t *testing.T) {
	golden := loadQuizGolden(t)
	if len(golden.SanitizeCases) == 0 {
		t.Fatal("golden が空")
	}

	sanitizer := &Sanitizer{Shuffle: func(c []string) []string { return c }}

	var kept, dropped, withPronunciation, withoutPronunciation int
	for i, c := range golden.SanitizeCases {
		got, ok := sanitizer.Question(c.Input)

		if c.Output == nil {
			dropped++
			if ok {
				t.Errorf("case %d: JS は破棄したのに Go は通した\n  入力 = %+v\n  出力 = %+v",
					i, c.Input, got)
			}
			continue
		}

		kept++
		if !ok {
			t.Errorf("case %d: JS は通したのに Go は破棄した\n  入力 = %+v", i, c.Input)
			continue
		}

		for _, p := range c.Output.ChoicePronunciations {
			if p == "" {
				withoutPronunciation++
			} else {
				withPronunciation++
			}
		}

		if !reflect.DeepEqual(normalizeQuestion(got), normalizeQuestion(*c.Output)) {
			t.Errorf("case %d:\n  JS = %+v\n  Go = %+v", i, *c.Output, got)
		}
	}

	t.Logf("%d ケース一致（通過 %d / 破棄 %d、ダミー発音 取得 %d / 空 %d）",
		len(golden.SanitizeCases), kept, dropped, withPronunciation, withoutPronunciation)
	for label, n := range map[string]int{
		"通過": kept, "破棄": dropped,
		"発音取得": withPronunciation, "発音空": withoutPronunciation,
	} {
		if n == 0 {
			t.Errorf("%s の分岐が1件も踏まれていない。golden が退化している", label)
		}
	}
}

// TestBlankSentencePronunciationGolden は例文発音の空欄化を JS 版と突き合わせる。
func TestBlankSentencePronunciationGolden(t *testing.T) {
	golden := loadQuizGolden(t)
	if len(golden.BlankPronunciationCases) == 0 {
		t.Fatal("golden が空")
	}

	var filled, empty int
	for i, c := range golden.BlankPronunciationCases {
		got := BuildBlankSentencePronunciation(
			c.SentencePronunciation, c.KeyWordPronunciation)
		if got != c.Output {
			t.Errorf("case %d: JS=%q Go=%q（例文=%q 語=%q）",
				i, c.Output, got, c.SentencePronunciation, c.KeyWordPronunciation)
		}
		if c.Output == "" {
			empty++
		} else {
			filled++
		}
	}

	t.Logf("%d ケース一致（空欄化 %d / 空 %d）",
		len(golden.BlankPronunciationCases), filled, empty)
	if filled == 0 || empty == 0 {
		t.Error("両方の分岐が踏まれていない。golden が退化している")
	}
}

// normalizeQuestion は nil スライスと空スライスの差を吸収する
// （JSON 由来か Go 由来かで変わるだけで、意味は同じ）。
func normalizeQuestion(q GeneratedQuizQuestion) GeneratedQuizQuestion {
	if q.Choices == nil {
		q.Choices = []string{}
	}
	if q.ChoicePronunciations == nil {
		q.ChoicePronunciations = []string{}
	}
	if q.DummyReasons == nil {
		q.DummyReasons = []string{}
	}
	return q
}

func normalizeQuestions(qs []GeneratedQuizQuestion) []GeneratedQuizQuestion {
	out := make([]GeneratedQuizQuestion, 0, len(qs))
	for _, q := range qs {
		out = append(out, normalizeQuestion(q))
	}
	return out
}

// firstDiff は最初に食い違う位置と前後を返す（プロンプト比較のため）。
func firstDiff(want, got string) string {
	w, g := []rune(want), []rune(got)
	n := min(len(w), len(g))
	for i := range n {
		if w[i] != g[i] {
			lo := max(i-40, 0)
			return "  位置 " + itoa(i) + "\n  JS = ..." + string(w[lo:min(i+40, len(w))]) +
				"...\n  Go = ..." + string(g[lo:min(i+40, len(g))]) + "..."
		}
	}
	if len(w) == len(g) {
		return "  差分なし（長さも同じ）"
	}
	lo := max(n-40, 0)
	if len(w) > len(g) {
		return "  Go が短い。JS の続き: ..." + string(w[lo:min(n+40, len(w))])
	}
	return "  Go が長い。Go の続き: ..." + string(g[lo:min(n+40, len(g))])
}

func itoa(n int) string {
	if n == 0 {
		return "0"
	}
	var b []byte
	for n > 0 {
		b = append([]byte{byte('0' + n%10)}, b...)
		n /= 10
	}
	return string(b)
}
