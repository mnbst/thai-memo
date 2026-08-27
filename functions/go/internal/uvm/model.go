// Package uvm は語彙習得モデル（User Vocabulary Model）。
// functions/python/uvm.py の移植。定数と式は Python 側と一致させること。
package uvm

import "math"

// α（1回の正誤で P を動かす幅）のスケーリング定数。
// rank が低い（高頻度な）語ほど alpha_max が大きく、少ない出題で P が上がる。
const (
	AlphaCorrectMaxTop   = 0.60 // rank≈1（高頻度語）の正解α上限: 1問正解でP=0.1→0.64
	AlphaCorrectMaxLow   = 0.30 // 高rank（低頻度語）の正解α下限: 2問正解でP>0.5
	AlphaCorrectMin      = 0.02 // 正解時 α の下限（quiz_attempts 大時の収束値）
	AlphaIncorrectMaxTop = 0.28 // rank≈1 の不正解α上限
	AlphaIncorrectMaxLow = 0.08 // 高rank の不正解α下限
	AlphaIncorrectMin    = 0.02 // 不正解時 α の下限
	AlphaDecayK          = 0.08 // α 減衰係数（quiz_attempts による α 減衰速度）

	// RankScaleRef はこの rank で alpha_max が上限・下限の中間値になる。
	RankScaleRef = 600

	PMin         = 0.0 // P の下限
	PMax         = 0.99
	NewWordP     = 0.1 // 新規単語の初期 P 値
	UnknownWordP = 0.4 // UVM 未登録語の prior P

	// VocabMaxDelta は1回の sync で estimated_vocab が動ける最大幅。
	VocabMaxDelta = 3

	// FreeTierMaxVocab は free ユーザーの estimated_vocab 上限
	// （constants.py の FREE_TIER_MAX_VOCAB）。
	FreeTierMaxVocab = 100

	// LearningCorrectMultiplier は quiz_type=="learning" の正解時に α を弱める係数。
	LearningCorrectMultiplier = 0.1
	// SentenceReviewCorrectMultiplier は例文レビュー由来の正解時に α を弱める係数。
	SentenceReviewCorrectMultiplier = 0.1
)

// UpdateP は P(know) を正誤に基づいて更新する（uvm.py:update_p）。
//
//	scale     = RankScaleRef / (rank + RankScaleRef)   rank が低いほど 1 に近い
//	alpha_max = MAX_LOW + (MAX_TOP - MAX_LOW) * scale
//	正解:   α = MIN + (alpha_max - MIN) * exp(-k * quizAttempts);  p += α*mult*(1-p)
//	不正解: α = MIN + (alpha_max - MIN) * exp(-k * quizAttempts);  p -= α*mult*p
//
// rank が nil のときは scale=0.5（中間値）。結果は [PMin, PMax] にクリップする。
func UpdateP(p float64, correct bool, quizAttempts int, rank *int, hintMultiplier float64) float64 {
	scale := 0.5
	if rank != nil {
		scale = RankScaleRef / (float64(*rank) + RankScaleRef)
	}

	decay := math.Exp(-AlphaDecayK * float64(quizAttempts))
	if correct {
		alphaMax := AlphaCorrectMaxLow + (AlphaCorrectMaxTop-AlphaCorrectMaxLow)*scale
		alpha := AlphaCorrectMin + (alphaMax-AlphaCorrectMin)*decay
		p = p + alpha*hintMultiplier*(1-p)
	} else {
		alphaMax := AlphaIncorrectMaxLow + (AlphaIncorrectMaxTop-AlphaIncorrectMaxLow)*scale
		alpha := AlphaIncorrectMin + (alphaMax-AlphaIncorrectMin)*decay
		p = p - alpha*hintMultiplier*p
	}
	return math.Max(PMin, math.Min(PMax, p))
}

// MovingAvg は rank 周辺の平均習熟度（uvm.py:moving_avg）。
// window = ±10。UVM 未登録語には UnknownWordP を使う。
// freq_rank は拘束形態素を除いた連番なので rank に穴はない。
func MovingAvg(wordsByRank map[int]float64, center, window int) float64 {
	total := 0.0
	for r := center - window; r <= center+window; r++ {
		if p, ok := wordsByRank[r]; ok {
			total += p
		} else {
			total += UnknownWordP
		}
	}
	return total / float64(2*window+1)
}

// RankedP は estimate_vocab に渡す (rank, P) の組。
type RankedP struct {
	Rank int
	P    float64
}

// EstimateVocab は語彙境界（P ≈ 0.5 となる rank）を推定する（uvm.py:estimate_vocab）。
//
// center ± 50 を走査し MovingAvg が 0.42 を下回る最初の rank を返す。
// データがスパースなときは P > 0.5 の語の最大 rank をフォールバックに使う。
func EstimateVocab(entries []RankedP, center int) int {
	if len(entries) == 0 {
		return 0
	}

	wordsByRank := make(map[int]float64, len(entries))
	knownMaxRank := 0
	totalP := 0.0
	weighted := 0.0
	for _, e := range entries {
		wordsByRank[e.Rank] = e.P
		if e.P > 0.5 && e.Rank > knownMaxRank {
			knownMaxRank = e.Rank
		}
		totalP += e.P
		weighted += e.P * float64(e.Rank)
	}

	// center が未指定 (0) のときは P を重みにした加重平均を中心にする。
	if center <= 0 {
		if totalP <= 0 {
			return knownMaxRank
		}
		center = int(weighted / totalP)
	}

	for r := center - 50; r <= center+50; r++ {
		if MovingAvg(wordsByRank, r, 10) < 0.42 {
			return max(knownMaxRank, max(r, 0))
		}
	}
	return max(knownMaxRank, max(center, 0))
}

// HintMultiplier は hint_level から α の倍率を出す（uvm.py:batch_update_uvm）。
// 0=ヒント無し 1.0 / 1=0.5 / それ以外=0.25。
func HintMultiplier(hintLevel int) float64 {
	switch hintLevel {
	case 0:
		return 1.0
	case 1:
		return 0.5
	default:
		return 0.25
	}
}
