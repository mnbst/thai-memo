package uvm

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
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

// CeilingAheadScale は語彙テストの上限（最上段の High）に届いた人の前方幅を
// est に比例させる率。前方幅は max(ScanBand の前方, est×この率)。
//
// ScanBand の前方は est が上がるほど狭まり、測定値から 60 上がると 8 で固定
// される。1 日の伸びがスコアによらず一定の順位数で頭打ちになるので、上限
// 3000 で測定が止まった人は真値が上にあっても 90 日で 3500 付近までしか
// 届かなかった（真値 6000 で d90 −2424）。
//
// 上限に届いた人だけに効かせる。測定値が上限未満の帯では、どの率でも
// 広げるほど上振れが増え、現行が最適だった（ceilingsim_test.go の
// TestAheadScaleByBand）。上限到達者は真値 3000〜6000 が同じ測定値に
// 見えるので、そのどれでも外さない率を取った。d90 誤差（世界 推測0.25/slip0 と
// 推測0.45/slip0.10）:
//
//	率     真値3000      3500       4500        6000
//	0%     +85/+106     +11/−29   −924/−1007  −2424/−2507
//	1%     +227/+595   +248/+329   +49/−170   −1267/−1665
//	1.5%   +395/+892   +384/+700  +244/+394     −11/−381
//	2%     +531/+1092  +354/+994  +315/+650    +171/+153
//
// 真値 3000 の上振れは、広い前方でまぐれ当たりした語が knownMaxRank を
// 押し上げるため。
const CeilingAheadScale = 0.015

// KeyWordBand は key_word 候補のランク帯を返す。
//
// 測定値（tested）を原点として ScanBand を取り、測定値ぶん平行移動する
// （EstimateVocab の floor と揃える）。測定値が語彙テストの上限に届いて
// いる人は、前方を est×CeilingAheadScale まで広げる。未受験は tested=0。
func KeyWordBand(estimatedVocab, tested int) (low, high int) {
	tested = max(tested, 0)
	low, high = ScanBand(max(estimatedVocab-tested, 0))
	low += tested
	high += tested
	if tested >= TestStages[len(TestStages)-1].High {
		high = max(high, estimatedVocab+int(CeilingAheadScale*float64(estimatedVocab)))
	}
	return low, high
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
// selectLeaning は prefer が真の未出語を先に、残りを未出語から選ぶ。
// どちらの中でも重みは ZeroPWeights（低ランク優先）のまま。
func (s *SessionSelector) selectLeaning(
	zeroP []Candidate, prefer func(string) bool, count int,
) []Candidate {
	var lean, rest []Candidate
	for _, c := range zeroP {
		if prefer(c.Word) {
			lean = append(lean, c)
		} else {
			rest = append(rest, c)
		}
	}
	picked := s.SelectWeighted(lean, ZeroPWeights(lean), count)
	if len(picked) < count && len(rest) > 0 {
		picked = append(picked, s.SelectWeighted(rest, ZeroPWeights(rest), count-len(picked))...)
	}
	return picked
}

// selectLeaningEach は枠ごとに寄せ先が違う selectLeaning。i 番目の枠は
// prefers[i] が真の未出語から1語、無ければ残りの未出語から1語選ぶ。
// 選んだ語は以降の枠の候補から外す。
func (s *SessionSelector) selectLeaningEach(
	zeroP []Candidate, prefers []func(string) bool, count int,
) []Candidate {
	pool := append([]Candidate(nil), zeroP...)
	var picked []Candidate
	for i := 0; i < count && len(pool) > 0; i++ {
		var lean []int
		if i < len(prefers) && prefers[i] != nil {
			for j, c := range pool {
				if prefers[i](c.Word) {
					lean = append(lean, j)
				}
			}
		}
		if len(lean) == 0 {
			lean = make([]int, len(pool))
			for j := range pool {
				lean[j] = j
			}
		}
		cands := make([]Candidate, len(lean))
		for k, j := range lean {
			cands[k] = pool[j]
		}
		j := lean[s.weightedPick(ZeroPWeights(cands))]
		picked = append(picked, pool[j])
		pool = append(pool[:j], pool[j+1:]...)
	}
	return picked
}

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

// selectUnknown は帯に未出語が無いときの選び方。last_seen の古い語から順に取る
// （同時刻はランクの小さい側から）。
//
// 以前は 1-P 重みの抽選だったが、帯が動かない間は同じ数十語が数日おきに
// 出続けた（prod 2026-10-15〜29: est 435〜445 で止まった premium ユーザーに、
// 延べ 470 語のうち 98 種類、同じ語が平均 5 回）。帯は 50〜60 語しか無いので
// 回数は減らせないが、古い順にすると間隔が最大になる。90日シミュレーション
// （TestSeenOrder。last_seen は key_word にした日とクイズに答えた日）で、
// 7 日以内に見た語をまた選ぶ割合が 50〜60% → 6〜33%、d90 の推定値は −15〜0。
// 帯を前方へ広げて未出を出す案は、推定値が真値より 250〜360 上振れたので採らない。
func (s *SessionSelector) selectUnknown(cands []Candidate, lastSeen map[string]float64, count int) []Candidate {
	pool := oldestFirst(cands, lastSeen)
	return pool[:min(count, len(pool))]
}

// oldestFirst は last_seen の古い順（同時刻はランク順）に並べ替えた写しを返す。
func oldestFirst(cands []Candidate, lastSeen map[string]float64) []Candidate {
	out := append([]Candidate(nil), cands...)
	sort.SliceStable(out, func(i, j int) bool {
		a, b := lastSeen[out[i].Word], lastSeen[out[j].Word]
		if a != b {
			return a < b
		}
		return out[i].Rank < out[j].Rank
	})
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
	// Prefer はテーマ寄せ（ThemeLean）。nil でなければ、帯の未出語のうち
	// Prefer が真の語を先に選ぶ。est 以下だけに寄せると前方の語がほぼ出ず
	// est が進まない。帯全体に寄せると素通りは増える（themesim_test.go。
	// 真値350・合う語18%で 36→113 語）が、テーマ指定時の進みを優先する。
	Prefer func(word string) bool
	// PreferEach は枠ごとのテーマ寄せ（premium おまかせ）。i 番目の語は
	// PreferEach[i] が真の未出語から先に選ぶ。Prefer より優先する。
	PreferEach []func(word string) bool
	// SkipTopicMatch が真なら、テーマ未指定でも FindBestTopic でテーマを決めない
	// （呼び出し側が場面合致でテーマを決める）。
	SkipTopicMatch bool
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
	scanLow, scanHigh := KeyWordBand(estimatedVocab, tested)
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

	pMap, lastSeen, err := s.fetchP(ctx, db, req.UID, candidates)
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
	if len(zeroP) > 0 && req.PreferEach != nil {
		selected = s.selectLeaningEach(zeroP, req.PreferEach, req.Count)
	} else if len(zeroP) > 0 && req.Prefer != nil {
		selected = s.selectLeaning(zeroP, req.Prefer, req.Count)
	} else if len(zeroP) > 0 {
		selected = s.SelectWeighted(zeroP, ZeroPWeights(zeroP), req.Count)
	} else {
		selected = s.selectUnknown(candidates, lastSeen, req.Count)
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
			restP, restSeen, err := s.fetchP(ctx, db, req.UID, append(append([]Candidate(nil), rest...), forward...))
			if err != nil {
				return nil, "", err
			}
			selected = TopUpFromBand(selected, rest, forward, restP, restSeen, req.Count)
		}
	}

	words := make([]string, len(selected))
	for i, c := range selected {
		words[i] = c.Word
	}

	chosenTopic := topic
	if chosenTopic == "" && !req.SkipTopicMatch && s.Emb != nil && len(words) > 0 {
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
		"user":            userHash(req.UID),
		"topic":           chosenTopic,
		"estimated_vocab": estimatedVocab,
		"scan":            []int{scanLow, scanHigh},
		"selected":        words,
	}); err == nil {
		log.Print(string(line))
	}

	return words, chosenTopic, nil
}

// userHash はログで同じ人の選出を追うための uid の短いハッシュ。uid そのものは残さない。
func userHash(uid string) string {
	sum := sha256.Sum256([]byte("get_session_words\x00" + uid))
	return hex.EncodeToString(sum[:6])
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
//  3. 帯の既出。last_seen の古い側から（selectUnknown と同じ）。既出を
//     key_word にするのは最後の手段。
//
// テーマの閾値は見ない。閾値を満たす語が帯に 1 つも無いときに ClosestToTopic で
// 埋めるのと同じ扱いで、「テーマから少し離れた語」より「本数が欠けたセット」の
// ほうが困るという判断。
func TopUpFromBand(
	selected, rest, forward []Candidate, pMap, lastSeen map[string]float64, count int,
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
	for _, pool := range [][]Candidate{zeroP, fwdZeroP, oldestFirst(known, lastSeen)} {
		for _, c := range pool {
			if len(out) >= count {
				return out
			}
			out = append(out, c)
		}
	}
	return out
}

// fetchP は候補語の UVM ドキュメントを一括で読み、p と last_seen（Unix 秒）を集める。
// 数値でない p は Python の isinstance チェックと同じく無視する。
func (s *SessionSelector) fetchP(
	ctx context.Context, db *firestore.Client, uid string, candidates []Candidate,
) (map[string]float64, map[string]float64, error) {
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
		return nil, nil, err
	}
	pMap := map[string]float64{}
	lastSeen := map[string]float64{}
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
		switch n := snap.Data()["last_seen"].(type) {
		case float64:
			lastSeen[snap.Ref.ID] = n
		case int64:
			lastSeen[snap.Ref.ID] = float64(n)
		}
	}
	return pMap, lastSeen, nil
}
