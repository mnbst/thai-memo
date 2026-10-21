package sentence

import (
	"context"
	"errors"
	"sync"
	"testing"
)

// stubChecker は bad に載せた key_word を不合格にする。
type stubChecker struct {
	mu    sync.Mutex
	bad   map[string]bool
	err   error
	calls []CheckInput
}

func (c *stubChecker) Check(_ context.Context, in CheckInput) (CheckResult, error) {
	c.mu.Lock()
	c.calls = append(c.calls, in)
	c.mu.Unlock()
	if c.err != nil {
		return CheckResult{}, c.err
	}
	if c.bad[in.KeyWord] {
		return CheckResult{Notes: []string{"共起がおかしい"}, Reason: "共起 0.62", Model: "m"}, nil
	}
	return CheckResult{Model: "m"}, nil
}

// 判定は1文1回だけ。不合格の文は作り直さずセットから外す（残りの本数で返す）。
func TestQualityCheckDropsFlaggedWithoutRetry(t *testing.T) {
	svc := &batchService{}
	chk := &stubChecker{bad: map[string]bool{"w2": true}}
	p := &Producer{Selector: &batchSelector{}, Service: svc, Checker: chk}
	req := batchRequest(false, true, 1)
	req.QualityCheck = true

	got, err := p.ProduceBatch(context.Background(), nil, nil, req, 3)
	if err != nil {
		t.Fatal(err)
	}
	if len(chk.calls) != 3 {
		t.Errorf("判定回数 = %d, want 3", len(chk.calls))
	}
	if len(got) != 2 {
		t.Fatalf("不合格の1本を外して2本のはず: %d", len(got))
	}
	for _, pr := range got {
		if pr.TargetWords[0] == "w2" || pr.Quality == nil || !pr.Quality.Passed {
			t.Errorf("不合格の文が残っている: %s %+v", pr.TargetWords[0], pr.Quality)
		}
		if pr.Sentence.GenerationTier != "premium" {
			t.Errorf("%s: tier=%q", pr.TargetWords[0], pr.Sentence.GenerationTier)
		}
	}
	for _, in := range chk.calls {
		if in.UID != "uid" {
			t.Errorf("判定の入力が違う: %+v", in)
		}
	}

	// 全部外れたら ErrQualityRejected。
	chk = &stubChecker{bad: map[string]bool{"w1": true}}
	p = &Producer{Selector: &batchSelector{}, Service: &batchService{}, Checker: chk}
	got, err = p.ProduceBatch(context.Background(), nil, nil, req, 1)
	if !errors.Is(err, ErrQualityRejected) || len(got) != 0 {
		t.Errorf("全滅なのに %v %v", got, err)
	}
}

// QualityCheck が偽なら判定しない（通常生成は今は判定しない）。
func TestQualityCheckOffByRequest(t *testing.T) {
	chk := &stubChecker{bad: map[string]bool{"w1": true}}
	p := &Producer{Selector: &batchSelector{}, Service: &batchService{}, Checker: chk}
	if _, err := p.ProduceBatch(context.Background(), nil, nil, batchRequest(false, true, 1), 2); err != nil {
		t.Fatal(err)
	}
	if len(chk.calls) != 0 {
		t.Errorf("QualityCheck=false なのに判定した: %d", len(chk.calls))
	}
}

// 判定が失敗しても元の文で続ける（生成・配信を止めない）。
func TestQualityCheckFailOpen(t *testing.T) {
	req := batchRequest(false, true, 1)
	req.QualityCheck = true

	p := &Producer{Selector: &batchSelector{}, Service: &batchService{},
		Checker: &stubChecker{err: errors.New("jev down")}}
	got, err := p.ProduceBatch(context.Background(), nil, nil, req, 2)
	if err != nil || len(got) != 2 {
		t.Fatalf("判定失敗で元の文を返していない: %v %v", got, err)
	}
	// 判定できなかった文は quality を持たない（プールに入らない）。
	if got[0].Quality != nil {
		t.Errorf("判定失敗なのに quality がある: %+v", got[0].Quality)
	}

}

// バンク・コーパス由来の文は判定しない（判定済み）。
func TestQualityCheckSkipsCache(t *testing.T) {
	// バンクに当たる w1 だけを不合格にする。判定されれば回数が増える。
	chk := &stubChecker{bad: map[string]bool{"w1": true}}
	bank := &batchBank{hits: map[string]bool{"w1": true}}
	p := &Producer{Selector: &batchSelector{}, Corpus: bank, Service: &batchService{}, Checker: chk}
	req := batchRequest(false, true, 1)
	req.QualityCheck = true
	if _, err := p.ProduceBatch(context.Background(), nil, nil, req, 2); err != nil {
		t.Fatal(err)
	}
	if len(chk.calls) != 1 {
		t.Errorf("LLM 生成の1本だけ判定するはず: %d", len(chk.calls))
	}
}
