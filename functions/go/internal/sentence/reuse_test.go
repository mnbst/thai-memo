package sentence

import (
	"context"
	"testing"

	"cloud.google.com/go/firestore"

	"github.com/mnbst/thai-memo/functions/go/internal/lang"
	"github.com/mnbst/thai-memo/functions/go/internal/uvm"
)

// unseenStub は帯の未出語 unseen と、出し直せる語 reusable を持つ選定。
type unseenStub struct {
	batchSelector
	unseen   []string
	reusable []string
	legacy   int
	wants    []int
}

func (s *unseenStub) SelectTargetWords(
	ctx context.Context, db *firestore.Client, fr uvm.FreqRank,
	uid string, params map[string]any, mv *int, count int, prem bool, est *int, tested int,
) ([]TargetWord, error) {
	s.legacy++
	return s.batchSelector.SelectTargetWords(ctx, db, fr, uid, params, mv, count, prem, est, tested)
}

func (s *unseenStub) SelectUnseenTargetWords(
	_ context.Context, _ *firestore.Client, _ uvm.FreqRank,
	_ string, _ map[string]any, _ *int, count int, _ bool, _ *int, _ int,
) ([]TargetWord, error) {
	if len(s.unseen) == 0 {
		return nil, ErrNoTargetWords
	}
	out := []TargetWord{}
	for _, w := range s.unseen[:min(count, len(s.unseen))] {
		out = append(out, TargetWord{Word: w})
	}
	return out, nil
}

func (s *unseenStub) PickReused(
	_ context.Context, _ *firestore.Client, _ uvm.FreqRank,
	_ ProduceRequest, count int, skip map[string]bool,
) ([]*Produced, error) {
	s.wants = append(s.wants, count)
	var out []*Produced
	for _, w := range s.reusable {
		if len(out) < count && !skip[w] {
			out = append(out, &Produced{
				Sentence: &Sentence{ThaiText: "old " + w}, TargetWords: []string{w}, FromCache: true,
			})
		}
	}
	return out, nil
}

func TestUnseenOnlyProduce(t *testing.T) {
	for _, c := range []struct {
		name             string
		unseen, reusable []string
		n                int
		fail             map[string]bool
		want             []string
		wantLegacy       int
		wantErr          bool
	}{
		{name: "未出3語なら3本で埋めない", unseen: []string{"a", "b", "c"}, reusable: []string{"x"}, n: 5, want: []string{"a", "b", "c"}},
		{name: "未出1語なら既出で2本", unseen: []string{"a"}, reusable: []string{"x", "y"}, n: 5, want: []string{"a", "x"}},
		{name: "未出なしなら既出2本", reusable: []string{"x", "y", "z"}, n: 5, want: []string{"x", "y"}},
		{name: "生成が全滅なら既出2本", unseen: []string{"a", "b"}, reusable: []string{"x", "y"}, n: 5, fail: map[string]bool{"a": true, "b": true}, want: []string{"x", "y"}},
		{name: "生成が全滅で既出なしならエラー", unseen: []string{"a"}, n: 5, fail: map[string]bool{"a": true}, wantErr: true},
		{name: "未出も既出もなければ従来の選び方", n: 2, want: []string{"w1", "w2"}, wantLegacy: 1},
		{name: "1本の要求は埋めない", unseen: []string{"a"}, reusable: []string{"x"}, n: 1, want: []string{"a"}},
	} {
		t.Run(c.name, func(t *testing.T) {
			sel := &unseenStub{unseen: c.unseen, reusable: c.reusable}
			p := &Producer{Selector: sel, Service: &batchService{fail: c.fail}}
			req := batchRequest(false, true, 1)
			req.UnseenOnly = true
			got, err := p.ProduceBatch(context.Background(), nil, nil, req, c.n)
			if c.wantErr {
				if err == nil {
					t.Fatal("エラーにならない")
				}
				return
			}
			if err != nil {
				t.Fatal(err)
			}
			w := words(got)
			if len(w) != len(c.want) {
				t.Fatalf("語 %v, want %v", w, c.want)
			}
			for i := range w {
				if w[i] != c.want[i] {
					t.Fatalf("語 %v, want %v", w, c.want)
				}
			}
			if sel.legacy != c.wantLegacy {
				t.Errorf("従来の選定 %d回, want %d", sel.legacy, c.wantLegacy)
			}
		})
	}
}

// 既定（旧クライアント）は未出語だけの選定を通らない。
func TestUnseenOnlyOffUsesLegacy(t *testing.T) {
	sel := &unseenStub{unseen: []string{"a"}}
	p := &Producer{Selector: sel, Service: &batchService{}}
	got, err := p.ProduceBatch(context.Background(), nil, nil, batchRequest(false, true, 1), 5)
	if err != nil || len(got) != 5 || sel.legacy != 1 {
		t.Fatalf("本数 %d legacy %d err %v", len(got), sel.legacy, err)
	}
}

func TestPickReusableDoc(t *testing.T) {
	good := map[string]any{
		"thai_text": "ไป", "japanese_translation": "行く", "lang": "ja", "viewed": true, "favorite": true,
		"word_breakdown": []any{map[string]any{"word": "ไป", "meaning": "行く", "notes": ""}},
	}
	for _, c := range []struct {
		name string
		doc  map[string]any
		want bool
	}{
		{"出せる", good, true},
		{"消した例文", merge(good, map[string]any{"deleted": true}), false},
		{"訳の言語が違う", merge(good, map[string]any{"lang": "en"}), false},
		{"単語分解なし", merge(good, map[string]any{"word_breakdown": []any{}}), false},
	} {
		got := pickReusableDoc([]map[string]any{c.doc}, lang.Lang("ja"), func(int) int { return 0 })
		if (got != nil) != c.want {
			t.Errorf("%s: %v", c.name, got)
		}
		if got != nil && got.WordBreakdown[0].Meaning != "行く" {
			t.Errorf("%s: 語が読めていない %+v", c.name, got.WordBreakdown)
		}
	}
}

func merge(a, b map[string]any) map[string]any {
	out := map[string]any{}
	for k, v := range a {
		out[k] = v
	}
	for k, v := range b {
		out[k] = v
	}
	return out
}

func TestQuizSizeFor(t *testing.T) {
	interview := map[string]any{"level": "none"}
	newApp, oldApp := "1.4.31", "1.4.30"
	for _, c := range []struct {
		name string
		user map[string]any
		want int
	}{
		{"入門者は実際の本数に連動", map[string]any{"interview": interview, "estimated_vocab": int64(34), "app_version": newApp, LastSetSizeField: int64(2)}, 2},
		{"入門者でも本数の上限は超えない", map[string]any{"interview": interview, "estimated_vocab": int64(0), "app_version": newApp, LastSetSizeField: int64(5)}, 2},
		{"本数が5に戻ったら連動しない", map[string]any{"interview": interview, "estimated_vocab": int64(50), "app_version": newApp, LastSetSizeField: int64(2)}, 5},
		{"入門者以外は連動しない", map[string]any{"app_version": newApp, LastSetSizeField: int64(2)}, 5},
		{"旧版は従来どおり", map[string]any{"interview": interview, "estimated_vocab": int64(34), "app_version": oldApp, LastSetSizeField: int64(2)}, 4},
	} {
		if got := QuizSizeFor(c.user); got != c.want {
			t.Errorf("%s: %d, want %d", c.name, got, c.want)
		}
	}
}
