package embeddings

import (
	"context"
	"math"
	"sort"
	"strings"
)

// FindBestSubTheme は単語とサブテーマ群のコサイン類似度で重みつきランダム選出する。
//
// embedding が引けない場合や候補が全て同点の場合は、候補全体から一様に選ぶ
// （Python の random.choice(sub_themes) と同じで、scored 側からではない）。
func (s *Store) FindBestSubTheme(
	ctx context.Context, word string, subThemes []string,
) (string, error) {
	if len(subThemes) == 0 {
		return "", nil
	}

	s.mu.Lock()
	if err := s.loadLocked(ctx); err != nil {
		s.mu.Unlock()
		return "", err
	}
	if err := s.loadJSONEmbeddings(ctx, &s.subThemeEmbs, subThemeEmbBlob); err != nil {
		s.mu.Unlock()
		return "", err
	}
	s.mu.Unlock()

	wordEmb := s.Embedding(word)
	if wordEmb == nil {
		return subThemes[s.pick(len(subThemes), nil)], nil
	}

	var sims []float64
	var items []string
	for _, st := range subThemes {
		emb, ok := s.subThemeEmbs[st]
		if !ok {
			continue
		}
		sims = append(sims, CosineSimilarity(wordEmb, emb))
		items = append(items, st)
	}
	if len(items) == 0 {
		return subThemes[s.pick(len(subThemes), nil)], nil
	}

	weights, ok := PickWeights(sims)
	if !ok {
		// 全て同点。Python は scored ではなく sub_themes から選ぶ。
		return subThemes[s.pick(len(subThemes), nil)], nil
	}
	return items[s.pick(len(items), weights)], nil
}

// Shot はドラマのショット候補（ID と台詞）。
// Python は dict を挿入順で回すので、Go では順序つきで受け取る。
type Shot struct {
	ID   string
	Text string
}

// FindBestDramaShot は単語と各セリフのコサイン類似度で最適なショットを1つ選ぶ。
//
// embedding が引けない場合は空文字を返す（呼び出し側でランダムに縮退する）。
// 次元不一致（生成時の output_dimensionality 違い等）は候補から外す。
// 例文生成そのものを落とさないため。
func (s *Store) FindBestDramaShot(
	ctx context.Context, word string, shots []Shot,
) (string, error) {
	s.mu.Lock()
	if err := s.loadLocked(ctx); err != nil {
		s.mu.Unlock()
		return "", err
	}
	if err := s.loadJSONEmbeddings(ctx, &s.shotEmbs, shotEmbBlob); err != nil {
		s.mu.Unlock()
		return "", err
	}
	s.mu.Unlock()

	wordEmb := s.Embedding(word)
	if wordEmb == nil {
		return "", nil
	}

	var sims []float64
	var items []string
	for _, shot := range shots {
		emb, ok := s.shotEmbs[shot.Text]
		if !ok || len(emb) != len(wordEmb) {
			continue
		}
		sims = append(sims, CosineSimilarity(wordEmb, emb))
		items = append(items, shot.ID)
	}
	if len(items) == 0 {
		return "", nil
	}

	weights, ok := PickWeights(sims)
	if !ok {
		return items[s.pick(len(items), nil)], nil
	}
	return items[s.pick(len(items), weights)], nil
}

// Scene は場面の名前と、そこに属するショットの本文。
type Scene struct {
	Name  string
	Texts []string
}

// FindNearScenes は類似度が threshold 以上の場面の名前を scenes の順で返す。
// どれも届かなければ nil（呼び出し側は場面を問わず選ぶ）。
//
// 最も近い1つではなく足切りを通ったすべてを返し、呼び出し側が一様に選ぶ。
// 最も近いものだけを採ると、どの語にも近く出る汎用的な場面へ集まる。
//
// 場面のベクトルは、属するショットの embedding を正規化して平均したもの。
// 語をショット1文と比べると、短く汎用的な文がどの語にも近く出て選出が
// 偏った（食べ物156語で実測）。場面単位の平均ならこの偏りが均される。
func (s *Store) FindNearScenes(
	ctx context.Context, word string, scenes []Scene, threshold float64,
) ([]string, error) {
	s.mu.Lock()
	if err := s.loadLocked(ctx); err != nil {
		s.mu.Unlock()
		return nil, err
	}
	if err := s.loadJSONEmbeddings(ctx, &s.shotEmbs, shotEmbBlob); err != nil {
		s.mu.Unlock()
		return nil, err
	}
	s.mu.Unlock()

	wordEmb := s.Embedding(word)
	if wordEmb == nil {
		return nil, nil
	}
	var near []string
	for _, sc := range scenes {
		centroid := s.centroid(sc.Texts, len(wordEmb))
		if centroid == nil {
			continue
		}
		if CosineSimilarity(wordEmb, centroid) >= threshold {
			near = append(near, sc.Name)
		}
	}
	return near, nil
}

// centroid はショットの embedding を正規化して平均する。1件も無ければ nil。
func (s *Store) centroid(texts []string, dim int) []float32 {
	sum := make([]float64, dim)
	n := 0
	for _, t := range texts {
		emb, ok := s.shotEmbs[t]
		if !ok || len(emb) != dim {
			continue
		}
		var norm float64
		for _, v := range emb {
			norm += float64(v) * float64(v)
		}
		if norm == 0 {
			continue
		}
		norm = math.Sqrt(norm)
		for i, v := range emb {
			sum[i] += float64(v) / norm
		}
		n++
	}
	if n == 0 {
		return nil
	}
	out := make([]float32, dim)
	for i, v := range sum {
		out[i] = float32(v / float64(n))
	}
	return out
}

// FindBestTopic は key_word の embedding と各テーマ embedding の類似度から
// テーマを返す。
//
// 閾値以上の候補を類似度順に並べ、上位 topK 件からランダムに1件選ぶ。
// 閾値を満たす候補が無ければ空文字（呼び出し側で LLM に委ねる）。
//
// 閾値未達時に最高類似度を返すことはしない。機能語 key_word はどのテーマとも
// 意味的に無関係なので、argmax はテーマ embedding の重心バイアス
// （ラベル文が広いテーマほど全語に近い）を拾うだけで意味を持たない。
func (s *Store) FindBestTopic(
	ctx context.Context, word string, topics []string, topK int, threshold float64,
) (string, error) {
	s.mu.Lock()
	if err := s.loadLocked(ctx); err != nil {
		s.mu.Unlock()
		return "", err
	}
	if err := s.loadJSONEmbeddings(ctx, &s.topicEmbs, topicEmbBlob); err != nil {
		s.mu.Unlock()
		return "", err
	}
	s.mu.Unlock()

	wordEmb := s.Embedding(word)
	if wordEmb == nil {
		return "", nil
	}

	type entry struct {
		sim   float64
		topic string
	}
	var scoredList []entry
	for _, topicStr := range sortedKeys(s.topicEmbs) {
		if topics != nil && !matchesAnyTopic(topicStr, topics) {
			continue
		}
		scoredList = append(scoredList, entry{
			sim:   CosineSimilarity(wordEmb, s.topicEmbs[topicStr]),
			topic: topicStr,
		})
	}
	if len(scoredList) == 0 {
		return "", nil
	}

	// Python の scored.sort(reverse=True) はタプル比較なので、
	// 類似度が同じときはテーマ文字列の降順になる。
	sort.SliceStable(scoredList, func(a, b int) bool {
		if scoredList[a].sim != scoredList[b].sim {
			return scoredList[a].sim > scoredList[b].sim
		}
		return scoredList[a].topic > scoredList[b].topic
	})

	var candidates []string
	for _, e := range scoredList {
		if e.sim >= threshold {
			candidates = append(candidates, e.topic)
		}
	}
	if len(candidates) == 0 {
		return "", nil
	}
	if topK < len(candidates) {
		candidates = candidates[:topK]
	}
	return candidates[s.pick(len(candidates), nil)], nil
}

// matchesAnyTopic は Python の
// any(t in topic_str or topic_str in t for t in topics)。
func matchesAnyTopic(topicStr string, topics []string) bool {
	for _, t := range topics {
		if strings.Contains(topicStr, t) || strings.Contains(t, topicStr) {
			return true
		}
	}
	return false
}
