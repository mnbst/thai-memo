// Package embeddings は語彙のセマンティック類似度計算。
// functions/python/embeddings.py の移植。
//
// GCS から embedding データを遅延ロードし、コサイン類似度で
// セマンティック重複除去やテーマ関連単語の検索を行う。
//
// データ形式:
//   - vocab_embeddings.npy: (10000, 768) float32 — Gemini Embedding モデルの出力
//   - vocab_words.json: [{"word": "ฉัน", "rank": 1}, ...] — npy の行番号と対応
//   - topic_embeddings.json: {"テーマ文字列": [float, ...], ...} — 事前計算済み
package embeddings

import (
	"math"
	"sort"
)

// Word は vocab_words.json の1件。
type Word struct {
	Word string `json:"word"`
	Rank int    `json:"rank"`
}

// SimilarWord は get_topic_similar_words の戻り値。
type SimilarWord struct {
	Word       string  `json:"word"`
	Rank       int     `json:"rank"`
	Similarity float64 `json:"similarity"`
}

// CosineSimilarity は2つのベクトルのコサイン類似度。
//
// 戻り値は -1.0〜1.0。1.0 に近いほど意味が似ている。
// ゼロベクトルが渡された場合は 0.0 を返す。
func CosineSimilarity(a, b []float32) float64 {
	// 累積は float64 で行う。
	//
	// numpy の np.dot(float32) は BLAS の sdot なので float32 で積和され、
	// 総和の順序も SIMD/ブロック分割で決まる。Go から順序まで再現はできないため
	// ビット一致は不可能で、どちらに寄せるかの選択になる。
	// 実測（合成データ3000ペア）での numpy との最大乖離:
	//   float32 で積和   1.44e-07  … 順序違いの誤差が上乗せされる
	//   float64 で積和   1.19e-07  … float32 の丸め幅 2^-23 ちょうど＝下限
	// **精度の高い float64 を採る。** 移植の目的は Python の再現ではなく
	// 同じ機能をより良く動かすことなので、丸め方まで真似る理由は無い。
	// 結果として float64 のほうが真値に近く、numpy との差も小さい。
	//
	// 残る乖離は numpy 側が float32 で持っていることによるもので、消せない。
	// このため差分テストは完全一致ではなく 1e-6 の許容で比べている。
	// 閾値比較（FilterSemanticDuplicates の >= 0.85 など）は、
	// 類似度がちょうど閾値に載ったときだけ Python と結果が分かれうる。
	var dot, na, nb float64
	n := min(len(a), len(b))
	for i := range n {
		dot += float64(a[i]) * float64(b[i])
		na += float64(a[i]) * float64(a[i])
		nb += float64(b[i]) * float64(b[i])
	}
	norm := math.Sqrt(na) * math.Sqrt(nb)
	if norm == 0 {
		return 0
	}
	return dot / norm
}

// scored は類似度つきの候補。
type scored[T any] struct {
	Sim  float64
	Item T
}

// PickWeights は _weighted_pick の重みを計算する。
//
// 類似度を min-max 正規化し、下駄 0.1 を足す。
// 最下位でも選ばれる余地を残して多様性を確保するため。
//
// 全て同じ類似度なら ok=false（Python 側は random.choice に落ちる）。
func PickWeights(sims []float64) (weights []float64, ok bool) {
	if len(sims) == 0 {
		return nil, false
	}
	minSim, maxSim := sims[0], sims[0]
	for _, s := range sims {
		minSim = math.Min(minSim, s)
		maxSim = math.Max(maxSim, s)
	}
	if maxSim == minSim {
		return nil, false
	}
	weights = make([]float64, len(sims))
	for i, s := range sims {
		weights[i] = (s-minSim)/(maxSim-minSim) + 0.1
	}
	return weights, true
}

// FilterSemanticDuplicates は選定済み単語と意味的に重複する候補を除去する。
//
// 復習単語を先に確定した後、新規単語候補に対して適用し、
// 復習単語と意味が被る候補を除外する。
// embedding が取れない単語はフィルタ対象外としてそのまま残す。
func (s *Store) FilterSemanticDuplicates(
	candidates, selected []Word, threshold float64,
) []Word {
	var selectedEmbs [][]float32
	for _, sel := range selected {
		if emb := s.Embedding(sel.Word); emb != nil {
			selectedEmbs = append(selectedEmbs, emb)
		}
	}
	// 選定済みに embedding がない場合はフィルタ不要
	if len(selectedEmbs) == 0 {
		return candidates
	}

	filtered := make([]Word, 0, len(candidates))
	for _, c := range candidates {
		emb := s.Embedding(c.Word)
		if emb == nil {
			filtered = append(filtered, c)
			continue
		}
		isDup := false
		for _, selEmb := range selectedEmbs {
			if CosineSimilarity(emb, selEmb) >= threshold {
				isDup = true
				break
			}
		}
		if !isDup {
			filtered = append(filtered, c)
		}
	}
	return filtered
}

// GetDiverseNewWords は候補から意味的に多様な新規単語を貪欲に選ぶ。
//
// 候補を先頭から順に見て、既に選定した単語のどれとも類似度が閾値未満なら採用する。
// これにより同義語・類義語が同時に選ばれることを防ぐ。
// 候補は freq_rank 順を推奨（頻出語が優先される）。
//
// embedding が無い語は無条件で採用する。このとき Python 側は
// result_embs に積まないので、以降の比較対象にもならない。
func (s *Store) GetDiverseNewWords(
	candidates []Word, count int, threshold float64,
) []Word {
	var result []Word
	var resultEmbs [][]float32

	for _, c := range candidates {
		if len(result) >= count {
			break
		}
		emb := s.Embedding(c.Word)
		if emb == nil {
			result = append(result, c)
			continue
		}
		isDup := false
		for _, rEmb := range resultEmbs {
			if CosineSimilarity(emb, rEmb) >= threshold {
				isDup = true
				break
			}
		}
		if !isDup {
			result = append(result, c)
			resultEmbs = append(resultEmbs, emb)
		}
	}
	return result
}

// TopicSimilarWords はテーマに関連する上位 topK 語を similarity 降順で返す。
//
// 累積は CosineSimilarity と同じ理由で float64 にしている。
// 並び順は安定ソートで、同点の場合は行番号（＝頻度順位）の昇順になる。
// numpy の argsort は既定が非安定なので同点の並びは一致しないが、
// 実データで類似度が完全一致することは無い。
func (s *Store) TopicSimilarWords(topicEmb []float32, topK int) []SimilarWord {
	s.mu.Lock()
	matrix, words := s.matrix, s.words
	s.mu.Unlock()
	if matrix == nil {
		return nil
	}

	topicNorm := math.Sqrt(selfDot(topicEmb))
	sims := make([]float64, len(matrix))
	for i, row := range matrix {
		rowNorm := math.Sqrt(selfDot(row))
		// Python は norms * topic_norm + 1e-10 でゼロ割を避けている
		sims[i] = dot(row, topicEmb) / (rowNorm*topicNorm + 1e-10)
	}

	idx := make([]int, len(sims))
	for i := range idx {
		idx[i] = i
	}
	sort.SliceStable(idx, func(a, b int) bool {
		return sims[idx[a]] > sims[idx[b]]
	})

	if topK > len(idx) {
		topK = len(idx)
	}
	out := make([]SimilarWord, 0, topK)
	for _, i := range idx[:topK] {
		if i >= len(words) {
			continue
		}
		out = append(out, SimilarWord{
			Word: words[i].Word, Rank: words[i].Rank, Similarity: sims[i],
		})
	}
	return out
}

func dot(a, b []float32) float64 {
	var sum float64
	n := min(len(a), len(b))
	for i := range n {
		sum += float64(a[i]) * float64(b[i])
	}
	return sum
}

func selfDot(a []float32) float64 { return dot(a, a) }
