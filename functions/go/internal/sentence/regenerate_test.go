package sentence

import (
	"context"
	"testing"
	"time"

	"cloud.google.com/go/firestore"

	"github.com/mnbst/thai-memo/functions/go/internal/lang"
	"github.com/mnbst/thai-memo/functions/go/internal/uvm"
)

// regenStub は出し直す文の登場回数を appearances で決め、空いた場面の有無を free で決める。
type regenStub struct {
	unseenStub
	appearances int
	free        bool
	asked       []string
}

func (s *regenStub) PickReused(
	ctx context.Context, db *firestore.Client, fr uvm.FreqRank,
	req ProduceRequest, count int, skip map[string]bool,
) ([]*Produced, error) {
	out, err := s.unseenStub.PickReused(ctx, db, fr, req, count, skip)
	for _, p := range out {
		p.Reuse = &Reuse{Appearances: s.appearances}
	}
	return out, err
}

func (s *regenStub) FreshSceneTarget(word, topic string, _ map[string]bool, _ int) (TargetWord, bool) {
	s.asked = append(s.asked, word)
	if !s.free {
		return TargetWord{}, false
	}
	return TargetWord{Word: word, Topic: topic, Matched: true, ShotID: "shot_" + word}, true
}

func TestRegenerateRepeated(t *testing.T) {
	five := 5
	zero := 0
	one := 1
	for _, c := range []struct {
		name        string
		appearances int
		free        bool
		regen       bool
		topic       string
		budget      *int
		fail        bool
		wantLLM     int
	}{
		{name: "3回出た文は作り直す", appearances: 3, free: true, regen: true, topic: "仕事", budget: &five, wantLLM: 2},
		{name: "2回までは出し直し", appearances: 2, free: true, regen: true, topic: "仕事", budget: &five},
		{name: "空いた場面が無ければ出し直し", appearances: 3, regen: true, topic: "仕事", budget: &five},
		{name: "テーマ指定でなければ出し直し", appearances: 3, free: true, topic: "仕事", budget: &five},
		{name: "テーマが空なら出し直し", appearances: 3, free: true, regen: true, budget: &five},
		{name: "1日の上限に達していれば出し直し", appearances: 3, free: true, regen: true, topic: "仕事", budget: &zero},
		{name: "残り1本なら1本だけ作る", appearances: 3, free: true, regen: true, topic: "仕事", budget: &one, wantLLM: 1},
		{name: "生成に失敗したら出し直し", appearances: 3, free: true, regen: true, topic: "仕事", budget: &five, fail: true},
	} {
		t.Run(c.name, func(t *testing.T) {
			sel := &regenStub{
				unseenStub:  unseenStub{reusable: []string{"x", "y"}},
				appearances: c.appearances, free: c.free,
			}
			fail := map[string]bool{}
			if c.fail {
				fail = map[string]bool{"x": true, "y": true}
			}
			svc := &batchService{fail: fail}
			p := &Producer{Selector: sel, Service: svc}
			req := batchRequest(false, true, 1)
			req.UnseenOnly = true
			req.RegenerateRepeated = c.regen
			req.LLMBudget = c.budget
			if c.topic != "" {
				req.Params = map[string]any{"topic": c.topic}
			}
			got, err := p.ProduceBatch(context.Background(), nil, nil, req, 5)
			if err != nil {
				t.Fatal(err)
			}
			if len(got) != 2 {
				t.Fatalf("本数 %d, want 2", len(got))
			}
			llm := 0
			for _, g := range got {
				if g.Reuse == nil && !g.FromCache {
					llm++
					if g.AppearanceCount() != 1 {
						t.Errorf("作り直した文の登場回数 %d", g.AppearanceCount())
					}
				} else if g.AppearanceCount() != c.appearances+1 {
					t.Errorf("出し直しの登場回数 %d, want %d", g.AppearanceCount(), c.appearances+1)
				}
			}
			if llm != c.wantLLM {
				t.Errorf("作り直し %d本, want %d", llm, c.wantLLM)
			}
		})
	}
}

// 登場回数は同じ本文の doc（削除印つきを含む）の最大。項目が無ければ 1。
func TestPickReusableDocAppearances(t *testing.T) {
	bd := []any{map[string]any{"word": "ไป", "meaning": "行く", "notes": ""}}
	doc := func(text, scene string, n any, deleted bool) map[string]any {
		d := map[string]any{"thai_text": text, "lang": "ja", "word_breakdown": bd, "deleted": deleted}
		if scene != "" {
			d["scene"] = scene
		}
		if n != nil {
			d[AppearanceCountField] = n
		}
		return d
	}
	docs := []sentenceDoc{
		{ID: "live", Data: doc("ไปทุกวัน", "", int64(2), false)},
		{ID: "old", Data: doc("ไปทุกวัน", "朝の通勤", int64(3), true)},
		{ID: "other", Data: doc("ไปไหม", "", nil, true)},
	}
	_, reuse := pickReusableDoc(docs, lang.JA, func(int) int { return 0 }, time.Now())
	if reuse.Appearances != 3 {
		t.Errorf("登場回数 %d, want 3", reuse.Appearances)
	}
	if !reuse.UsedScenes["朝の通勤"] || len(reuse.UsedScenes) != 1 {
		t.Errorf("使った場面 %v", reuse.UsedScenes)
	}
	// 同じ本文は場面の記録がある方で数えるので、記録の無い文は ไปไหม の1つだけ。
	if reuse.UnknownScenes != 1 {
		t.Errorf("記録の無い文 %d, want 1", reuse.UnknownScenes)
	}
	if (&Produced{Reuse: reuse}).AppearanceCount() != 4 {
		t.Error("新しい doc は最大 +1")
	}

	_, reuse = pickReusableDoc(docs[2:3:3], lang.JA, nil, time.Now())
	if reuse != nil {
		t.Error("削除印つきだけなら出し直さない")
	}
	docs[2].Data["deleted"] = false
	_, reuse = pickReusableDoc(docs[2:], lang.JA, nil, time.Now())
	if reuse.Appearances != 1 {
		t.Errorf("項目の無い doc は 1: %d", reuse.Appearances)
	}
}
