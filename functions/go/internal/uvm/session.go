package uvm

import (
	"context"
	"encoding/json"
	"log"
	"math"
	"math/rand"
	"sort"
	"unicode/utf8"

	"cloud.google.com/go/firestore"

	"github.com/mnbst/thai-memo/functions/go/internal/embeddings"
)

const (
	GapScanDepth = 50 // 後方スキャンの最大深さ
	// 前方スキャンの初期幅と、estimated_vocab に対する逓減の緩さ。
	// ahead = max(ScanAheadMin, ScanBandWidth - estimatedVocab/ScanBandDecay)
	//
	// 入りの 50 は広すぎた。progress 0（受験直後や新規）では後方が 0 なので
	// 候補 51 件が全部前方に並び、ZeroPWeights の sqrt 重みでも平均で境界の
	// 20 ランク先まで飛んでいた。入りを半分にして、8 へ降りるペースは
	// 据え置く（ScanBandDecay を 2→5）。8 到達は est=83 → 81 でほぼ同じ。
	//
	// さらに 25→20。前方が広いと est の前進が「1日 5 語しか登録できない」
	// 速度を追い越し、帯の下端が語を通り過ぎたまま二度と key_word に
	// ならない「素通り」が出る。90日シミュレーションで未受験・真値350 の
	// 素通りが 24語(8%) → 16語(5%)、受験者はほぼ 0 になり、d90 の推定値は
	// 不変（±5）。効くのは ahead が下限 8 に落ちる前、est<60 の区間だけ
	// （25 のときは est<85）。
	ScanBandWidth = 20
	ScanBandDecay = 5
	ScanAheadMin  = 8 // 前方スキャンの下限（未習語が必ず候補に入るようにする）

	// TopicFilterThreshold はテーマ embedding との類似度の足切り。
	TopicFilterThreshold = 0.3
)

// ScanBand は estimated_vocab から key_word 候補のランク帯 [low, high] を返す
// （uvm.py:scan_band:69）。
//
// 後方は GapScanDepth まで深く取り、前方は estimated_vocab が増えるほど狭める。
func ScanBand(estimatedVocab int) (low, high int) {
	behind := max(0, estimatedVocab)
	if behind > GapScanDepth {
		behind = GapScanDepth
	}
	// Python は float 演算のまま max を取り、最後に int() で切り捨てる。
	// estimated_vocab が奇数のとき /2 が .5 になるので、先に整数除算すると
	// 1 ずれる。
	ahead := ScanBandWidth - float64(estimatedVocab)/ScanBandDecay
	if ahead < ScanAheadMin {
		ahead = ScanAheadMin
	}
	return max(0, estimatedVocab-behind), estimatedVocab + int(ahead)
}

// Candidate は key_word の候補 1 件。
type Candidate struct {
	Word string
	Rank int
}

// BandCandidates は freqRank から [low, high] の 2 文字以上の語を返す
// （uvm.py:get_session_words:406 のリスト内包）。
//
// Python は dict の挿入順（＝JSON の並び＝rank 順）で並ぶ。Go の map は
// 反復順が不定なので rank で並べ直す。rank は連番で重複しないため一意に決まる。
func BandCandidates(freqRank FreqRank, low, high int) []Candidate {
	var out []Candidate
	for word, rank := range freqRank {
		if low <= rank && rank <= high && utf8.RuneCountInString(word) >= 2 {
			out = append(out, Candidate{Word: word, Rank: rank})
		}
	}
	sort.Slice(out, func(a, b int) bool { return out[a].Rank < out[b].Rank })
	return out
}

// TopicEmbedder は候補フィルタとテーマ選択に使う embedding 参照。
// 実装は internal/embeddings.Store。
type TopicEmbedder interface {
	Embedding(word string) []float32
	TopicEmbedding(ctx context.Context, topic string) ([]float32, error)
	FindBestTopic(ctx context.Context, word string, topics []string, topK int, threshold float64) (string, error)
}

// FilterCandidatesByTopic はテーマ embedding との類似度で候補を絞る
// （uvm.py:_filter_candidates_by_topic:314）。
//
// 帯域内に閾値以上が 1 つも無ければ空を返す。呼び出し側は既出を除いたうえで
// ClosestToTopic に落とす。
//
// 以前は帯域の外へ 50 ずつ 5 段まで**下へ**広げて探し、それでも駄目なら元の
// 候補を丸ごと返していた。やめた理由は 2 つ:
//
//   - 下へ広げると rank 0 まで降りられ、「測定値以下は無いものとして扱う」が
//     破れる。測定 250 の人がテーマ次第で rank 一桁の語を key_word にされた
//   - 丸ごと返すのはテーマを無視するのと同じ。帯内で一番近い語を出すほうが
//     テーマの指定に沿う
//
// 帯を出ないので、原点シフトも free の上限もそのまま守られる。
func FilterCandidatesByTopic(
	emb TopicEmbedder, candidates []Candidate, topicEmb []float32,
) []Candidate {
	var filtered []Candidate
	for _, c := range candidates {
		wordEmb := emb.Embedding(c.Word)
		if wordEmb == nil {
			continue
		}
		// 境界（ちょうど 0.3）は差分テストで踏めない。float の類似度が
		// 閾値と厳密に一致する入力を作れないため、>= と > は区別できない。
		if embeddings.CosineSimilarity(wordEmb, topicEmb) >= TopicFilterThreshold {
			filtered = append(filtered, c)
		}
	}
	return filtered
}

// ClosestToTopic は候補の中でテーマ embedding に最も近い順に count 件返す。
// 閾値を満たす語が帯内に 1 つも無かったときのフォールバック。
//
// 呼び出し側が先に既出（UVM 登録済み）を落としているので、同じテーマでも
// 同じ語が出続けることはない。embedding を持たない語は比較できないので外す。
// 全部が比較できないときは候補をそのまま返す（抽選に任せる）。
func ClosestToTopic(
	emb TopicEmbedder, candidates []Candidate, topicEmb []float32, count int,
) []Candidate {
	type scored struct {
		c   Candidate
		sim float64
	}
	var all []scored
	for _, c := range candidates {
		wordEmb := emb.Embedding(c.Word)
		if wordEmb == nil {
			continue
		}
		all = append(all, scored{c: c, sim: embeddings.CosineSimilarity(wordEmb, topicEmb)})
	}
	if len(all) == 0 {
		return candidates[:min(count, len(candidates))]
	}
	// 類似度の降順。同点は rank 昇順にして結果を一意にする。
	sort.SliceStable(all, func(i, j int) bool {
		if all[i].sim != all[j].sim {
			return all[i].sim > all[j].sim
		}
		return all[i].c.Rank < all[j].c.Rank
	})
	out := make([]Candidate, 0, min(count, len(all)))
	for _, s := range all[:min(count, len(all))] {
		out = append(out, s.c)
	}
	return out
}

// ZeroPWeights は未登録／P=0 の候補の抽選重み。rank が大きい（低頻度）ほど軽い。
func ZeroPWeights(cands []Candidate) []float64 {
	maxRank := 0
	for _, c := range cands {
		if c.Rank > maxRank {
			maxRank = c.Rank
		}
	}
	weights := make([]float64, len(cands))
	for i, c := range cands {
		weights[i] = math.Sqrt(float64(maxRank - c.Rank + 1))
	}
	return weights
}

// UnknownWeights は全候補が既習のときの抽選重み。P が低い語ほど重い。
func UnknownWeights(cands []Candidate, pMap map[string]float64) []float64 {
	weights := make([]float64, len(cands))
	for i, c := range cands {
		weights[i] = math.Max(0, 1.0-pMap[c.Word])
	}
	return weights
}

// SessionSelector は key_word の選定に必要な外部依存をまとめる。
type SessionSelector struct {
	// Rand は抽選に使う。nil なら共有の乱数源。テストで固定する。
	Rand *rand.Rand
	// Emb は nil ならテーマフィルタもテーマ自動選択も行わない。
	Emb TopicEmbedder
}

func (s *SessionSelector) float64n() float64 {
	if s.Rand != nil {
		return s.Rand.Float64()
	}
	return rand.Float64()
}

func (s *SessionSelector) intn(n int) int {
	if s.Rand != nil {
		return s.Rand.Intn(n)
	}
	return rand.Intn(n)
}

// weightedPick は random.choices(weights=...) と同じ、累積和の二分探索。
// 重みの合計が 0 のときは先頭を返す（Python の bisect と同じ）。
func (s *SessionSelector) weightedPick(weights []float64) int {
	var total float64
	for _, w := range weights {
		total += w
	}
	target := s.float64n() * total
	var cum float64
	for i, w := range weights {
		cum += w
		if target < cum {
			return i
		}
	}
	return 0
}

// SelectWeighted は weights に従って非復元で count 件引く（引いた添字を返す）。
func (s *SessionSelector) SelectWeighted(cands []Candidate, weights []float64, count int) []Candidate {
	pool := append([]Candidate(nil), cands...)
	w := append([]float64(nil), weights...)
	var out []Candidate
	for range min(count, len(pool)) {
		i := s.weightedPick(w)
		out = append(out, pool[i])
		pool = append(pool[:i], pool[i+1:]...)
		w = append(w[:i], w[i+1:]...)
	}
	return out
}

// selectUnknown は全候補が既習のときの抽選（uvm.py:get_session_words:445 の else）。
// 重みの合計が 0 なら一様抽選に落とす。
func (s *SessionSelector) selectUnknown(cands []Candidate, pMap map[string]float64, count int) []Candidate {
	pool := append([]Candidate(nil), cands...)
	w := UnknownWeights(pool, pMap)
	var out []Candidate
	for range min(count, len(cands)) {
		var total float64
		for _, x := range w {
			total += x
		}
		i := 0
		if total <= 0 {
			i = s.intn(len(pool))
		} else {
			i = s.weightedPick(w)
		}
		out = append(out, pool[i])
		pool = append(pool[:i], pool[i+1:]...)
		w = append(w[:i], w[i+1:]...)
	}
	return out
}

// SessionRequest は GetSessionWords の引数。
type SessionRequest struct {
	UID   string
	Topic string
	// Count は選ぶ語数。0 以下なら 1 件も選ばない（Python の min(count, ...) と同じ）。
	Count int
	// MaxVocab は語彙帯域の上限（free は 100）。nil なら制限なし。
	MaxVocab *int
	// TopicsPool はテーマ自動選択の候補。nil なら全テーマ。
	TopicsPool []string
	// EstimatedVocab は呼び出し元で取得済みの語彙スコア。nil なら Firestore から読む。
	EstimatedVocab *int
	// TestedVocab は語彙テストの測定値（原点）。帯の下端はここより下へ行かない。
	// 未受験は 0 で、その場合の帯は従来どおり。
	TestedVocab int
}

// GetSessionWords は統合スキャン方式でセッション単語を選定する
// （uvm.py:get_session_words:360）。
//
// 1. scan_band が返すランク帯から未登録 or P=0 の語を rank 重み付きで選ぶ
// 2. テーマ指定があれば embedding で候補を絞り、そのテーマをそのまま使う
// 3. 指定が無ければ key_word から embedding でテーマを決める（閾値未達なら ""）
func (s *SessionSelector) GetSessionWords(
	ctx context.Context, db *firestore.Client, freqRank FreqRank, req SessionRequest,
) ([]string, string, error) {
	estimatedVocab := 0
	if req.EstimatedVocab != nil {
		estimatedVocab = *req.EstimatedVocab
	} else {
		snap, err := db.Collection("users").Doc(req.UID).Get(ctx)
		if err == nil && snap.Exists() {
			estimatedVocab = intField(snap.Data(), "estimated_vocab", 0)
			if req.TestedVocab == 0 {
				req.TestedVocab = intField(snap.Data(), "vocab_test_vocab", 0)
			}
		}
	}
	if req.MaxVocab != nil {
		estimatedVocab = min(estimatedVocab, *req.MaxVocab)
	}

	// 測定値を原点として帯を取る（EstimateVocab の floor と揃える）。
	// ScanBand を「測定値からの相対位置」で計算し、あとで測定値ぶん平行移動する。
	// 単に下端を測定値で切り上げると後方ぶん（最大 GapScanDepth）が丸ごと消え、
	// 測定 250 のとき幅 9 しか残らない。0 から始めた人は前方 51 幅を持つので、
	// 原点をずらすだけで同じ幅になるようにする。未受験（0）は従来と完全に同一。
	//
	// ただし free（MaxVocab あり）は測定値を使わない。上限 100 と原点シフトを
	// 併用すると帯が上限に潰れるため（測定 250 で [100,100] の幅 1、測定 100
	// でも幅 1）。free は未受験者とまったく同じ挙動にし、上限側だけで抑える。
	tested := max(req.TestedVocab, 0)
	if req.MaxVocab != nil {
		tested = 0
	}
	scanLow, scanHigh := ScanBand(max(estimatedVocab-tested, 0))
	scanLow += tested
	scanHigh += tested
	if req.MaxVocab != nil {
		scanHigh = min(scanHigh, *req.MaxVocab)
		scanLow = min(scanLow, scanHigh)
	}

	candidates := BandCandidates(freqRank, scanLow, scanHigh)

	// fallbackEmb が非 nil のときは「帯内に閾値以上の語が無かった」。
	// 既出を落としたあとで一番テーマに近い語を選ぶ（下の選出部）。
	var fallbackEmb []float32

	topic := req.Topic
	if topic != "" && s.Emb != nil && len(candidates) > 0 {
		topicEmb, err := s.Emb.TopicEmbedding(ctx, topic)
		if err != nil {
			return nil, "", err
		}
		if topicEmb != nil {
			if matched := FilterCandidatesByTopic(s.Emb, candidates, topicEmb); len(matched) > 0 {
				candidates = matched
			} else {
				fallbackEmb = topicEmb
			}
		}
	}

	if len(candidates) == 0 {
		log.Printf("get_session_words: no candidates, estimated_vocab=%d, scan=[%d, %d], topic=%s",
			estimatedVocab, scanLow, scanHigh, topic)
		return nil, topic, nil
	}

	pMap, err := s.fetchP(ctx, db, req.UID, candidates)
	if err != nil {
		return nil, "", err
	}

	var zeroP []Candidate
	for _, c := range candidates {
		if p, ok := pMap[c.Word]; !ok || p == 0.0 {
			zeroP = append(zeroP, c)
		}
	}

	var selected []Candidate
	switch {
	case fallbackEmb != nil && len(zeroP) > 0:
		// テーマ一致語が帯内に無かった場合。既出（UVM 登録済み）を除いた
		// 未出の語から、一番テーマに近いものを取る。
		selected = ClosestToTopic(s.Emb, zeroP, fallbackEmb, req.Count)
	case fallbackEmb != nil:
		// 帯内が全部既出。それでもテーマに一番近い語を返す。
		selected = ClosestToTopic(s.Emb, candidates, fallbackEmb, req.Count)
	case len(zeroP) > 0:
		selected = s.SelectWeighted(zeroP, ZeroPWeights(zeroP), req.Count)
	default:
		selected = s.selectUnknown(candidates, pMap, req.Count)
	}

	words := make([]string, len(selected))
	for i, c := range selected {
		words[i] = c.Word
	}

	chosenTopic := topic
	if chosenTopic == "" && s.Emb != nil && len(words) > 0 {
		// 閾値未達（＝key_word がどのテーマとも結びつかない機能語など）は
		// "" のまま返し、テーマを LLM に決めさせる。ランダムに埋めない。
		chosenTopic, err = s.Emb.FindBestTopic(ctx, words[0], req.TopicsPool, 5, 0.545)
		if err != nil {
			return nil, "", err
		}
	}

	if line, err := json.Marshal(map[string]any{
		"message":         "get_session_words",
		"topic":           chosenTopic,
		"estimated_vocab": estimatedVocab,
		"scan":            []int{scanLow, scanHigh},
		"selected":        words,
	}); err == nil {
		log.Print(string(line))
	}

	return words, chosenTopic, nil
}

// fetchP は候補語の UVM ドキュメントを一括で読み、p を集める。
// 数値でない p は Python の isinstance チェックと同じく無視する。
func (s *SessionSelector) fetchP(
	ctx context.Context, db *firestore.Client, uid string, candidates []Candidate,
) (map[string]float64, error) {
	uvmRef := db.Collection("users").Doc(uid).Collection("uvm")
	seen := map[string]bool{}
	var refs []*firestore.DocumentRef
	for _, c := range candidates {
		if seen[c.Word] {
			continue
		}
		seen[c.Word] = true
		refs = append(refs, uvmRef.Doc(c.Word))
	}
	snaps, err := db.GetAll(ctx, refs)
	if err != nil {
		return nil, err
	}
	pMap := map[string]float64{}
	for _, snap := range snaps {
		if !snap.Exists() {
			continue
		}
		if v, ok := snap.Data()["p"]; ok {
			switch n := v.(type) {
			case float64:
				pMap[snap.Ref.ID] = n
			case int64:
				pMap[snap.Ref.ID] = float64(n)
			}
		}
	}
	return pMap, nil
}
