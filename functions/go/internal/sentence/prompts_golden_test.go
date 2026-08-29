package sentence

import (
	"encoding/json"
	"os"
	"reflect"
	"testing"

	"github.com/mnbst/thai-memo/functions/go/internal/lang"
)

type promptsGolden struct {
	DifficultyCases []struct {
		EstimatedVocab int    `json:"estimated_vocab"`
		Label          string `json:"label"`
		VocabHint      string `json:"vocab_hint"`
		Length         string `json:"length"`
	} `json:"difficulty_cases"`
	GateCases []struct {
		EstimatedVocab int      `json:"estimated_vocab"`
		Pool           []string `json:"pool"`
		Result         []string `json:"result"`
	} `json:"gate_cases"`
	SystemPromptCases []struct {
		IsPremium bool   `json:"is_premium"`
		Lang      string `json:"lang"`
		Prompt    string `json:"prompt"`
	} `json:"system_prompt_cases"`
	ConstraintCases []struct {
		Topic       string   `json:"topic"`
		TargetWords []string `json:"target_words"`
		Lang        string   `json:"lang"`
		Register    string   `json:"register"`
		Free        string   `json:"free"`
		WordClass   string   `json:"word_class"`
	} `json:"constraint_cases"`
	RelationCases []struct {
		Relation string `json:"relation"`
		Result   string `json:"result"`
	} `json:"relation_cases"`
	PromptCases []struct {
		Resolved struct {
			Topic        string   `json:"topic"`
			TopicOptions []string `json:"topicOptions"`
			SubTheme     *string  `json:"subTheme"`
			TimeFrame    *string  `json:"timeFrame"`
			Relation     *string  `json:"relation"`
		} `json:"resolved"`
		TargetWords    []string `json:"target_words"`
		EstimatedVocab int      `json:"estimated_vocab"`
		IsPremium      bool     `json:"is_premium"`
		Lang           string   `json:"lang"`
		Drama          struct {
			Context  string `json:"context"`
			Required string `json:"required"`
		} `json:"drama"`
		Prompt  string         `json:"prompt"`
		Context map[string]any `json:"context"`
	} `json:"prompt_cases"`
}

func loadPromptsGolden(t *testing.T) *promptsGolden {
	t.Helper()
	raw, err := os.ReadFile(
		"../../testdata/python/daily_golden/prompts_golden.json")
	if err != nil {
		t.Fatalf("golden の読み込みに失敗: %v", err)
	}
	var golden promptsGolden
	if err := json.Unmarshal(raw, &golden); err != nil {
		t.Fatal(err)
	}
	return &golden
}

// TestGetDifficultyGolden は難易度と長さヒントを Python 実装と突き合わせる。
//
// 「長さ」は難易度制御の実体なので、線形補間の丸め（Python は偶数丸め）まで一致
// させる必要がある。
func TestGetDifficultyGolden(t *testing.T) {
	golden := loadPromptsGolden(t)
	if len(golden.DifficultyCases) == 0 {
		t.Fatal("golden が空")
	}

	seenLabel := map[string]int{}
	for _, c := range golden.DifficultyCases {
		got := GetDifficulty(c.EstimatedVocab)
		seenLabel[c.Label]++
		if got.Label != c.Label || got.VocabHint != c.VocabHint ||
			got.Length != c.Length {
			t.Errorf("vocab=%d:\n  Python = %s / %s\n  Go     = %s / %s",
				c.EstimatedVocab, c.Label, c.Length, got.Label, got.Length)
		}
	}

	t.Logf("%d ケース一致 %v", len(golden.DifficultyCases), seenLabel)
	for _, want := range []string{"入門", "初級", "初中級", "中級", "上級"} {
		if seenLabel[want] == 0 {
			t.Errorf("%s の帯が踏まれていない", want)
		}
	}
}

// TestGateTopicsGolden はテーマのレベル別ゲートを突き合わせる。
func TestGateTopicsGolden(t *testing.T) {
	golden := loadPromptsGolden(t)

	var narrowed, fellBack int
	for i, c := range golden.GateCases {
		got := GateTopicsForVocab(c.Pool, c.EstimatedVocab)
		if len(c.Result) < len(c.Pool) {
			narrowed++
		}
		if len(c.Result) == len(c.Pool) && c.EstimatedVocab == 0 &&
			len(c.Pool) > 0 && topicMinVocab[c.Pool[0]] > 0 {
			fellBack++
		}
		if !reflect.DeepEqual(got, c.Result) {
			t.Errorf("case %d (vocab=%d):\n  Python = %v\n  Go     = %v",
				i, c.EstimatedVocab, c.Result, got)
		}
	}
	t.Logf("%d ケース一致（絞られた %d / 全落ちで元に戻した %d）",
		len(golden.GateCases), narrowed, fellBack)
	if narrowed == 0 || fellBack == 0 {
		t.Error("絞り込みか全落ちフォールバックのどちらかが踏まれていない")
	}
}

// TestSystemPromptGoldenPy はシステムプロンプトがバイト一致することを確かめる。
func TestSystemPromptGoldenPy(t *testing.T) {
	golden := loadPromptsGolden(t)
	if len(golden.SystemPromptCases) != 4 {
		t.Fatalf("golden のケース数が想定外: %d", len(golden.SystemPromptCases))
	}

	for _, c := range golden.SystemPromptCases {
		got := SystemPrompt(c.IsPremium, lang.Lang(c.Lang))
		if got != c.Prompt {
			t.Errorf("premium=%v lang=%s: プロンプトが違う（Python %d / Go %d バイト）\n%s",
				c.IsPremium, c.Lang, len(c.Prompt), len(got),
				firstDiff(c.Prompt, got))
		}
	}
	t.Logf("4 ケース（premium/free × ja/en）バイト一致")
}

// TestConstraintBlocksGolden は【最後に確認】と語クラスブロックを突き合わせる。
func TestConstraintBlocksGolden(t *testing.T) {
	golden := loadPromptsGolden(t)
	if len(golden.ConstraintCases) == 0 {
		t.Fatal("golden が空")
	}

	var romance, dropped, wordClass int
	for i, c := range golden.ConstraintCases {
		l := lang.Lang(c.Lang)

		if got := BuildRegisterConstraint(c.Topic, c.TargetWords, l); got != c.Register {
			t.Errorf("case %d register (topic=%q words=%v lang=%s):\n%s",
				i, c.Topic, c.TargetWords, c.Lang, firstDiff(c.Register, got))
		}
		if got := BuildFreeConstraint(c.TargetWords, l); got != c.Free {
			t.Errorf("case %d free:\n%s", i, firstDiff(c.Free, got))
		}
		if got := BuildWordClassConstraint(c.TargetWords); got != c.WordClass {
			t.Errorf("case %d word_class (words=%v):\n%s",
				i, c.TargetWords, firstDiff(c.WordClass, got))
		}

		if c.Topic == Topics[14] || c.Topic == Topics[15] {
			romance++
		}
		for _, w := range c.TargetWords {
			if _, banned := ruleBannedWords[w]; banned {
				dropped++
				break
			}
		}
		if c.WordClass != "" {
			wordClass++
		}
	}

	t.Logf("%d ケース一致（恋愛系テーマ %d / 禁止語でルール除去 %d / 語クラス付与 %d）",
		len(golden.ConstraintCases), romance, dropped, wordClass)
	if romance == 0 || dropped == 0 || wordClass == 0 {
		t.Error("分岐が踏まれていない")
	}
}

// TestRelationConstraintGolden は関係ブロックを突き合わせる。
func TestRelationConstraintGolden(t *testing.T) {
	golden := loadPromptsGolden(t)

	var empty, filled int
	for i, c := range golden.RelationCases {
		got := BuildRelationConstraint(c.Relation)
		if c.Result == "" {
			empty++
		} else {
			filled++
		}
		if got != c.Result {
			t.Errorf("case %d (relation=%q):\n%s", i, c.Relation,
				firstDiff(c.Result, got))
		}
	}
	t.Logf("%d ケース一致（空 %d / 生成 %d）", len(golden.RelationCases), empty, filled)
	if empty == 0 || filled == 0 {
		t.Error("空と生成のどちらかが踏まれていない")
	}
}

// TestBuildPromptGolden はプロンプト全文と context を Python 実装と突き合わせる。
//
// 抽選部分は golden 生成時に固定してあるので、組み立てはバイト一致するはず。
func TestBuildPromptGolden(t *testing.T) {
	golden := loadPromptsGolden(t)
	if len(golden.PromptCases) == 0 {
		t.Fatal("golden が空")
	}

	var dramaCases, noTopicCases, premiumCases int
	for i, c := range golden.PromptCases {
		resolved := ResolvedParams{
			Topic:        c.Resolved.Topic,
			TopicOptions: c.Resolved.TopicOptions,
			SubTheme:     deref(c.Resolved.SubTheme),
			TimeFrame:    deref(c.Resolved.TimeFrame),
			Relation:     deref(c.Resolved.Relation),
		}
		drama := DramaSection{Context: c.Drama.Context, Required: c.Drama.Required}

		gotPrompt, gotContext := BuildPrompt(
			resolved, c.TargetWords, c.EstimatedVocab,
			c.IsPremium, lang.Lang(c.Lang), drama)

		if c.Resolved.Topic == Topics[15] {
			dramaCases++
		}
		if c.Resolved.Topic == "" {
			noTopicCases++
		}
		if c.IsPremium {
			premiumCases++
		}

		if gotPrompt != c.Prompt {
			t.Errorf("case %d (topic=%q premium=%v lang=%s):\n%s",
				i, c.Resolved.Topic, c.IsPremium, c.Lang,
				firstDiff(c.Prompt, gotPrompt))
		}
		if !reflect.DeepEqual(roundTrip(t, gotContext), normalizeContext(c.Context)) {
			t.Errorf("case %d の context:\n  Python = %v\n  Go     = %v",
				i, c.Context, gotContext)
		}
	}

	t.Logf("%d ケース一致（ドラマ回 %d / テーマ未確定 %d / premium %d）",
		len(golden.PromptCases), dramaCases, noTopicCases, premiumCases)
	if dramaCases == 0 || noTopicCases == 0 || premiumCases == 0 {
		t.Error("分岐が踏まれていない")
	}
}

func deref(s *string) string {
	if s == nil {
		return ""
	}
	return *s
}

func normalizeContext(m map[string]any) map[string]any {
	if m == nil {
		return map[string]any{}
	}
	return m
}

// firstDiff は最初に食い違う位置と前後を返す。
func firstDiff(want, got string) string {
	w, g := []rune(want), []rune(got)
	n := min(len(w), len(g))
	for i := range n {
		if w[i] != g[i] {
			lo := max(i-60, 0)
			return "  位置 " + itoa(i) +
				"\n  Python = ..." + string(w[lo:min(i+60, len(w))]) +
				"...\n  Go     = ..." + string(g[lo:min(i+60, len(g))]) + "..."
		}
	}
	if len(w) == len(g) {
		return "  差分なし"
	}
	lo := max(n-60, 0)
	if len(w) > len(g) {
		return "  Go が短い。Python の続き: ..." + string(w[lo:min(n+60, len(w))])
	}
	return "  Go が長い。Go の続き: ..." + string(g[lo:min(n+60, len(g))])
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

// TestPyRound は Python の round()（偶数丸め）と一致することを確かめる。
//
// _compute_length_hint の線形補間で使う。実際に .5 ちょうどになる
// estimated_vocab は 800（11.5）の1点しかなく、そこは偶数丸めでも
// 通常の丸めでも 12 になるため golden では違いが出ない。
// 丸め方式そのものをここで固定しておく。
//
// 期待値は Python の round() を実行して取得したもの。
func TestPyRound(t *testing.T) {
	tests := []struct {
		in   float64
		want int
	}{
		{0.5, 0}, {1.5, 2}, {2.5, 2}, {3.5, 4},
		{-0.5, 0}, {-1.5, -2}, {-2.5, -2},
		{6.5, 6}, {7.5, 8}, {9.5, 10}, {10.5, 10}, {11.5, 12}, {12.5, 12},
		{0.4, 0}, {0.6, 1}, {-0.4, 0}, {-0.6, -1},
	}
	for _, tt := range tests {
		if got := pyRound(tt.in); got != tt.want {
			t.Errorf("pyRound(%v) = %d, Python の round() は %d", tt.in, tt.want, got)
		}
	}
}

// TestComputeLengthHintBoundary は長さヒントの境界を直接押さえる。
//
// 「- 長さ」は難易度制御の実体で、外すと帯の差が消えることが ablation で
// 確認されている。段階指定（<100）と線形補間（100-1499）と自然な長さ（>=1500）の
// 継ぎ目がずれると、特定の語彙帯だけ長さが飛ぶ。
func TestComputeLengthHintBoundary(t *testing.T) {
	tests := []struct {
		vocab int
		want  string
	}{
		{0, "〜5単語"}, {59, "〜5単語"},
		{60, "〜6単語"}, {99, "〜6単語"},
		{100, "〜7単語"},
		{800, "〜12単語"}, // 11.5 の偶数丸め
		{1499, "〜16単語"},
		{1500, "自然な長さ"}, {3000, "自然な長さ"},
	}
	for _, tt := range tests {
		if got := computeLengthHint(tt.vocab); got != tt.want {
			t.Errorf("computeLengthHint(%d) = %q, want %q", tt.vocab, got, tt.want)
		}
	}
}
