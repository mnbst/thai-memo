package sentence

import (
	"context"
	"encoding/json"
	"errors"
	"os"
	"reflect"
	"testing"

	"github.com/mnbst/thai-memo/functions/go/internal/lang"
	"github.com/mnbst/thai-memo/functions/go/internal/thainlp"
)

// generate_golden.json は
// functions/python/scripts/daily_golden/gen_generate_golden.py が
// 本物の sentence_service.py を動かして書き出したもの。
// LLM 呼び出しと NLP 後処理だけ差し替え、制御フローは本物のまま。

type generateGolden struct {
	LocalizePOS []struct {
		Label  string `json:"label"`
		Lang   string `json:"lang"`
		Result string `json:"result"`
	} `json:"localize_pos"`

	ApplyResponseCompat []struct {
		Sentence        map[string]any `json:"sentence"`
		ResolvedContext map[string]any `json:"resolved_context"`
		Result          map[string]any `json:"result"`
	} `json:"apply_response_compat"`

	Enrich []struct {
		Words    []string `json:"words"`
		Lang     string   `json:"lang"`
		Enriched []struct {
			Syllables       []string `json:"syllables"`
			Pronunciation   string   `json:"pronunciation"`
			GrammaticalRole string   `json:"grammatical_role"`
		} `json:"enriched"`
		Pronunciation string `json:"pronunciation"`
	} `json:"enrich"`

	GenerateSingle []struct {
		Name        string            `json:"name"`
		Prompt      string            `json:"prompt"`
		TargetWords []string          `json:"target_words"`
		Responses   []json.RawMessage `json:"responses"`
		OK          bool              `json:"ok"`
		Result      map[string]any    `json:"result"`
		Error       string            `json:"error"`
		Calls       []struct {
			Prompt    string `json:"prompt"`
			TierLabel string `json:"tier_label"`
			IsPremium bool   `json:"is_premium"`
		} `json:"calls"`
	} `json:"generate_single"`
}

func loadGenerateGolden(t *testing.T) *generateGolden {
	t.Helper()
	raw, err := os.ReadFile("../../../python/scripts/daily_golden/generate_golden.json")
	if err != nil {
		t.Fatalf("golden の読み込みに失敗: %v", err)
	}
	var g generateGolden
	if err := json.Unmarshal(raw, &g); err != nil {
		t.Fatal(err)
	}
	return &g
}

func TestLocalizePOSGolden(t *testing.T) {
	g := loadGenerateGolden(t)
	for i, c := range g.LocalizePOS {
		got := thainlp.LocalizePOS(c.Label, lang.Resolve(c.Lang))
		if got != c.Result {
			t.Errorf("[%d] label=%q lang=%s got %q want %q",
				i, c.Label, c.Lang, got, c.Result)
		}
	}
	t.Logf("%d ケース一致", len(g.LocalizePOS))
}

// TestApplyResponseCompatGolden は target_notes の展開と context の注入を見る。
//
// notes の引き当ては完全一致が先で、外れたときだけ ๆ の表記ゆれを吸収する。
// 走査順で結果が変わるので、Python の dict の順序と揃っている必要がある。
func TestApplyResponseCompatGolden(t *testing.T) {
	g := loadGenerateGolden(t)
	withNote := 0
	for i, c := range g.ApplyResponseCompat {
		s, err := FromMap(c.Sentence)
		if err != nil {
			t.Fatalf("[%d] %v", i, err)
		}
		ApplyResponseCompat(s, c.ResolvedContext)

		want, err := FromMap(c.Result)
		if err != nil {
			t.Fatalf("[%d] %v", i, err)
		}
		for _, w := range want.WordBreakdown {
			if w.Notes != "" {
				withNote++
			}
		}
		if !reflect.DeepEqual(s.WordBreakdown, want.WordBreakdown) {
			t.Fatalf("[%d] word_breakdown 不一致\ngot  %+v\nwant %+v",
				i, s.WordBreakdown, want.WordBreakdown)
		}
		if !reflect.DeepEqual(normalizeMap(s.Context), normalizeMap(want.Context)) {
			t.Fatalf("[%d] context 不一致\ngot  %v\nwant %v",
				i, s.Context, want.Context)
		}
		if len(s.TargetNotes) != 0 {
			t.Fatalf("[%d] target_notes が残っている: %v", i, s.TargetNotes)
		}
	}
	t.Logf("%d ケース一致（notes が付いた語 %d）", len(g.ApplyResponseCompat), withNote)
}

func normalizeMap(m map[string]any) map[string]any {
	if len(m) == 0 {
		return nil
	}
	return m
}

// scriptedGenerator は golden に記録された応答を順に返す。
type scriptedGenerator struct {
	responses []json.RawMessage
	calls     []struct {
		prompt    string
		tierLabel string
		isPremium bool
	}
}

func (g *scriptedGenerator) GenerateSentence(
	_ context.Context, _, prompt string, isPremium bool,
	tierLabel string, _ map[string]any,
) (map[string]any, error) {
	g.calls = append(g.calls, struct {
		prompt    string
		tierLabel string
		isPremium bool
	}{prompt, tierLabel, isPremium})

	if len(g.responses) == 0 {
		return nil, errors.New("LLM_API_ERROR: no more responses")
	}
	next := g.responses[0]
	g.responses = g.responses[1:]

	// 文字列の応答はエラーを表す。
	var errMsg string
	if err := json.Unmarshal(next, &errMsg); err == nil {
		return nil, errors.New(errMsg)
	}
	var obj map[string]any
	if err := json.Unmarshal(next, &obj); err != nil {
		return nil, err
	}
	return obj, nil
}

// TestGenerateSingleGolden はやり直しの制御フローを Python と突き合わせる。
//
// 見るのは「何回・どのプロンプトで LLM を叩いたか」と最終結果。ここが
// ずれると、直らない失敗を再生成し続けたり、直せる失敗を諦めたりする。
func TestGenerateSingleGolden(t *testing.T) {
	g := loadGenerateGolden(t)
	for _, c := range g.GenerateSingle {
		t.Run(c.Name, func(t *testing.T) {
			gen := &scriptedGenerator{responses: append([]json.RawMessage(nil), c.Responses...)}
			got, err := GenerateSingle(context.Background(), gen, Request{
				SystemPrompt: "SYS",
				Prompt:       c.Prompt,
				TierLabel:    "free",
				TargetWords:  c.TargetWords,
				Lang:         lang.JA,
				// NLP は Python 側でも差し替えているので何もしない。
				Enrich: func(*Sentence, lang.Lang) {},
			})

			if len(gen.calls) != len(c.Calls) {
				t.Fatalf("呼び出し回数 %d want %d", len(gen.calls), len(c.Calls))
			}
			for i, want := range c.Calls {
				if gen.calls[i].prompt != want.Prompt {
					t.Errorf("[%d] prompt=%q want %q", i, gen.calls[i].prompt, want.Prompt)
				}
				if gen.calls[i].tierLabel != want.TierLabel {
					t.Errorf("[%d] tier=%q want %q", i, gen.calls[i].tierLabel, want.TierLabel)
				}
			}

			if !c.OK {
				if err == nil {
					t.Fatalf("エラーになるはず（got %+v）", got)
				}
				if err.Error() != c.Error {
					t.Errorf("error=%q want %q", err.Error(), c.Error)
				}
				return
			}
			if err != nil {
				t.Fatalf("予期しないエラー: %v", err)
			}

			want, ferr := FromMap(c.Result)
			if ferr != nil {
				t.Fatal(ferr)
			}
			if got.ThaiText != want.ThaiText {
				t.Errorf("thai_text=%q want %q", got.ThaiText, want.ThaiText)
			}
			if !reflect.DeepEqual(got.WordBreakdown, want.WordBreakdown) {
				t.Errorf("word_breakdown 不一致\ngot  %+v\nwant %+v",
					got.WordBreakdown, want.WordBreakdown)
			}
			if got.Pronunciation != want.Pronunciation {
				t.Errorf("pronunciation=%q want %q", got.Pronunciation, want.Pronunciation)
			}
		})
	}
	t.Logf("%d ケース一致", len(g.GenerateSingle))
}

// TestEnrichGolden は音節分割・発音・品詞の付与を Python 実装と突き合わせる。
//
// 素材は scripts/output/ にある実際の生成結果の word_breakdown。個々の変換は
// internal/thainlp が別途差分テスト済みなので、ここで見るのは組み合わせ方
// （一括タグ付けで埋まらなかった語の引き直し、文全体の発音の作り方）。
func TestEnrichGolden(t *testing.T) {
	g := loadGenerateGolden(t)
	if len(g.Enrich) == 0 {
		t.Fatal("enrich のケースが無い")
	}
	for i, c := range g.Enrich {
		got, pronunciation, _ := thainlp.Enrich(c.Words, lang.Resolve(c.Lang))
		if len(got) != len(c.Enriched) {
			t.Fatalf("[%d] 語数 %d want %d", i, len(got), len(c.Enriched))
		}
		for j, want := range c.Enriched {
			if !equalStrings(got[j].Syllables, want.Syllables) {
				t.Errorf("[%d][%d] %q syllables=%v want %v",
					i, j, c.Words[j], got[j].Syllables, want.Syllables)
			}
			if got[j].Pronunciation != want.Pronunciation {
				t.Errorf("[%d][%d] %q pronunciation=%q want %q",
					i, j, c.Words[j], got[j].Pronunciation, want.Pronunciation)
			}
			if got[j].GrammaticalRole != want.GrammaticalRole {
				t.Errorf("[%d][%d] %q role=%q want %q",
					i, j, c.Words[j], got[j].GrammaticalRole, want.GrammaticalRole)
			}
		}
		if pronunciation != c.Pronunciation {
			t.Errorf("[%d] 文全体の発音=%q want %q", i, pronunciation, c.Pronunciation)
		}
	}
	t.Logf("%d ケース一致", len(g.Enrich))
}

// equalStrings は nil と空スライスを同じとみなす（Python の [] との比較用）。
func equalStrings(a, b []string) bool {
	if len(a) != len(b) {
		return false
	}
	for i := range a {
		if a[i] != b[i] {
			return false
		}
	}
	return true
}

// TestEnrichKeepsPronunciationOnEmptyBreakdown は、word_breakdown が空の
// ときに既存の発音を消さないことを見る。
//
// golden では拾えない。LLM から来たばかりの文は発音を持たないので、空で
// 上書きしても結果が変わらないため。効くのは欠落補完のあと（1 回目の後処理や
// RepairPronunciation で発音が入っている状態）に、作り直した word_breakdown が
// 空になった場合。そこで消すと、発音の無い文がそのままクライアントへ出る。
//
// 空文字の語が並んでいる場合は逆に上書きする。Python も語のリストが空でない
// 限り代入するので、そちらに揃えている。
func TestEnrichKeepsPronunciationOnEmptyBreakdown(t *testing.T) {
	cases := []struct {
		name          string
		breakdown     []Word
		wantPronounce string
	}{
		{"word_breakdown が空", nil, "chǎn kin khâao"},
		{"空文字の語が1つ", []Word{{Word: ""}}, ""},
		{"空文字の語が2つ", []Word{{Word: ""}, {Word: ""}}, " "},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			s := &Sentence{
				ThaiText:      "ฉันกินข้าว",
				Pronunciation: "chǎn kin khâao",
				WordBreakdown: tc.breakdown,
			}
			EnrichWithNLP(s, lang.JA)
			if s.Pronunciation != tc.wantPronounce {
				t.Errorf("発音=%q want %q", s.Pronunciation, tc.wantPronounce)
			}
		})
	}
}
