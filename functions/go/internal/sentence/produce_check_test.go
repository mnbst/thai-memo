package sentence

import (
	"context"
	"errors"
	"sync"
	"testing"

	"github.com/mnbst/thai-memo/functions/go/internal/lang"
)

// notesService は差し戻しに対応した生成器。notes 付きの呼び出しは本文に
// "retried" を付けて返す。
type notesService struct {
	batchService
	mu        sync.Mutex
	notes     [][]string
	retryFail bool
}

func (s *notesService) GenerateSentenceWithNotes(
	ctx context.Context, params map[string]any, isPremium bool,
	targetWords []string, vocab int, l lang.Lang, notes []string,
) (*Sentence, error) {
	s.mu.Lock()
	s.notes = append(s.notes, notes)
	s.mu.Unlock()
	if s.retryFail {
		return nil, errors.New("LLM down")
	}
	out, err := s.GenerateSentence(ctx, params, isPremium, targetWords, vocab, l)
	if err != nil {
		return nil, err
	}
	out.ThaiText = "retried"
	return out, nil
}

// stubChecker は bad に載せた key_word を不合格にする。
// badRetry が真なら作り直し後（Stage=retry）も不合格にする。
type stubChecker struct {
	mu       sync.Mutex
	bad      map[string]bool
	badRetry bool
	err      error
	calls    []CheckInput
}

func (c *stubChecker) Check(_ context.Context, in CheckInput) (CheckResult, error) {
	c.mu.Lock()
	c.calls = append(c.calls, in)
	c.mu.Unlock()
	if c.err != nil {
		return CheckResult{}, c.err
	}
	if c.bad[in.KeyWord] && (in.Stage == "first" || c.badRetry) {
		return CheckResult{Notes: []string{"共起がおかしい"}, Reason: "共起 0.62", Model: "m"}, nil
	}
	return CheckResult{Model: "m"}, nil
}

func TestQualityCheckRetriesOnlyFlagged(t *testing.T) {
	svc := &notesService{}
	chk := &stubChecker{bad: map[string]bool{"w2": true}}
	p := &Producer{Selector: &batchSelector{}, Service: svc, Checker: chk}
	req := batchRequest(false, true, 1)
	req.QualityCheck = true

	got, err := p.ProduceBatch(context.Background(), nil, nil, req, 3)
	if err != nil {
		t.Fatal(err)
	}
	// 3本の生成直後 + 作り直した1本の再判定。
	if len(chk.calls) != 4 {
		t.Errorf("判定回数 = %d, want 4", len(chk.calls))
	}
	for _, pr := range got {
		retried := pr.Sentence.ThaiText == "retried"
		if retried != (pr.TargetWords[0] == "w2") {
			t.Errorf("%s: 作り直し=%v", pr.TargetWords[0], retried)
		}
		// 作り直した文にもティアが付く。
		if pr.Sentence.GenerationTier != "premium" {
			t.Errorf("%s: tier=%q", pr.TargetWords[0], pr.Sentence.GenerationTier)
		}
		q := pr.Quality
		if q == nil || !q.Passed || q.Retried != retried {
			t.Errorf("%s: quality = %+v", pr.TargetWords[0], q)
		}
	}
	if len(svc.notes) != 1 || svc.notes[0][0] != "共起がおかしい" {
		t.Errorf("指摘を差し戻しに渡していない: %v", svc.notes)
	}
}

// 作り直しても不合格なら、作り直した文を Passed=false で返す（プールに入らない）。
func TestQualityCheckRetryStillFails(t *testing.T) {
	chk := &stubChecker{bad: map[string]bool{"w1": true}, badRetry: true}
	p := &Producer{Selector: &batchSelector{}, Service: &notesService{}, Checker: chk}
	req := batchRequest(false, true, 1)
	req.QualityCheck = true

	got, err := p.ProduceBatch(context.Background(), nil, nil, req, 1)
	if err != nil {
		t.Fatal(err)
	}
	q := got[0].Quality
	if got[0].Sentence.ThaiText != "retried" || q == nil || q.Passed || !q.Retried || q.Reason != "共起 0.62" {
		t.Fatalf("作り直し後の不合格が記録されていない: %q %+v", got[0].Sentence.ThaiText, q)
	}
	if chk.calls[1].Stage != "retry" || chk.calls[1].UID != "uid" {
		t.Errorf("再判定の入力が違う: %+v", chk.calls[1])
	}
}

// QualityCheck が偽なら判定しない（通常生成は今は判定しない）。
func TestQualityCheckOffByRequest(t *testing.T) {
	chk := &stubChecker{bad: map[string]bool{"w1": true}}
	p := &Producer{Selector: &batchSelector{}, Service: &notesService{}, Checker: chk}
	if _, err := p.ProduceBatch(context.Background(), nil, nil, batchRequest(false, true, 1), 2); err != nil {
		t.Fatal(err)
	}
	if len(chk.calls) != 0 {
		t.Errorf("QualityCheck=false なのに判定した: %d", len(chk.calls))
	}
}

// 判定や作り直しが失敗しても元の文で続ける（生成・配信を止めない）。
func TestQualityCheckFailOpen(t *testing.T) {
	req := batchRequest(false, true, 1)
	req.QualityCheck = true

	p := &Producer{Selector: &batchSelector{}, Service: &notesService{},
		Checker: &stubChecker{err: errors.New("jev down")}}
	got, err := p.ProduceBatch(context.Background(), nil, nil, req, 2)
	if err != nil || len(got) != 2 || got[0].Sentence.ThaiText == "retried" {
		t.Fatalf("判定失敗で元の文を返していない: %v %v", got, err)
	}
	// 判定できなかった文は quality を持たない（プールに入らない）。
	if got[0].Quality != nil {
		t.Errorf("判定失敗なのに quality がある: %+v", got[0].Quality)
	}

	p = &Producer{Selector: &batchSelector{}, Service: &notesService{retryFail: true},
		Checker: &stubChecker{bad: map[string]bool{"w1": true}}}
	got, err = p.ProduceBatch(context.Background(), nil, nil, req, 1)
	if err != nil || len(got) != 1 || got[0].Sentence.ThaiText == "retried" {
		t.Fatalf("作り直し失敗で元の文を返していない: %v %v", got, err)
	}
	// 作り直せなかった元の文は不合格のまま（プールに入らない）。
	if q := got[0].Quality; q == nil || q.Passed || q.Retried {
		t.Errorf("quality = %+v", got[0].Quality)
	}
}

// バンク・コーパス由来の文は判定しない（判定済み）。
func TestQualityCheckSkipsCache(t *testing.T) {
	// バンクに当たる w1 だけを不合格にする。判定されれば作り直しで回数が増える。
	chk := &stubChecker{bad: map[string]bool{"w1": true}}
	bank := &batchBank{hits: map[string]bool{"w1": true}}
	p := &Producer{Selector: &batchSelector{}, Corpus: bank, Service: &notesService{}, Checker: chk}
	req := batchRequest(false, true, 1)
	req.QualityCheck = true
	if _, err := p.ProduceBatch(context.Background(), nil, nil, req, 2); err != nil {
		t.Fatal(err)
	}
	if len(chk.calls) != 1 {
		t.Errorf("LLM 生成の1本だけ判定するはず: %d", len(chk.calls))
	}
}
