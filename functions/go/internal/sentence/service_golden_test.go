package sentence

import (
	"encoding/json"
	"os"
	"reflect"
	"testing"

	"github.com/mnbst/thai-memo/functions/go/internal/wordgap"
)

type serviceGolden struct {
	TextCases []struct {
		Text         string `json:"text"`
		CompactYamok string `json:"compact_yamok"`
		StripSpaces  string `json:"strip_spaces"`
	} `json:"text_cases"`
	MatchCases []struct {
		A      string `json:"a"`
		B      string `json:"b"`
		Result bool   `json:"result"`
	} `json:"match_cases"`
	ValidateCases []struct {
		BreakdownWords []string `json:"breakdown_words"`
		TargetWords    []string `json:"target_words"`
		Missing        []string `json:"missing"`
	} `json:"validate_cases"`
	SpacingCases []struct {
		ThaiText       string   `json:"thai_text"`
		BreakdownWords []string `json:"breakdown_words"`
		ResultText     string   `json:"result_text"`
		ResultWords    []string `json:"result_words"`
	} `json:"spacing_cases"`
	RetryCases []struct {
		Prompt   string   `json:"prompt"`
		Missing  []string `json:"missing"`
		ThaiText string   `json:"thai_text"`
		Retry    string   `json:"retry"`
		Mismatch string   `json:"mismatch"`
	} `json:"retry_cases"`
	GapCases []struct {
		ThaiText  string `json:"thai_text"`
		Breakdown []struct {
			Word    string `json:"word"`
			Meaning string `json:"meaning"`
		} `json:"breakdown"`
		Gaps   [][]any `json:"gaps"`
		Prompt string  `json:"prompt"`
	} `json:"gap_cases"`
	ApplyCases []struct {
		ThaiText  string `json:"thai_text"`
		Breakdown []struct {
			Word    string `json:"word"`
			Meaning string `json:"meaning"`
		} `json:"breakdown"`
		Gaps   [][]any `json:"gaps"`
		Filled []struct {
			Word    string `json:"word"`
			Meaning string `json:"meaning"`
		} `json:"filled"`
		OK     bool `json:"ok"`
		Result []struct {
			Word    string `json:"word"`
			Meaning string `json:"meaning"`
		} `json:"result"`
	} `json:"apply_cases"`
}

func loadServiceGolden(t *testing.T) *serviceGolden {
	t.Helper()
	raw, err := os.ReadFile(
		"../../testdata/python/daily_golden/service_golden.json")
	if err != nil {
		t.Fatalf("golden の読み込みに失敗: %v", err)
	}
	var golden serviceGolden
	if err := json.Unmarshal(raw, &golden); err != nil {
		t.Fatal(err)
	}
	return &golden
}

// TestTextNormalizeGolden は ๆ の空白詰めと空白除去を Python 実装と突き合わせる。
//
// Python の \s は全角スペースや NBSP を含む。Go の \s は ASCII だけなので、
// 明示しないとここがずれる。
func TestTextNormalizeGolden(t *testing.T) {
	golden := loadServiceGolden(t)
	if len(golden.TextCases) == 0 {
		t.Fatal("golden が空")
	}

	var compacted int
	for _, c := range golden.TextCases {
		if got := CompactYamok(c.Text); got != c.CompactYamok {
			t.Errorf("CompactYamok(%q):\n  Python = %q\n  Go     = %q",
				c.Text, c.CompactYamok, got)
		}
		if got := StripSpaces(c.Text); got != c.StripSpaces {
			t.Errorf("StripSpaces(%q):\n  Python = %q\n  Go     = %q",
				c.Text, c.StripSpaces, got)
		}
		if c.CompactYamok != c.Text {
			compacted++
		}
	}
	t.Logf("%d ケース一致（ๆ の前を詰めた %d）", len(golden.TextCases), compacted)
	if compacted == 0 {
		t.Error("ๆ を詰めるケースが無い。golden が退化している")
	}
}

// TestMatchWordGolden は語の照合（ๆ の有無を同一視）を突き合わせる。
func TestMatchWordGolden(t *testing.T) {
	golden := loadServiceGolden(t)

	var matched int
	for _, c := range golden.MatchCases {
		got := MatchWord(c.A, c.B)
		if got != c.Result {
			t.Errorf("MatchWord(%q, %q): Python=%v Go=%v", c.A, c.B, c.Result, got)
		}
		if c.Result {
			matched++
		}
	}
	t.Logf("%d ケース一致（一致 %d）", len(golden.MatchCases), matched)
	if matched == 0 {
		t.Error("一致するケースが無い。golden が退化している")
	}
}

// TestValidateTargetWordsGolden はターゲット語の欠落検出を突き合わせる。
func TestValidateTargetWordsGolden(t *testing.T) {
	golden := loadServiceGolden(t)

	var withMissing int
	for i, c := range golden.ValidateCases {
		got := ValidateTargetWords(c.BreakdownWords, c.TargetWords)
		if len(c.Missing) > 0 {
			withMissing++
		}
		if !reflect.DeepEqual(normStrings(got), normStrings(c.Missing)) {
			t.Errorf("case %d:\n  breakdown = %v\n  targets   = %v\n"+
				"  Python    = %v\n  Go        = %v",
				i, c.BreakdownWords, c.TargetWords, c.Missing, got)
		}
	}
	t.Logf("%d ケース一致（欠落あり %d）", len(golden.ValidateCases), withMissing)
	if withMissing == 0 {
		t.Error("欠落ありのケースが無い。golden が退化している")
	}
}

// TestNormalizeThaiSpacingGolden は分かち書き崩壊の検出と修正を突き合わせる。
//
// 「空白位置が word_breakdown の区切りと一致」かつ「語数の 0.7 倍以上に
// 割れている」ものだけを詰める。正しい2節の文には触らない。
func TestNormalizeThaiSpacingGolden(t *testing.T) {
	golden := loadServiceGolden(t)
	if len(golden.SpacingCases) == 0 {
		t.Fatal("golden が空")
	}

	var fixed, untouched int
	for i, c := range golden.SpacingCases {
		gotText, gotWords := NormalizeThaiSpacing(c.ThaiText, c.BreakdownWords)

		if c.ResultText != c.ThaiText {
			fixed++
		} else {
			untouched++
		}

		if gotText != c.ResultText {
			t.Errorf("case %d thai_text:\n  入力   = %q\n  語     = %v\n"+
				"  Python = %q\n  Go     = %q",
				i, c.ThaiText, c.BreakdownWords, c.ResultText, gotText)
		}
		if !reflect.DeepEqual(normStrings(gotWords), normStrings(c.ResultWords)) {
			t.Errorf("case %d word_breakdown:\n  Python = %v\n  Go     = %v",
				i, c.ResultWords, gotWords)
		}
	}

	t.Logf("%d ケース一致（詰めた %d / 触らなかった %d）",
		len(golden.SpacingCases), fixed, untouched)
	if fixed == 0 || untouched == 0 {
		t.Error("詰めた・触らなかったのどちらかが踏まれていない")
	}
}

// TestRetryPromptGolden は再生成プロンプトを突き合わせる。
func TestRetryPromptGolden(t *testing.T) {
	golden := loadServiceGolden(t)

	for i, c := range golden.RetryCases {
		if got := BuildRetryPrompt(c.Prompt, c.Missing); got != c.Retry {
			t.Errorf("case %d retry:\n%s", i, firstDiff(c.Retry, got))
		}
		if got := BuildMismatchRetryPrompt(c.Prompt, c.ThaiText); got != c.Mismatch {
			t.Errorf("case %d mismatch:\n%s", i, firstDiff(c.Mismatch, got))
		}
	}
	t.Logf("%d ケース一致", len(golden.RetryCases))
}

// TestFindGapsGolden は word_breakdown の欠落検出を突き合わせる。
func TestFindGapsGolden(t *testing.T) {
	golden := loadServiceGolden(t)
	if len(golden.GapCases) == 0 {
		t.Fatal("golden が空")
	}

	var withGaps, unrepairable int
	for i, c := range golden.GapCases {
		breakdown := make([]wordgap.Word, 0, len(c.Breakdown))
		for _, w := range c.Breakdown {
			breakdown = append(breakdown, wordgap.Word{Word: w.Word, Meaning: w.Meaning})
		}

		got := wordgap.FindGaps(c.ThaiText, breakdown)
		want := decodeGaps(c.Gaps)

		if len(want) > 0 {
			withGaps++
			if want[0].Index < 0 {
				unrepairable++
			}
		}
		if !reflect.DeepEqual(normGaps(got), normGaps(want)) {
			t.Errorf("case %d:\n  thai   = %q\n  分解   = %v\n"+
				"  Python = %v\n  Go     = %v",
				i, c.ThaiText, c.Breakdown, want, got)
			continue
		}
		if len(want) > 0 {
			if gotPrompt := wordgap.BuildGapPrompt(c.ThaiText, got); gotPrompt != c.Prompt {
				t.Errorf("case %d prompt:\n%s", i, firstDiff(c.Prompt, gotPrompt))
			}
		}
	}

	t.Logf("%d ケース一致（欠落あり %d / 綴り不一致 %d）",
		len(golden.GapCases), withGaps, unrepairable)
	if withGaps == 0 || unrepairable == 0 {
		t.Error("欠落・綴り不一致のどちらかが踏まれていない")
	}
}

// TestApplyGapWordsGolden は補完結果の差し込みを突き合わせる。
func TestApplyGapWordsGolden(t *testing.T) {
	golden := loadServiceGolden(t)
	if len(golden.ApplyCases) == 0 {
		t.Fatal("golden が空")
	}

	var ok, ng int
	for i, c := range golden.ApplyCases {
		breakdown := make([]wordgap.Word, 0, len(c.Breakdown))
		for _, w := range c.Breakdown {
			breakdown = append(breakdown, wordgap.Word{Word: w.Word, Meaning: w.Meaning})
		}
		filled := make([]wordgap.Word, 0, len(c.Filled))
		for _, w := range c.Filled {
			filled = append(filled, wordgap.Word{Word: w.Word, Meaning: w.Meaning})
		}

		gotWords, gotOK := wordgap.ApplyGapWords(
			c.ThaiText, breakdown, decodeGaps(c.Gaps), filled)

		if c.OK {
			ok++
		} else {
			ng++
		}
		if gotOK != c.OK {
			t.Errorf("case %d: Python ok=%v Go ok=%v\n  thai=%q 分解=%v 補完=%v",
				i, c.OK, gotOK, c.ThaiText, c.Breakdown, c.Filled)
			continue
		}
		if !c.OK {
			continue
		}
		var want []wordgap.Word
		for _, w := range c.Result {
			want = append(want, wordgap.Word{Word: w.Word, Meaning: w.Meaning})
		}
		if !reflect.DeepEqual(gotWords, want) {
			t.Errorf("case %d の結果:\n  Python = %v\n  Go     = %v", i, want, gotWords)
		}
	}

	t.Logf("%d ケース一致（補完成功 %d / 失敗 %d）", len(golden.ApplyCases), ok, ng)
	if ok == 0 || ng == 0 {
		t.Error("成功・失敗のどちらかが踏まれていない")
	}
}

func decodeGaps(raw [][]any) []wordgap.Gap {
	out := make([]wordgap.Gap, 0, len(raw))
	for _, g := range raw {
		idx, _ := g[0].(float64)
		seg, _ := g[1].(string)
		out = append(out, wordgap.Gap{Index: int(idx), Segment: seg})
	}
	return out
}

func normGaps(g []wordgap.Gap) []wordgap.Gap {
	if g == nil {
		return []wordgap.Gap{}
	}
	return g
}

func normStrings(s []string) []string {
	if s == nil {
		return []string{}
	}
	return s
}
