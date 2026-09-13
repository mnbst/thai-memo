package sentence

import (
	"context"
	"errors"
	"testing"

	"cloud.google.com/go/firestore"

	"github.com/mnbst/thai-memo/functions/go/internal/lang"
)

// stubHistory は既出例文を固定で返す。err を入れると取得失敗を再現する。
type stubHistory struct {
	texts map[string]bool
	err   error
	calls int
}

func (h *stubHistory) SeenTexts(
	_ context.Context, _ *firestore.Client, _ string,
) (map[string]bool, error) {
	h.calls++
	if h.err != nil {
		return nil, h.err
	}
	return h.texts, nil
}

func produceOnce(t *testing.T, p *Producer) *Produced {
	t.Helper()
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
	return got
}

// バンクが既出の文を返したら LLM 生成へ落ちること。
//
// 在庫の別の文へ逃がさないのは、テーマ指定のときに頼まれたテーマから
// 外れるため（バンクは語×テーマで1本しか持たない）。
func TestProduceFallsBackToLLMWhenBankReturnsSeen(t *testing.T) {
	corpus := &stubBank{hits: []bool{true}}
	svc := &stubService{}
	hist := &stubHistory{texts: map[string]bool{goldenSentence().ThaiText: true}}
	p := &Producer{Selector: &stubSelector{}, Corpus: corpus, History: hist, Service: svc}

	got := produceOnce(t, p)

	if hist.calls != 1 {
		t.Errorf("既出の取得回数 %d, want 1（セットにつき1回）", hist.calls)
	}
	if len(svc.calls) != 1 {
		t.Fatalf("LLM 呼び出し %d 回, want 1", len(svc.calls))
	}
	if got.FromCache {
		t.Error("既出だったのに FromCache が true")
	}
}

// 既出でなければ従来どおりバンクから出す（LLM を呼ばない）。
func TestProduceUsesBankWhenNotSeen(t *testing.T) {
	corpus := &stubBank{hits: []bool{true}}
	svc := &stubService{}
	p := &Producer{
		Selector: &stubSelector{},
		Corpus:   corpus,
		History:  &stubHistory{texts: map[string]bool{"別の文": true}},
		Service:  svc,
	}

	got := produceOnce(t, p)

	if !got.FromCache {
		t.Error("未出なのにバンクから出していない")
	}
	if len(svc.calls) != 0 {
		t.Errorf("バンクに当たったのに LLM を %d 回呼んでいる", len(svc.calls))
	}
}

// セット内で同じ文を二度出さないこと（語が違っても在庫が重なりうる）。
// 2本目は LLM 生成へ落ちる。
func TestProduceBatchSkipsSentenceAlreadyPickedInSameSet(t *testing.T) {
	corpus := &stubBank{hits: []bool{true, true}}
	svc := &stubService{}
	p := &Producer{
		Selector: &batchSelector{},
		Corpus:   corpus,
		History:  &stubHistory{},
		Service:  svc,
	}

	produced, err := p.ProduceBatch(context.Background(), nil, nil, ProduceRequest{
		UID:            "uid",
		Params:         map[string]any{"topic": "指定"},
		UsePremiumSpec: true,
		SelectRetry:    1,
		Lang:           lang.JA,
	}, 2)
	if err != nil {
		t.Fatal(err)
	}
	if len(produced) != 2 {
		t.Fatalf("生成本数 %d, want 2", len(produced))
	}
	if !produced[0].FromCache {
		t.Error("1本目はバンクから出すこと")
	}
	if produced[1].FromCache {
		t.Error("2本目は同じ文なので LLM 生成へ落とすこと")
	}
	if len(svc.calls) != 1 {
		t.Errorf("LLM 呼び出し %d 回, want 1", len(svc.calls))
	}
}

// 既出の取得に失敗してもバンクは引く（重複の可能性より配信が落ちるほうが重い）。
func TestProduceContinuesWhenHistoryFails(t *testing.T) {
	corpus := &stubBank{hits: []bool{true}}
	p := &Producer{
		Selector: &stubSelector{},
		Corpus:   corpus,
		History:  &stubHistory{err: errors.New("firestore down")},
		Service:  &stubService{},
	}

	got := produceOnce(t, p)

	if !got.FromCache {
		t.Error("既出を読めなくてもバンクから出すこと")
	}
}

// free の配信（CacheOnly）は LLM へ落とせない。未出の在庫が尽きたら、
// 配信を落とすより既出をもう一度出す。
func TestProduceCacheOnlyFallsBackToSeenWhenExhausted(t *testing.T) {
	bank := &singleBank{text: "既出"}
	p := &Producer{
		Selector: &batchSelector{},
		Bank:     bank,
		History:  &stubHistory{texts: map[string]bool{"既出": true}},
		Service:  &stubService{},
	}

	produced, err := p.ProduceBatch(context.Background(), nil, nil, ProduceRequest{
		UID:         "uid",
		Params:      map[string]any{},
		CacheOnly:   true,
		SelectRetry: 2,
		Lang:        lang.JA,
	}, 1)
	if err != nil {
		t.Fatal(err)
	}
	if len(produced) != 1 || produced[0].Sentence.ThaiText != "既出" {
		t.Fatalf("既出でも配信すること: %+v", produced)
	}
	// 引き直し（2周）＋既出を許す最後の1周。
	if bank.calls != 3 {
		t.Errorf("バンク参照 %d 回, want 3", bank.calls)
	}
}

// singleBank は text の1本しか持たない。
type singleBank struct {
	text  string
	calls int
}

func (b *singleBank) Pick(
	_ context.Context, w string, _ lang.Lang, _ string,
) (*Sentence, error) {
	b.calls++
	return &Sentence{ThaiText: b.text, KeyWord: w}, nil
}
