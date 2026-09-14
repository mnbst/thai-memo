package sentence

import (
	"context"
	"errors"
	"testing"
)

// stubEmb は語ごとに決まったテーマを返す。未登録の語は閾値未達扱いで空。
type stubEmb struct {
	byWord map[string]string
	pools  [][]string
	err    error
}

func (e *stubEmb) Embedding(string) []float32 { return nil }

func (e *stubEmb) TopicEmbedding(context.Context, string) ([]float32, error) { return nil, nil }

func (e *stubEmb) FindBestTopic(
	_ context.Context, word string, topics []string, _ int, _ float64,
) (string, error) {
	if e.err != nil {
		return "", e.err
	}
	e.pools = append(e.pools, topics)
	return e.byWord[word], nil
}

// テーマが選定前に確定していれば（テーマ指定あり / free おまかせ）全部同じテーマ。
func TestAssignTopicsSharedWhenTopicFixed(t *testing.T) {
	emb := &stubEmb{byWord: map[string]string{"w2": "旅行", "w3": "仕事"}}
	got, err := assignTopics(context.Background(), []string{"w1", "w2", "w3"},
		"食べ物", TopicChoice{Topic: "食べ物"}, emb)
	if err != nil {
		t.Fatal(err)
	}
	for _, tw := range got {
		if tw.Topic != "食べ物" {
			t.Errorf("%s のテーマ %q, want 食べ物", tw.Word, tw.Topic)
		}
	}
	if len(emb.pools) != 0 {
		t.Errorf("テーマ確定済みなのに embedding を %d回引いた", len(emb.pools))
	}
}

// テーマ未確定（premium おまかせ）なら語ごとに決める。
func TestAssignTopicsPerWordWhenAuto(t *testing.T) {
	pool := []string{"旅行", "仕事", "食べ物"}
	emb := &stubEmb{byWord: map[string]string{"w2": "仕事", "w3": "旅行"}}
	got, err := assignTopics(context.Background(), []string{"w1", "w2", "w3"},
		"食べ物", TopicChoice{Pool: pool}, emb)
	if err != nil {
		t.Fatal(err)
	}
	// 1本目は GetSessionWords が決めた値をそのまま使う。
	want := []string{"食べ物", "仕事", "旅行"}
	for i, tw := range got {
		if tw.Topic != want[i] {
			t.Errorf("%s のテーマ %q, want %q", tw.Word, tw.Topic, want[i])
		}
	}
	// 候補プールは選定時と同じものを渡す（語彙ゲート後）。
	for _, p := range emb.pools {
		if len(p) != len(pool) {
			t.Errorf("プール %v, want %v", p, pool)
		}
	}
}

// 閾値未達は "" のまま返し、テーマを LLM に委ねる。ランダムに埋めない。
func TestAssignTopicsLeavesUnmatchedEmpty(t *testing.T) {
	emb := &stubEmb{byWord: map[string]string{"w2": "仕事"}}
	got, err := assignTopics(context.Background(), []string{"w1", "w2", "w3"},
		"食べ物", TopicChoice{Pool: []string{"仕事"}}, emb)
	if err != nil {
		t.Fatal(err)
	}
	if got[2].Topic != "" {
		t.Errorf("閾値未達のテーマ %q, want 空", got[2].Topic)
	}
}

func TestAssignTopicsPropagatesError(t *testing.T) {
	emb := &stubEmb{err: errors.New("embedding down")}
	if _, err := assignTopics(context.Background(), []string{"w1", "w2"},
		"", TopicChoice{Pool: []string{"仕事"}}, emb); err == nil {
		t.Fatal("エラーが返らない")
	}
}

// emb が無い環境（テスト・未設定）では1本目のテーマを全体に使う。
func TestAssignTopicsWithoutEmbedder(t *testing.T) {
	got, err := assignTopics(context.Background(), []string{"w1", "w2"},
		"旅行", TopicChoice{Pool: []string{"旅行"}}, nil)
	if err != nil {
		t.Fatal(err)
	}
	for _, tw := range got {
		if tw.Topic != "旅行" {
			t.Errorf("%s のテーマ %q, want 旅行", tw.Word, tw.Topic)
		}
	}
}
