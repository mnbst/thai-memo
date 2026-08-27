package sentence

import (
	"context"
	"encoding/json"
	"os"
	"strconv"
	"testing"

	"cloud.google.com/go/firestore"

	"github.com/mnbst/thai-memo/functions/go/internal/lang"
	"github.com/mnbst/thai-memo/functions/go/internal/uvm"
)

// handlersGoldenPath は
// functions/python/scripts/daily_golden/gen_handlers_golden.py の出力。
const handlersGoldenPath = "../../../python/scripts/daily_golden/handlers_golden.json"

type handlersGolden struct {
	KeyWordLookup []struct {
		KeyWord           string `json:"key_word"`
		WantPronunciation string `json:"want_pronunciation"`
		WantMeaning       string `json:"want_meaning"`
	} `json:"key_word_lookup"`
	SentenceDoc []struct {
		Sentence       map[string]any `json:"sentence"`
		UsePremiumSpec bool           `json:"use_premium_spec"`
		Want           map[string]any `json:"want"`
	} `json:"sentence_doc"`
	Produce []struct {
		Name           string `json:"name"`
		EstimatedVocab int    `json:"estimated_vocab"`
		UsePremiumSpec bool   `json:"use_premium_spec"`
		CacheOnly      bool   `json:"cache_only"`
		SelectRetry    int    `json:"select_retry"`
		CacheHits      []bool `json:"cache_hits"`
		Calls          struct {
			Select               int    `json:"select"`
			SelectIsPremium      []bool `json:"select_is_premium"`
			SelectEstimatedVocab []int  `json:"select_estimated_vocab"`
			Pick                 []struct {
				TargetWord string `json:"target_word"`
				Lang       string `json:"lang"`
				Topic      string `json:"topic"`
			} `json:"pick"`
			Generate []struct {
				Topic       string   `json:"topic"`
				IsPremium   bool     `json:"is_premium"`
				TargetWords []string `json:"target_words"`
				Lang        string   `json:"lang"`
			} `json:"generate"`
		} `json:"calls"`
		Want *struct {
			GenerationTier string   `json:"generation_tier"`
			FromCache      bool     `json:"from_cache"`
			TargetWords    []string `json:"target_words"`
			ChosenTopic    string   `json:"chosen_topic"`
		} `json:"want"`
	} `json:"produce"`
}

func loadHandlersGolden(t *testing.T) *handlersGolden {
	t.Helper()
	b, err := os.ReadFile(handlersGoldenPath)
	if err != nil {
		t.Fatalf("golden を読めない（gen_handlers_golden.py を実行したか？）: %v", err)
	}
	var g handlersGolden
	if err := json.Unmarshal(b, &g); err != nil {
		t.Fatalf("golden の JSON 解析に失敗: %v", err)
	}
	return &g
}

// goldenSentence は生成器側の SENTENCE と同じ内容。
func goldenSentence() *Sentence {
	return &Sentence{
		ThaiText:            "ฉันกินข้าว",
		Pronunciation:       "chǎn kin khâao",
		JapaneseTranslation: "私はご飯を食べる",
		WordBreakdown: []Word{
			{Word: "ฉัน", Meaning: "私", Pronunciation: "chǎn ", Notes: ""},
			{Word: " กิน ", Meaning: " 食べる ", Pronunciation: "kin"},
			{Word: "ข้าวๆ", Meaning: "ご飯", Pronunciation: "khâao"},
		},
		Context: map[string]any{"topic": "食べ物"},
	}
}

func TestKeyWordLookupAgainstPythonGolden(t *testing.T) {
	g := loadHandlersGolden(t)
	s := goldenSentence()
	for _, c := range g.KeyWordLookup {
		if got := s.KeyWordPronunciation(c.KeyWord); got != c.WantPronunciation {
			t.Errorf("KeyWordPronunciation(%q) = %q, want %q", c.KeyWord, got, c.WantPronunciation)
		}
		if got := s.KeyWordMeaning(c.KeyWord); got != c.WantMeaning {
			t.Errorf("KeyWordMeaning(%q) = %q, want %q", c.KeyWord, got, c.WantMeaning)
		}
	}
	t.Logf("key_word の引き当て %dケース一致", len(g.KeyWordLookup))
}

func TestBuildSentenceDocAgainstPythonGolden(t *testing.T) {
	g := loadHandlersGolden(t)
	for ci, c := range g.SentenceDoc {
		s, err := FromMap(c.Sentence)
		if err != nil {
			t.Fatalf("case %d: 例文を読めない: %v", ci, err)
		}
		doc := s.BuildSentenceDoc("กิน", c.UsePremiumSpec)
		// created_at（SERVER_TIMESTAMP）は比較対象外。
		delete(doc, "created_at")

		normalizeNotes(c.Want)
		gotJSON, _ := json.Marshal(doc)
		wantJSON, _ := json.Marshal(c.Want)
		var got, want any
		_ = json.Unmarshal(gotJSON, &got)
		_ = json.Unmarshal(wantJSON, &want)
		if !jsonEqual(got, want) {
			t.Fatalf("case %d:\n got=%s\nwant=%s", ci, gotJSON, wantJSON)
		}
	}
	t.Logf("保存する例文ドキュメント %dケース一致", len(g.SentenceDoc))
}

// stubSelector は毎回 w1/topic1, w2/topic2 ... を返す（Python 側の fake と同じ）。
type stubSelector struct {
	calls          int
	isPremium      []bool
	estimatedVocab []int
	maxVocab       []*int
}

func (s *stubSelector) SelectTargetWords(
	_ context.Context, _ *firestore.Client, _ uvm.FreqRank,
	_ string, _ map[string]any, maxVocab *int, _ int, isPremium bool, estimatedVocab *int,
) ([]string, string, error) {
	s.calls++
	s.isPremium = append(s.isPremium, isPremium)
	s.maxVocab = append(s.maxVocab, maxVocab)
	v := 0
	if estimatedVocab != nil {
		v = *estimatedVocab
	}
	s.estimatedVocab = append(s.estimatedVocab, v)
	return []string{fmtWord(s.calls)}, fmtTopic(s.calls), nil
}

func fmtWord(n int) string  { return "w" + strconv.Itoa(n) }
func fmtTopic(n int) string { return "topic" + strconv.Itoa(n) }

type pickCall struct {
	targetWord string
	l          lang.Lang
	topic      string
}

type stubBank struct {
	hits  []bool
	calls []pickCall
}

func (b *stubBank) Pick(_ context.Context, targetWord string, l lang.Lang, topic string) (*Sentence, error) {
	b.calls = append(b.calls, pickCall{targetWord, l, topic})
	i := len(b.calls) - 1
	if i < len(b.hits) && b.hits[i] {
		s := goldenSentence()
		s.KeyWord = targetWord
		return s, nil
	}
	return nil, nil
}

type generateCall struct {
	topic       string
	isPremium   bool
	targetWords []string
	l           lang.Lang
}

type stubService struct{ calls []generateCall }

func (s *stubService) GenerateSentence(
	_ context.Context, params map[string]any, isPremium bool,
	targetWords []string, _ int, l lang.Lang,
) (*Sentence, error) {
	topic, _ := params["topic"].(string)
	s.calls = append(s.calls, generateCall{topic, isPremium, targetWords, l})
	return goldenSentence(), nil
}

func TestProduceAgainstPythonGolden(t *testing.T) {
	g := loadHandlersGolden(t)
	for _, c := range g.Produce {
		sel := &stubSelector{}
		bank := &stubBank{hits: c.CacheHits}
		svc := &stubService{}
		p := &Producer{Selector: sel, Bank: bank, Service: svc}

		got, err := p.Produce(context.Background(), nil, nil, ProduceRequest{
			UID:            "uid",
			Params:         map[string]any{"topic": "指定"},
			UsePremiumSpec: c.UsePremiumSpec,
			EstimatedVocab: c.EstimatedVocab,
			CacheOnly:      c.CacheOnly,
			SelectRetry:    c.SelectRetry,
			Lang:           lang.JA,
		})
		if err != nil {
			t.Fatalf("%s: %v", c.Name, err)
		}

		if sel.calls != c.Calls.Select {
			t.Errorf("%s: 単語選定の回数 %d, want %d", c.Name, sel.calls, c.Calls.Select)
		}
		// use_premium_prompt_for_vocab の結果（語彙スコアで変わる）と、
		// そこから決まる語彙上限が選定へ正しく渡っているか。
		for i, want := range c.Calls.SelectIsPremium {
			if i >= len(sel.isPremium) {
				break
			}
			if sel.isPremium[i] != want {
				t.Errorf("%s: 選定[%d] の premium 判定 = %v, want %v",
					c.Name, i, sel.isPremium[i], want)
			}
			wantMax := sel.maxVocab[i] == nil
			if want != wantMax {
				t.Errorf("%s: 選定[%d] premium=%v なのに語彙上限が %v",
					c.Name, i, want, sel.maxVocab[i])
			}
		}
		for i, want := range c.Calls.SelectEstimatedVocab {
			if i < len(sel.estimatedVocab) && sel.estimatedVocab[i] != want {
				t.Errorf("%s: 選定[%d] の語彙スコア = %d, want %d",
					c.Name, i, sel.estimatedVocab[i], want)
			}
		}
		if len(bank.calls) != len(c.Calls.Pick) {
			t.Fatalf("%s: キャッシュ参照の回数 %d, want %d",
				c.Name, len(bank.calls), len(c.Calls.Pick))
		}
		for i, want := range c.Calls.Pick {
			if bank.calls[i].targetWord != want.TargetWord ||
				string(bank.calls[i].l) != want.Lang ||
				bank.calls[i].topic != want.Topic {
				t.Errorf("%s: キャッシュ参照[%d] = %+v, want %+v",
					c.Name, i, bank.calls[i], want)
			}
		}
		if len(svc.calls) != len(c.Calls.Generate) {
			t.Fatalf("%s: LLM 生成の回数 %d, want %d",
				c.Name, len(svc.calls), len(c.Calls.Generate))
		}
		for i, want := range c.Calls.Generate {
			if svc.calls[i].topic != want.Topic ||
				svc.calls[i].isPremium != want.IsPremium ||
				string(svc.calls[i].l) != want.Lang ||
				!equalStringSlices(svc.calls[i].targetWords, want.TargetWords) {
				t.Errorf("%s: LLM 生成[%d] = %+v, want %+v",
					c.Name, i, svc.calls[i], want)
			}
		}

		if c.Want == nil {
			if got != nil {
				t.Errorf("%s: 配信しないはずが %+v", c.Name, got)
			}
			continue
		}
		if got == nil {
			t.Fatalf("%s: nil が返った", c.Name)
		}
		if got.Sentence.GenerationTier != c.Want.GenerationTier {
			t.Errorf("%s: generation_tier = %q, want %q",
				c.Name, got.Sentence.GenerationTier, c.Want.GenerationTier)
		}
		if got.FromCache != c.Want.FromCache {
			t.Errorf("%s: from_cache = %v, want %v", c.Name, got.FromCache, c.Want.FromCache)
		}
		if !equalStringSlices(got.TargetWords, c.Want.TargetWords) {
			t.Errorf("%s: target_words = %v, want %v",
				c.Name, got.TargetWords, c.Want.TargetWords)
		}
		if got.ChosenTopic != c.Want.ChosenTopic {
			t.Errorf("%s: chosen_topic = %q, want %q",
				c.Name, got.ChosenTopic, c.Want.ChosenTopic)
		}
	}
	t.Logf("生成コアの制御 %dケース一致", len(g.Produce))
}

// normalizeNotes は Python 側の word_breakdown に notes を補う。
//
// Python は LLM の dict をそのまま保存するので、notes が無い語では
// キーごと欠ける。Go は構造体なので必ず notes を書く（空文字）。
// 読み手（クライアント・generateQuiz）はどちらも欠損を空文字として
// 扱うので、揃えたうえで比べる。
func normalizeNotes(doc map[string]any) {
	words, ok := doc["word_breakdown"].([]any)
	if !ok {
		return
	}
	for _, w := range words {
		m, ok := w.(map[string]any)
		if !ok {
			continue
		}
		if _, ok := m["notes"]; !ok {
			m["notes"] = ""
		}
	}
}

func jsonEqual(a, b any) bool {
	ab, _ := json.Marshal(a)
	bb, _ := json.Marshal(b)
	return string(ab) == string(bb)
}
