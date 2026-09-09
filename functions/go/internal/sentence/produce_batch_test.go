package sentence

import (
	"context"
	"errors"
	"strconv"
	"sync"
	"testing"

	"cloud.google.com/go/firestore"

	"github.com/mnbst/thai-memo/functions/go/internal/lang"
	"github.com/mnbst/thai-memo/functions/go/internal/uvm"
)

// batchSelector は count 語をまとめて返す。語は全呼び出しを通して重複しない
// （実装の GetSessionWords と同じ前提）。
type batchSelector struct {
	counts []int
	topics []string
	issued int
}

func (s *batchSelector) SelectTargetWords(
	_ context.Context, _ *firestore.Client, _ uvm.FreqRank,
	_ string, params map[string]any, _ *int, count int, _ bool, _ *int, _ int,
) ([]string, string, error) {
	s.counts = append(s.counts, count)
	words := make([]string, count)
	for i := range words {
		s.issued++
		words[i] = "w" + strconv.Itoa(s.issued)
	}
	topic := "topic" + strconv.Itoa(len(s.counts))
	if t, _ := params["topic"].(string); t != "" {
		topic = t
	}
	s.topics = append(s.topics, topic)
	return words, topic, nil
}

// batchBank は hits に載せた語だけキャッシュに当たる。
type batchBank struct {
	mu    sync.Mutex
	hits  map[string]bool
	calls []pickCall
}

func (b *batchBank) Pick(_ context.Context, w string, l lang.Lang, topic string) (*Sentence, error) {
	b.mu.Lock()
	defer b.mu.Unlock()
	b.calls = append(b.calls, pickCall{w, l, topic})
	if !b.hits[w] {
		return nil, nil
	}
	s := goldenSentence()
	s.KeyWord = w
	return s, nil
}

// batchService は fail に載せた語の生成だけ失敗する。並列に呼ばれる。
type batchService struct {
	mu    sync.Mutex
	calls []generateCall
	fail  map[string]bool
}

func (s *batchService) GenerateSentence(
	_ context.Context, params map[string]any, isPremium bool,
	targetWords []string, _ int, l lang.Lang,
) (*Sentence, error) {
	s.mu.Lock()
	topic, _ := params["topic"].(string)
	s.calls = append(s.calls, generateCall{topic, isPremium, targetWords, l})
	s.mu.Unlock()
	if s.fail[targetWords[0]] {
		return nil, errors.New("LLM down")
	}
	out := goldenSentence()
	out.KeyWord = targetWords[0]
	return out, nil
}

func batchRequest(cacheOnly bool, premium bool, retry int) ProduceRequest {
	return ProduceRequest{
		UID:            "uid",
		Params:         map[string]any{},
		UsePremiumSpec: premium,
		CacheOnly:      cacheOnly,
		SelectRetry:    retry,
		Lang:           lang.JA,
	}
}

func words(got []*Produced) []string {
	out := make([]string, len(got))
	for i, p := range got {
		out[i] = p.TargetWords[0]
	}
	return out
}

// TestProduceBatchPremium は premium の5本セット: 選定は1回、生成は語ごと。
func TestProduceBatchPremium(t *testing.T) {
	sel := &batchSelector{}
	svc := &batchService{}
	p := &Producer{Selector: sel, Service: svc}

	got, err := p.ProduceBatch(context.Background(), nil, nil, batchRequest(false, true, 1), 5)
	if err != nil {
		t.Fatalf("生成に失敗: %v", err)
	}
	if len(got) != 5 {
		t.Fatalf("本数 %d, want 5", len(got))
	}
	// 選定は1回だけ。並列に引くと同じ UVM 状態を見て key_word が重複する。
	if len(sel.counts) != 1 || sel.counts[0] != 5 {
		t.Errorf("選定 %v, want [5]", sel.counts)
	}
	if len(svc.calls) != 5 {
		t.Errorf("LLM 生成 %d回, want 5", len(svc.calls))
	}
	// テーマはセットで共通。
	for _, pr := range got {
		if pr.ChosenTopic != "topic1" {
			t.Errorf("テーマ %q, want topic1", pr.ChosenTopic)
		}
	}
	// 戻り値は選定順。
	if w := words(got); len(w) != 5 || w[0] != "w1" || w[4] != "w5" {
		t.Errorf("語の並び %v, want w1..w5", w)
	}
}

// TestProduceBatchPartialFailure は一部の生成が失敗しても揃ったぶんを返すこと。
func TestProduceBatchPartialFailure(t *testing.T) {
	sel := &batchSelector{}
	svc := &batchService{fail: map[string]bool{"w2": true, "w4": true}}
	p := &Producer{Selector: sel, Service: svc}

	got, err := p.ProduceBatch(context.Background(), nil, nil, batchRequest(false, true, 1), 5)
	if err != nil {
		t.Fatalf("一部失敗はエラーにしない: %v", err)
	}
	if w := words(got); len(w) != 3 || w[0] != "w1" || w[1] != "w3" || w[2] != "w5" {
		t.Errorf("語 %v, want [w1 w3 w5]", w)
	}
}

// TestProduceBatchAllFailed は全滅したときだけエラーを返すこと。
func TestProduceBatchAllFailed(t *testing.T) {
	sel := &batchSelector{}
	svc := &batchService{fail: map[string]bool{"w1": true, "w2": true}}
	p := &Producer{Selector: sel, Service: svc}

	got, err := p.ProduceBatch(context.Background(), nil, nil, batchRequest(false, true, 1), 2)
	if err == nil {
		t.Fatalf("エラーが返らない: %v", got)
	}
}

// TestProduceBatchCacheOnlyRefill は free の配信経路。
// キャッシュに外れた語は、使用済みを除いて足りないぶんだけ引き直す。
func TestProduceBatchCacheOnlyRefill(t *testing.T) {
	sel := &batchSelector{}
	bank := &batchBank{hits: map[string]bool{"w1": true, "w3": true, "w6": true, "w7": true, "w8": true}}
	svc := &batchService{}
	p := &Producer{Selector: sel, Bank: bank, Service: svc}

	got, err := p.ProduceBatch(context.Background(), nil, nil, batchRequest(true, false, 3), 5)
	if err != nil {
		t.Fatalf("生成に失敗: %v", err)
	}
	if len(got) != 5 {
		t.Fatalf("本数 %d, want 5 (語 %v)", len(got), words(got))
	}
	// 1周目5語で2本、2周目は残り3語 → w6/w7/w8 が当たって充足。
	if len(sel.counts) != 2 || sel.counts[0] != 5 || sel.counts[1] != 3 {
		t.Errorf("選定の本数 %v, want [5 3]", sel.counts)
	}
	// 引き直しでもテーマは1周目のまま（セット内で揃える）。
	for _, pr := range got {
		if pr.ChosenTopic != "topic1" {
			t.Errorf("テーマ %q, want topic1", pr.ChosenTopic)
		}
		if !pr.FromCache {
			t.Errorf("%v がキャッシュ由来でない", pr.TargetWords)
		}
	}
	// CacheOnly では LLM を呼ばない。
	if len(svc.calls) != 0 {
		t.Errorf("LLM を %d回呼んだ", len(svc.calls))
	}
}

// TestProduceBatchCacheOnlyShort は引き直しても埋まらなければ揃ったぶんだけ返すこと。
func TestProduceBatchCacheOnlyShort(t *testing.T) {
	sel := &batchSelector{}
	bank := &batchBank{hits: map[string]bool{"w2": true}}
	p := &Producer{Selector: sel, Bank: bank, Service: &batchService{}}

	got, err := p.ProduceBatch(context.Background(), nil, nil, batchRequest(true, false, 2), 5)
	if err != nil {
		t.Fatalf("生成に失敗: %v", err)
	}
	if w := words(got); len(w) != 1 || w[0] != "w2" {
		t.Errorf("語 %v, want [w2]", w)
	}
}
