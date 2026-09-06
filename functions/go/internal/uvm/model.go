// Package uvm は語彙習得モデル（User Vocabulary Model）。
//
// 旧Python版UVMの移植だが、P の更新則だけは 2026-09 に尤度比へ置き換えた
// （UpdateP / 旧則は UpdatePAlpha）。MovingAvg と EstimateVocab は移行時の
// golden データと一致させること。
package uvm

import "math"

// α（1回の正誤で P を動かす幅）のスケーリング定数。旧更新則 UpdatePAlpha
// 専用で、本番の UpdateP は使わない（golden と比較シミュレーションのために残す）。
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

	PMin = 0.0 // P の下限
	PMax = 0.99
	// UnknownWordP は UVM 未登録語の prior P。
	UnknownWordP = 0.4
	// NewWordP は新規単語の初期 P 値。prior と同じ値でなければならない。
	//
	// 0.1 だった頃は、登録しただけで prior より 0.3 低い値が母数に入り、
	// MovingAvg が 21 ランクあたり 0.0143 押し下がっていた（cutoff まで 0.02 しか
	// 余裕が無い）。同時に「1 問正解で cutoff を越えられるか」が更新則の設計を
	// 縛っていた: 0.1 から 1 問で 0.42 を越すには α≈0.36 が要り、正解側を
	// 大きく取らざるを得ない。prior から始めれば 1 問の正解で素直に越える。
	NewWordP = UnknownWordP

	// FreeTierMaxVocab は free ユーザーの estimated_vocab 上限
	// （constants.py の FREE_TIER_MAX_VOCAB）。
	FreeTierMaxVocab = 100

	// LearningCorrectMultiplier は quiz_type=="learning" の正解を弱める係数。
	LearningCorrectMultiplier = 0.1
	// SentenceReviewCorrectMultiplier は例文レビュー由来の正解を弱める係数。
	SentenceReviewCorrectMultiplier = 0.1

	// BayesGuessTop はヒント無しの 4 択で「知らなくても当たる」確率 g。
	//
	// 素の 4 択なら 0.25 だが、まとめクイズは穴埋めでダミーが品詞・文法で
	// 落とせるよう作られている（quizgen/prompt.go の goodReasonExamples）ので、
	// 対象語を知らなくても周辺のタイ語から当たる。実測できるまでは 0.25 より
	// 高めに置く。g を高く見積もる代償は小幅な過小評価だけだが、低く見積もると
	// まぐれ当たりがそのまま境界に載る（真値150 が d90 316）。
	BayesGuessTop = 0.35
	// BayesSlip は知っている語を落とす確率 s（誤タップ・読み違い）。
	BayesSlip = 0.15

	// MaxGuessRate は GuessRate の上限。
	//
	// g は 1-s を超えてはならない。超えると「知っている人より知らない人のほうが
	// 正解しやすい」という状態になり、尤度比が反転して**正解で P が下がる**。
	// 上限 0.95 で入れたところ、ヒント2段を常用するユーザーの estimated_vocab が
	// 90 日で 4 まで落ちた。1-s=0.85 に対して余裕を取り 0.80 で止める。
	// このとき正解の尤度比は 0.85/0.80=1.06（ほぼ情報なし）、不正解は
	// 0.15/0.20=0.75（訳を見てなお落とすのは弱い「知らない」証拠）。
	MaxGuessRate = 0.80
)

// GuessRate は hint_level ごとの想定推測率 g。ヒントを出すほど選択肢が絞れる
// ので、知らなくても当たる確率が上がる。ヒント 2 段（訳を表示）は
// MaxGuessRate で頭打ちになり、正解してもほとんど証拠にならない。
func GuessRate(hintLevel int) float64 {
	switch hintLevel {
	case 0:
		return BayesGuessTop
	case 1:
		return math.Min(MaxGuessRate, BayesGuessTop*1.8)
	default:
		return math.Min(MaxGuessRate, BayesGuessTop*3.0)
	}
}

// UpdateP は P(know) を尤度比で更新する。
//
//	正解:   LR = (1-s)/g        不正解: LR = s/(1-g)
//	odds' = odds * LR^weight,   P' = odds'/(1+odds')
//
// g は GuessRate（知らなくても当たる確率）、s は BayesSlip（知っていて落とす
// 確率）。weight は証拠の重みで、確認クイズの正解など弱い経路で 1 未満になる。
//
// 旧 α 則（UpdatePAlpha）との違いは不正解側。rank 300 の新語は 1 問正解で
// P=0.55 まで上がるのに 1 問不正解では 0.079 にしか下がらず、まぐれ当たりで
// 既知になった語を後から回収できなかった。実際、知らない語（pKnow<0.5）が
// P>0.5 のまま残る割合は 22〜55%（matrixsim）。尤度比なら正解 +/- が同じ
// 枠組みで入るので、片方向のラチェットにならない。
//
// quiz_attempts も rank も要らない。回数を重ねれば odds が飽和して自然に
// 動かなくなるし、rank ごとの難度は g（と prior）が受け持つ。
func UpdateP(p float64, correct bool, hintLevel int, weight float64) float64 {
	p = math.Max(1e-6, math.Min(1-1e-6, p))
	g := GuessRate(hintLevel)
	lr := BayesSlip / (1 - g)
	if correct {
		lr = (1 - BayesSlip) / g
	}
	odds := p / (1 - p) * math.Pow(lr, weight)
	return math.Max(PMin, math.Min(PMax, odds/(1+odds)))
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
//
// floor は語彙テストの測定値（vocab_test_vocab）。**floor 以下の rank は存在
// しないものとして扱う**。未受験は floor=0 で、その場合の挙動は従来と同一。
//
// 語彙テストを受けた人の出発点を 0 から測定値 M へずらす、という考え方。
// 0 から始めた人が rank<0 を見ないのと同じく、測定値を持つ人は rank<M を見ない。
// これで受験者と未受験者の挙動が「原点が違うだけ」で揃う。
//
// floor を入れないと、受験直後は走査帯に証拠（P>0.5 の語）が 1 つも無いので
// knownMaxRank=0、返り値が center-50 側になり、測定値から
// 0 へ崩れていく（測定100 が数分で 91 まで落ちる）。0 から始めた人が崩れないのは
// 下限 0 に張り付いているからで、その下限を M に置き換えるのがこの引数。
func EstimateVocab(entries []RankedP, center, floor int) int {
	floor = max(floor, 0)

	wordsByRank := make(map[int]float64, len(entries))
	knownMaxRank := 0
	totalP := 0.0
	weighted := 0.0
	n := 0
	for _, e := range entries {
		// floor 以下は「無いもの」。測定値より下に残っている古い doc が
		// 境界を引き戻さないようにする。
		if e.Rank < floor {
			continue
		}
		n++
		wordsByRank[e.Rank] = e.P
		if e.P > 0.5 && e.Rank > knownMaxRank {
			knownMaxRank = e.Rank
		}
		totalP += e.P
		weighted += e.P * float64(e.Rank)
	}
	if n == 0 {
		return floor
	}

	// center が未指定 (0) のときは P を重みにした加重平均を中心にする。
	if center <= 0 {
		if totalP <= 0 {
			return max(knownMaxRank, floor)
		}
		center = int(weighted / totalP)
	}

	for r := max(center-50, floor); r <= center+50; r++ {
		if MovingAvg(wordsByRank, r, 10) < 0.42 {
			return max(knownMaxRank, max(r, floor))
		}
	}
	return max(knownMaxRank, max(center, floor))
}

// HintMultiplier は hint_level から証拠量の倍率を出す（uvm.py:batch_update_uvm）。
// 0=ヒント無し 1.0 / 1=0.5 / それ以外=0.25。
//
// P の更新でヒントを効かせるのは GuessRate 側（推測率が上がる）で、こちらは
// ResultEvidence ＝「境界推定の母数に入れるか」の重みにだけ使う。
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

// UpdatePAlpha は UpdateP を尤度比に置き換える前の α 則（uvm.py:update_p）。
// 本番からは外したが、Python 移行時の golden と、更新則を比較する
// シミュレーション（alphasim_test.go）のために残してある。
//
//	scale     = RankScaleRef / (rank + RankScaleRef)   rank が低いほど 1 に近い
//	alpha_max = MAX_LOW + (MAX_TOP - MAX_LOW) * scale
//	正解:   α = MIN + (alpha_max - MIN) * exp(-k * quizAttempts);  p += α*mult*(1-p)
//	不正解: α = MIN + (alpha_max - MIN) * exp(-k * quizAttempts);  p -= α*mult*p
func UpdatePAlpha(p float64, correct bool, quizAttempts int, rank *int, hintMultiplier float64) float64 {
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
