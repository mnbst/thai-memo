package sentence

import (
	"context"
	"math/rand"
	"testing"

	"github.com/mnbst/thai-memo/functions/go/internal/lang"
)

// TestProducePremiumUsesCorpus は premium が静的コーパスを先に引くこと。
//
// free 例文バンク（Bank）は引かない。出どころはティアで分かれていて、
// free 側の挙動は従来のまま（handlers_golden.json がそれを押さえている）。
func TestProducePremiumUsesCorpus(t *testing.T) {
	corpus := &stubBank{hits: []bool{true}}
	free := &stubBank{hits: []bool{true}}
	svc := &stubService{}
	p := &Producer{Selector: &stubSelector{}, Bank: free, Corpus: corpus, Service: svc}

	got, err := p.Produce(context.Background(), nil, nil, ProduceRequest{
		UID:            "uid",
		Params:         map[string]any{"topic": "指定"},
		UsePremiumSpec: true,
		EstimatedVocab: 42,
		SelectRetry:    1,
		Lang:           lang.JA,
	})
	if err != nil {
		t.Fatal(err)
	}
	if len(corpus.calls) != 1 {
		t.Fatalf("コーパス参照の回数 %d, want 1", len(corpus.calls))
	}
	if len(free.calls) != 0 {
		t.Errorf("premium なのに free 例文バンクを %d 回引いている", len(free.calls))
	}
	if len(svc.calls) != 0 {
		t.Errorf("コーパスに当たったのに LLM を %d 回呼んでいる", len(svc.calls))
	}
	if !got.FromCache {
		t.Error("FromCache が false")
	}
	if got.Sentence.GenerationTier != "premium" {
		t.Errorf("generation_tier = %q, want premium", got.Sentence.GenerationTier)
	}
}

// TestProducePremiumCorpusMissFallsBackToLLM はコーパスに無い語だけ LLM へ
// 落ちること。コーパスのランク上限より先へ進んだ人がここを通る。
func TestProducePremiumCorpusMissFallsBackToLLM(t *testing.T) {
	corpus := &stubBank{hits: []bool{false}}
	svc := &stubService{}
	p := &Producer{Selector: &stubSelector{}, Corpus: corpus, Service: svc}

	got, err := p.Produce(context.Background(), nil, nil, ProduceRequest{
		UID:            "uid",
		Params:         map[string]any{"topic": "指定"},
		UsePremiumSpec: true,
		EstimatedVocab: 42,
		SelectRetry:    1,
		Lang:           lang.JA,
	})
	if err != nil {
		t.Fatal(err)
	}
	if len(svc.calls) != 1 {
		t.Fatalf("LLM 生成の回数 %d, want 1", len(svc.calls))
	}
	if got.FromCache {
		t.Error("FromCache が true")
	}
}

func corpusBankStub(sentences ...Sentence) *CorpusBank {
	index := map[string][]Sentence{}
	for _, s := range sentences {
		index[s.KeyWord] = append(index[s.KeyWord], s)
	}
	return &CorpusBank{
		Rand:  rand.New(rand.NewSource(1)),
		index: map[lang.Lang]map[string][]Sentence{lang.JA: index},
	}
}

func corpusSentence(keyWord, topic, text string) Sentence {
	return Sentence{
		ThaiText:      text,
		KeyWord:       keyWord,
		WordBreakdown: []Word{{Word: keyWord, Meaning: "意味"}},
		Context:       map[string]any{"topic": topic},
	}
}

func TestCorpusBankPickPrefersTopic(t *testing.T) {
	bank := corpusBankStub(
		corpusSentence("ฉัน", "食べ物", "a"),
		corpusSentence("ฉัน", "旅行", "b"),
	)
	got, err := bank.Pick(context.Background(), "ฉัน", lang.JA, "旅行")
	if err != nil {
		t.Fatal(err)
	}
	if got.ThaiText != "b" {
		t.Errorf("thai_text = %q, want b", got.ThaiText)
	}
}

// テーマが無くても諦めない。語ごとに平均4.5テーマしか無いので、
// ここで nil を返すとテーマ指定のたびに LLM を呼ぶことになる。
func TestCorpusBankPickFallsBackWhenTopicMissing(t *testing.T) {
	bank := corpusBankStub(corpusSentence("ฉัน", "食べ物", "a"))
	got, err := bank.Pick(context.Background(), "ฉัน", lang.JA, "宗教・信仰")
	if err != nil {
		t.Fatal(err)
	}
	if got == nil || got.ThaiText != "a" {
		t.Fatalf("テーマ違いでも1本返すこと: %+v", got)
	}
}

func TestCorpusBankPickUnknownWordReturnsNil(t *testing.T) {
	bank := corpusBankStub(corpusSentence("ฉัน", "食べ物", "a"))
	got, err := bank.Pick(context.Background(), "ไม่มี", lang.JA, "")
	if err != nil {
		t.Fatal(err)
	}
	if got != nil {
		t.Errorf("コーパスに無い語は nil を返すこと: %+v", got)
	}
}

// 返した文への変更がバンクへ伝播しないこと（generation_tier を足すのは
// 呼び出し側で、バンクはインスタンスの寿命ぶん使い回される）。
func TestCorpusBankPickDoesNotShareState(t *testing.T) {
	bank := corpusBankStub(corpusSentence("ฉัน", "食べ物", "a"))
	first, err := bank.Pick(context.Background(), "ฉัน", lang.JA, "")
	if err != nil {
		t.Fatal(err)
	}
	first.GenerationTier = "premium"
	first.WordBreakdown[0].Meaning = "書き換え"

	second, err := bank.Pick(context.Background(), "ฉัน", lang.JA, "")
	if err != nil {
		t.Fatal(err)
	}
	if second.GenerationTier != "" {
		t.Errorf("generation_tier が残っている: %q", second.GenerationTier)
	}
	if second.WordBreakdown[0].Meaning != "意味" {
		t.Errorf("word_breakdown が書き換わっている: %q", second.WordBreakdown[0].Meaning)
	}
}
