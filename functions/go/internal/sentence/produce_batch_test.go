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

// batchSelector は count 語をまとめて返す。1回の呼び出しの中では語が重複しない
// （実装の GetSessionWords と同じ前提）。
//
// テーマの付け方は実装の SelectTargetWords に合わせる:
//   - params["topic"] あり → 全部その値
//   - sharedTopic        → 全部同じ抽選値（free おまかせ）
//   - それ以外            → 語ごとに別（premium おまかせ）
type batchSelector struct {
	counts      []int
	issued      int
	sharedTopic bool
}

func (s *batchSelector) SelectTargetWords(
	_ context.Context, _ *firestore.Client, _ uvm.FreqRank,
	_ string, params map[string]any, _ *int, count int, _ bool, _ *int, _ int,
) ([]TargetWord, error) {
	s.counts = append(s.counts, count)
	pinned, _ := params["topic"].(string)
	round := "round" + strconv.Itoa(len(s.counts))

	out := make([]TargetWord, count)
	for i := range out {
		s.issued++
		topic := "topic" + strconv.Itoa(s.issued)
		switch {
		case pinned != "":
			topic = pinned
		case s.sharedTopic:
			topic = round
		}
		out[i] = TargetWord{Word: "w" + strconv.Itoa(s.issued), Topic: topic}
	}
	return out, nil
}

// repeatSelector は毎回まったく同じ語を返す（帯の候補が極端に少ない状態）。
type repeatSelector struct {
	calls int
	words []string
}

func (s *repeatSelector) SelectTargetWords(
	_ context.Context, _ *firestore.Client, _ uvm.FreqRank,
	_ string, _ map[string]any, _ *int, count int, _ bool, _ *int, _ int,
) ([]TargetWord, error) {
	s.calls++
	out := make([]TargetWord, 0, count)
	for i := 0; i < count && i < len(s.words); i++ {
		out = append(out, TargetWord{Word: s.words[i], Topic: "topic1"})
	}
	return out, nil
}

// batchBank は hits に載せた語だけキャッシュに当たる。
type batchBank struct {
	mu    sync.Mutex
	hits  map[string]bool
	calls []pickCall
}

func (b *batchBank) Pick(
	_ context.Context, w string, l lang.Lang, topic string,
) (*Sentence, error) {
	b.mu.Lock()
	defer b.mu.Unlock()
	b.calls = append(b.calls, pickCall{w, l, topic})
	if !b.hits[w] {
		return nil, nil
	}
	s := goldenSentence()
	s.KeyWord = w
	// 語ごとに別の文にする。コーパスは1本を1語の索引にしか置かないので、
	// 別の key_word で同じ本文が返ることは実際には起きない。
	s.ThaiText += w
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

// TestProduceBatchOneSelection は5本セットの選定が1回であること。
//
// 分けて引くと呼び出しをまたぐ排他が無く、同じ key_word がセットに2本入る。
func TestProduceBatchOneSelection(t *testing.T) {
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
	if len(sel.counts) != 1 || sel.counts[0] != 5 {
		t.Errorf("選定 %v, want [5]（1回で5語）", sel.counts)
	}
	if len(svc.calls) != 5 {
		t.Errorf("LLM 生成 %d回, want 5", len(svc.calls))
	}
	if w := words(got); len(w) != 5 || w[0] != "w1" || w[4] != "w5" {
		t.Errorf("語の並び %v, want w1..w5", w)
	}
}

// TestProduceBatchPremiumTopicPerWord は premium おまかせのテーマがセット内で散ること。
// 選定は1回のままなので key_word の被りは起きない。
func TestProduceBatchPremiumTopicPerWord(t *testing.T) {
	sel := &batchSelector{}
	svc := &batchService{}
	p := &Producer{Selector: sel, Service: svc}

	got, err := p.ProduceBatch(context.Background(), nil, nil, batchRequest(false, true, 1), 5)
	if err != nil {
		t.Fatalf("生成に失敗: %v", err)
	}
	for i, pr := range got {
		if want := "topic" + strconv.Itoa(i+1); pr.ChosenTopic != want {
			t.Errorf("%d本目のテーマ %q, want %q", i+1, pr.ChosenTopic, want)
		}
	}
	// LLM へ渡すテーマもその本のもの。
	topics := map[string]bool{}
	for _, c := range svc.calls {
		topics[c.topic] = true
	}
	if len(topics) != 5 {
		t.Errorf("LLM へ渡したテーマ %v, want 5種類", topics)
	}
}

// TestProduceBatchFreeSharedTopic は free おまかせがセット共通テーマのままであること。
// テーマ分布は一様抽選のまま（語→テーマに寄せると BLドラマへ偏る）。
func TestProduceBatchFreeSharedTopic(t *testing.T) {
	sel := &batchSelector{sharedTopic: true}
	p := &Producer{Selector: sel, Service: &batchService{}}

	got, err := p.ProduceBatch(context.Background(), nil, nil, batchRequest(false, false, 1), 5)
	if err != nil {
		t.Fatalf("生成に失敗: %v", err)
	}
	if len(got) != 5 {
		t.Fatalf("本数 %d, want 5", len(got))
	}
	for _, pr := range got {
		if pr.ChosenTopic != "round1" {
			t.Errorf("テーマ %q, want round1（セット共通）", pr.ChosenTopic)
		}
	}
}

// TestProduceBatchPinnedTopic はテーマ指定（premium の preferred_topic）。
func TestProduceBatchPinnedTopic(t *testing.T) {
	sel := &batchSelector{}
	p := &Producer{Selector: sel, Service: &batchService{}}

	req := batchRequest(false, true, 1)
	req.Params = map[string]any{"topic": "仕事"}
	got, err := p.ProduceBatch(context.Background(), nil, nil, req, 5)
	if err != nil {
		t.Fatalf("生成に失敗: %v", err)
	}
	if len(sel.counts) != 1 || sel.counts[0] != 5 {
		t.Errorf("選定 %v, want [5]", sel.counts)
	}
	for _, pr := range got {
		if pr.ChosenTopic != "仕事" {
			t.Errorf("テーマ %q, want 仕事", pr.ChosenTopic)
		}
	}
}

// TestProduceBatchNoDuplicateKeyWord は引き直し（CacheOnly）で同じ語を拾っても
// セットに2本入れないこと。揃わなければ本数が減るほうを選ぶ。
func TestProduceBatchNoDuplicateKeyWord(t *testing.T) {
	sel := &repeatSelector{words: []string{"w1", "w2", "w3", "w4", "w5"}}
	bank := &batchBank{hits: map[string]bool{"w1": true, "w2": true}}
	p := &Producer{Selector: sel, Bank: bank, Service: &batchService{}}

	got, err := p.ProduceBatch(context.Background(), nil, nil, batchRequest(true, false, 3), 5)
	if err != nil {
		t.Fatalf("生成に失敗: %v", err)
	}
	seen := map[string]bool{}
	for _, w := range words(got) {
		if seen[w] {
			t.Errorf("key_word %q がセットに2本入っている（語 %v）", w, words(got))
		}
		seen[w] = true
	}
	if w := words(got); len(w) != 2 || w[0] != "w1" || w[1] != "w2" {
		t.Errorf("語 %v, want [w1 w2]", w)
	}
	// 2周目以降は全部 used なのでバンクを引き直さない。
	if len(bank.calls) != 5 {
		t.Errorf("バンク照会 %d回, want 5（1周目の5語だけ）", len(bank.calls))
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
	sel := &batchSelector{sharedTopic: true}
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
	for _, pr := range got {
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
	sel := &batchSelector{sharedTopic: true}
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
