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

	// ForwardTopUpDepth は、帯の中で本数が埋まらないときに前方へ広げる深さ。
	//
	// 帯（幅は後方 50 + 前方 8〜20）を使い切るのは、est が伸びないまま生成を
	// 続けた人。そこで既出を key_word に戻すと同じ語が何度も出るので、帯の
	// 続きから未出を取る。深さは後方スキャン（GapScanDepth）と同じ 50。
	// 1 セット 5 本ぶんを賄うには十分広く、難度が跳ぶほど遠くもない。
	// ここで取れるのは穴埋めぶんだけで、帯そのものは動かさない
	// （est の前進は従来どおり ScanBand が決める）。
	ForwardTopUpDepth = 50
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
		if low <= rank && rank <= high && utf8.RuneCountInString(word) >= 2 &&
			!IsExcludedTargetWord(word) {
			out = append(out, Candidate{Word: word, Rank: rank})
		}
	}
	sort.Slice(out, func(a, b int) bool { return out[a].Rank < out[b].Rank })
	return out
}

// テーマ未指定のとき key_word からテーマを決める条件（FindBestTopic の引数）。
//
// 類似度が TopicMatchThreshold 以上のテーマを上位 TopicMatchTopK 件まで残し、
// その中から1つ引く。argmax にしないのは、テーマ embedding の重心の高さで
// 特定テーマ（BLドラマ）が全語で1位になるため。
// セット生成で語ごとにテーマを決める側（sentence.SelectTargetWords）も
// 同じ条件を使うので、定数にして片方だけずれないようにする。
// 静的コーパスのマニフェスト（cmd/corpus）も同じ定数で語×テーマを起こす。
// serve 側が指定しうるテーマとコーパスの在庫を一致させるため、ここを動かすと
// コーパスの再生成が要る。
//
// 閾値は全語×全テーマの類似度中央値（0.530）付近に置くと、通過テーマ数が
// そのまま語ごとの在庫数になって谷ができる。0.545 では 1201 語が 5 本未満、
// うち ยาว のように 1 テーマだけ通った語は在庫1本＝毎回同じ文になっていた。
// 0.52 まで下げると 5 本未満は 116 語。候補が増えるぶん重心バイアスも薄まり、
// BLドラマが実際に引かれる期待値は 19.7% → 16.9% に下がる。
const (
	TopicMatchTopK      = 5
	TopicMatchThreshold = 0.52
)

// TopicEmbedder はテーマ選択に使う embedding 参照。
// 実装は internal/embeddings.Store。
type TopicEmbedder interface {
	Embedding(word string) []float32
	FindBestTopic(ctx context.Context, word string, topics []string, topK int, threshold float64) (string, error)
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
// 2. テーマ指定があればそのテーマをそのまま使う。key_word はテーマで絞らない
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
	topic := req.Topic

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
	if len(zeroP) > 0 {
		selected = s.SelectWeighted(zeroP, ZeroPWeights(zeroP), req.Count)
	} else {
		selected = s.selectUnknown(candidates, pMap, req.Count)
	}

	// 選出が req.Count に足りないと、セットがその本数で欠ける（例文5本が
	// 1本で返る）。帯の未出語（zeroP）が尽きかけていると、SelectWeighted は
	// zeroP の数しか返さない。
	// prod 2026-09-12: 帯59語のうち未出が1語だけ残った premium ユーザーが、
	// おまかせで1本しか受け取れなかった。
	// 足りなければ帯の残りから埋める（未出→既出の順は TopUpFromBand）。
	if len(selected) < req.Count {
		rest := remaining(candidates, selected)
		// 帯の中で埋まらないときのために、帯の前方（ランクの大きい側）へ
		// ForwardTopUpDepth ぶん広げた語も一緒に見る。帯の既出を使い回すより、
		// 前方の未出を出すほうが「まだ習っていない語を出す」帯の意図に合う。
		forwardHigh := scanHigh + ForwardTopUpDepth
		if req.MaxVocab != nil {
			// free は語彙上限を越えない。上限に張り付いている帯では前方ぶんが
			// 空になり、従来どおり帯の中だけで埋める。
			forwardHigh = min(forwardHigh, *req.MaxVocab)
		}
		forward := BandCandidates(freqRank, scanHigh+1, forwardHigh)
		if len(rest)+len(forward) > 0 {
			// P を読み直すのは、足りないと分かったときだけ。
			restP, err := s.fetchP(ctx, db, req.UID, append(append([]Candidate(nil), rest...), forward...))
			if err != nil {
				return nil, "", err
			}
			selected = TopUpFromBand(selected, rest, forward, restP, req.Count)
		}
	}

	words := make([]string, len(selected))
	for i, c := range selected {
		words[i] = c.Word
	}

	chosenTopic := topic
	if chosenTopic == "" && s.Emb != nil && len(words) > 0 {
		// 閾値未達（＝key_word がどのテーマとも結びつかない機能語など）は
		// "" のまま返し、テーマを LLM に決めさせる。ランダムに埋めない。
		chosenTopic, err = s.Emb.FindBestTopic(
			ctx, words[0], req.TopicsPool, TopicMatchTopK, TopicMatchThreshold)
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

// remaining は band から selected の語を除いたもの。
func remaining(band, selected []Candidate) []Candidate {
	taken := make(map[string]bool, len(selected))
	for _, c := range selected {
		taken[c.Word] = true
	}
	rest := make([]Candidate, 0, len(band))
	for _, c := range band {
		if !taken[c.Word] {
			rest = append(rest, c)
		}
	}
	return rest
}

// TopUpFromBand は選出が count に足りないとき、帯の残り（rest）と、帯の前方へ
// 広げたぶん（forward）から埋める。
//
// 使う順は 3 段:
//  1. 帯の未出（P=0 か未登録）。ランクの小さい側から。帯の中は易しい語を先に
//     出す（ZeroPWeights が本選出で低ランクを重く見るのと同じ向き）。
//  2. 帯の前方（ランクの大きい側）の外にある未出（forward）。帯に近い側から。
//     帯の中では 5 本に届かない人—帯を使い切った premium ユーザーや、テーマ
//     一致語が数語しかない場合—はここで埋まる。帯の上端から 1 ランクずつ前へ
//     進む形なので難度は跳ばない。
//  3. 帯の既出。ランクの小さい側から。既出を key_word にするのは最後の手段。
//
// テーマの閾値は見ない。閾値を満たす語が帯に 1 つも無いときに ClosestToTopic で
// 埋めるのと同じ扱いで、「テーマから少し離れた語」より「本数が欠けたセット」の
// ほうが困るという判断。
func TopUpFromBand(
	selected, rest, forward []Candidate, pMap map[string]float64, count int,
) []Candidate {
	ordered := append([]Candidate(nil), rest...)
	sort.SliceStable(ordered, func(i, j int) bool {
		return ordered[i].Rank < ordered[j].Rank
	})

	var zeroP, known []Candidate
	for _, c := range ordered {
		if p, ok := pMap[c.Word]; !ok || p == 0.0 {
			zeroP = append(zeroP, c)
		} else {
			known = append(known, c)
		}
	}

	// 帯の外も帯に近い側（＝ランクの小さい側）から。帯の上端の続きとして
	// 1 ランクずつ前へ進む形にして、難度が跳ねないようにする。既出は飛ばす。
	fwd := append([]Candidate(nil), forward...)
	sort.SliceStable(fwd, func(i, j int) bool { return fwd[i].Rank < fwd[j].Rank })
	var fwdZeroP []Candidate
	for _, c := range fwd {
		if p, ok := pMap[c.Word]; !ok || p == 0.0 {
			fwdZeroP = append(fwdZeroP, c)
		}
	}

	out := selected
	for _, pool := range [][]Candidate{zeroP, fwdZeroP, known} {
		for _, c := range pool {
			if len(out) >= count {
				return out
			}
			out = append(out, c)
		}
	}
	return out
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
