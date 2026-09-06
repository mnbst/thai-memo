package uvm

import (
	"math"
	"math/rand"
)

// 語彙テスト（オンボーディング末尾と設定画面の再試験）の純ロジック。
//
// estimated_vocab はクイズの正誤という弱い信号でしか動かず、初日から実力帯へ
// 届かせる手段が無い。テストはその唯一の例外として、測定値を直接書く。
// 迂回路になるので、呼び出し側でプレミアム限定と、サーバー採点を掛けること。
//
// 出発点を作る経路はこれだけ。自己申告レベルは estimated_vocab に一切入れない
// （SyncEstimatedVocab のコメントを参照）。開始段も申告では動かさず、全員
// 1 段目から測る。申告で下の段を飛ばすと、飛ばした帯を暗黙に通過扱いにする
// ぶんスコアが上振れるうえ、開始段がクライアントの任意入力になる。
//
// 語ごとの P は「間違えた」証拠しか残さない（TestSeedP）。測定値は
// estimated_vocab に直接書くので、正解を既知語として置き直す必要はない。

// TestStage は出題する 1 段のランク帯（両端含む）。
type TestStage struct {
	Low  int
	High int
}

// TestStages は下から順の階段。上へ行くほど帯を広く取る（高ランクほど
// 語彙差が緩やかに開くので、等幅にすると上位が無駄に細かくなる）。
//
// 上限は 3000。900 で止めていた頃は、タイ語検定 2 級相当の層が最上段まで
// 全通過して天井に張り付き、測定にならなかった。freq_rank は上位 1 万語まで
// あるが、3000 より上は低頻度語ばかりで同じ段から 4 択の誤答を作れなくなる
// （識別力が落ちる）ので、まずここまで。
//
// 900 より上を 300〜500 幅に刻んであるのは、測定誤差が帯の幅に比例するため。
// まぐれで 1 段抜けたときに乗る下駄も、落ちた段を内挿する誤差も、幅が広いほど
// 大きい。900 超えを 500/700/900 幅の 3 段にしたときと 5 段に刻んだときで、
// 真値2000 の誤差は +461 → +300（実効推測率 0.55）。出題は 5 問増える。
var TestStages = []TestStage{
	{1, 50},
	{51, 150},
	{151, 300},
	{301, 450},
	{451, 600},
	{601, 900},
	{901, 1200},
	{1201, 1600},
	{1601, 2100},
	{2101, 2600},
	{2601, 3000},
}

const (
	// TestItemsPerStage は 1 段あたりの出題数。
	//
	// 4 問だった頃は「1 段 1 問も落とせない」ゲートで、段を 11 段に伸ばした
	// とたんに上位層が途中で落ちるようになった（下の表）。段あたりの問題数を
	// 増やして、通過本数に 1 問ぶんの余裕を作るための 6。
	TestItemsPerStage = 6

	// TestPassThreshold は次の段へ上がるのに要る正答数。6 問中 5 問。
	//
	// 3 問通過（4 問中）にしていた頃は測定値が実際より大きく出た。誤答の選択肢を
	// 同じ段の語の訳から作る以上、消去法と部分再認で実効の推測正答率は 4 択の
	// 0.25 より高くなり、採点式の前提（TestChanceRate）とずれるため。そこで
	// 全問正解（4 問中 4 問）に振ったが、今度は「知っていてもうっかり 1 問」で
	// その段で終わる。段が 6 段のうちは天井が 900 で影響が小さかったが、
	// 3000 まで伸ばすと下振れが致命的になる。
	//
	// scoresim_test.go（4000 試行、pKnow はロジスティック scale 60）の
	// 真値に対する誤差。slip は「知っている語をうっかり落とす」確率、
	// 内挿は TestChanceRate:
	//
	//	推測率/slip  構成                 真値350  700  1200  2000  出題数(真値2000)
	//	0.25 / 0.00  旧6段900 4問4通過      -40   -24  -300 -1100   24問（天井張り付き）
	//	0.25 / 0.00  9段 6問5通過 内挿0.25    +4   +19   +59  +127   53問
	//	0.25 / 0.00  今の構成                -8    -6   +17   +46   58問
	//	0.55 / 0.00  旧6段900 4問4通過      +24   +55  -300 -1100   24問
	//	0.55 / 0.00  9段 6問5通過 内挿0.25  +103  +220  +376  +461   54問
	//	0.55 / 0.00  今の構成               +89  +147  +214  +260   60問
	//	0.45 / 0.10  旧6段900 4問4通過     -122  -324  -782 -1571   15問（途中で落ちる）
	//	0.45 / 0.10  9段 6問5通過 内挿0.25    +1    -1   -43  -157   46問
	//	0.45 / 0.10  今の構成                +1   -38  -131  -301   50問
	//
	// 4 問全問正解のゲートは、slip があるとどの段でも止まりうるので上位層が
	// まったく測れない（真値2000 が -1571）。6 問 5 通過は 1 問ぶんの余裕を
	// 作りつつ、当てずっぽうで通る確率は低い（実効 0.55 でも 5/6 以上は 16%。
	// 4 問中 3 問通過は 39%）ので、3 問通過へ戻すのとは違う。
	//
	// 残るのは「うっかりが無く推測だけ上手い層」の上振れ（推測 0.55・slip 0 で
	// 真値2000 が +260）と、その裏返しの下振れ（推測 0.45・slip 0.10 で -301）。
	// 4 択である限り「消去法で当てた」と「半分知っている」は見分けられないので、
	// ここから先はゲートではなく帯の幅と内挿（TestStages / TestChanceRate）で
	// 削るしかない。試した中では確認段（最後に通過した段をもう 1 度出す）が
	// 上振れに効いた（+260 → +172）が、下振れが -301 → -379 に伸びて
	// 出題も 6 問増えるので取らなかった。二分追試（落ちた帯の下半分で
	// もう 1 段）は散り（SD）だけ縮んで偏りは動かない。
	TestPassThreshold = 5

	// TestChanceRate は落ちた段を内挿するときに差し引く推測正答率。
	//
	// 4 択の名目は 0.25 だが、誤答の選択肢を同じ段の語の訳から作る以上、
	// 消去法と部分再認で実効はそれより高い。名目の 0.25 で内挿すると、
	// 知らない帯を当てずっぽうで 0.5 正答した人に帯の 1/3 を与えてしまう
	// （幅 900 の段なら +300）。実効寄りの 0.35 に置いて、その下駄を削る。
	//
	// ゲート（TestPassThreshold）とは独立に効く。0.25→0.35 で真値2000 の
	// 誤差は +461 → +399（実効推測率 0.55）、素直な層（実効 0.25）の
	// +127 → +82。上へも下へも 0.1/(1-0.25) ≒ 帯幅の 13% 動く。
	TestChanceRate = 0.35

	// ScoreBias は測定値から差し引く上振れ補正。
	//
	// 3 問通過だった頃は 50 を引いていた（内挿が帯の中の一様分布を前提に
	// しているぶん上振れるため）。通過条件を締めて上振れの主因を断ったので、
	// 二重に沈めないよう 0 に戻した。上表の誤差はこの 0 での値。
	// 補正を足すのは、実データで一貫した上振れを測ってから。
	ScoreBias = 0
)

// StageResult は 1 段ぶんの結果。
type StageResult struct {
	// Stage は TestStages の添字。
	Stage int
	// Correct は正答数（0..TestItemsPerStage）。
	Correct int
}

// Passed はその段を通過したか。
func (r StageResult) Passed() bool { return r.Correct >= TestPassThreshold }

// NextStage は履歴から次に出す段を返す。done が真なら出題は終わり。
//
//   - 通過（TestPassThreshold 以上）: 1 段上へ。天井まで通過したら終了
//   - 不通過: そこで終了
//
// 常に 1 段目から始めるので、下へ戻す経路は要らない。申告レベルで開始段を
// 上げていた頃は「申告が高すぎた人をスコア 0 にしない」ための下降があったが、
// 申告を使うのをやめたので消した。
func NextStage(history []StageResult) (stage int, done bool) {
	if len(history) == 0 {
		return 0, false
	}
	last := history[len(history)-1]

	if last.Passed() && last.Stage+1 < len(TestStages) {
		return last.Stage + 1, false
	}
	return 0, true
}

// ScoreVocab は履歴を estimated_vocab へ変換する。
//
// 落ちた段の中を、推測補正した正答率で内挿する。
//
//	c     = clamp((正答率 - TestChanceRate) / (1 - TestChanceRate), 0, 1)
//	vocab = 落ちた段の下限 - 1 + c * 段の幅
//
// 全段通過なら最上段の上限。通過済みの段の上限は下回らせない。
func ScoreVocab(history []StageResult) int {
	passedHigh := 0
	failed := -1
	for _, r := range history {
		if r.Passed() {
			if TestStages[r.Stage].High > passedHigh {
				passedHigh = TestStages[r.Stage].High
			}
			continue
		}
		if failed < 0 || r.Stage < failed {
			failed = r.Stage
		}
	}
	if failed < 0 {
		return applyScoreBias(passedHigh)
	}

	band := TestStages[failed]
	rate := float64(0)
	if TestItemsPerStage > 0 {
		rate = float64(historyCorrect(history, failed)) / float64(TestItemsPerStage)
	}
	c := (rate - TestChanceRate) / (1 - TestChanceRate)
	c = math.Max(0, math.Min(1, c))

	width := band.High - band.Low + 1
	vocab := band.Low - 1 + int(math.Round(c*float64(width)))
	return applyScoreBias(max(vocab, passedHigh))
}

// applyScoreBias は上振れ補正を掛ける（ScoreBias を参照）。
func applyScoreBias(vocab int) int {
	return max(0, vocab-ScoreBias)
}

// historyCorrect は指定した段の正答数。
func historyCorrect(history []StageResult, stage int) int {
	for _, r := range history {
		if r.Stage == stage {
			return r.Correct
		}
	}
	return 0
}

// TestSeedP は出題語の P をどう書き換えるかを返す。
// write が偽なら doc を作らない（既存 doc があれば呼び出し側が触らない）。
//
// 正解は書かない。以前は測定した境界より下の正解に TestKnownP(0.8) を置いて
// いたが、
//
//   - 巻き戻る。再受験で estimated_vocab を下げても、前回の 0.8 は上に残り、
//     窓の平均を押し上げて以後の sync が前回の測定値まで登り直す
//     （1回目300→2回目100 で、約60回の sync で 289 へ戻る）
//   - 精度が上がらない。本番の帯（KeyWordBand）で 30 日回すと、置いても
//     置かなくても d30 の差は数語。真値350 だけは置かないほうが真値に近い
//     （440 → 399）。0.8 は knownMaxRank の床として上振れを固定していただけ
//
// 未登録語の誤答も書かない。以前は 0.15 を置いていたが、
//
//   - 下方修正には効かない。平均は 21 ランクの窓で、未登録の
//     UnknownWordP(0.4) を 0.15 に置き換えても、7 語まとめて同じ窓に入れて
//     ようやく平均 0.317。測定値以下の cutoff 0.30 を割れない。実際に窓へ
//     入るのは落ちた段の 1〜2 語だけ
//   - key_word の候補から外れる。GetSessionWords は「未登録 or P=0」を
//     未出題として拾うので、0.15 が入った語は候補に上がらない
//
// つまり「知らないと分かった語」だけが出題されなくなっていた。書かなければ
// 未登録のまま残り、優先して出題される。
//
// 残るのは既存 doc の誤答だけ。積んだ履歴のほうが 4 択 1 問より信頼できるので、
// 半分に落とすに留める。
//
// スコアの決定は集約統計（推測補正した内挿）に任せ、P の種付けはその結論と
// 矛盾しない範囲でだけ行う、という分担にしている。
func TestSeedP(oldP float64, exists, correct bool) (p float64, write bool) {
	if !exists || correct {
		return 0, false
	}
	return math.Max(PMin, oldP*0.5), true
}

// TestQuestion は出題 1 問。AnswerIndex はサーバー側にだけ残し、
// クライアントへは Word と Choices しか返さない（採点を信用できなくなる）。
type TestQuestion struct {
	Word string
	// Rank は種付けで境界と比べるために持つ。
	Rank        int
	Choices     []string
	AnswerIndex int
}

// BuildStageQuestions は 1 段ぶんの 4 択を組む。
//
// 誤答は同じ段の語の訳から引く。難度の違う訳を混ぜると、意味を知らなくても
// 消去法で当てられてしまう。段内で足りないときだけ全体から補う。
// 出せた問題数が n に満たなければその数だけ返す（呼び出し側が判断する）。
//
// 選択肢が 4 つ揃わない語は捨てるので、候補は先頭 n 語ではなく、n 語ぶん
// 揃うまで見る。先頭 n 語だけを見ていた頃は、訳が重複した語を 1 つ引いた
// だけで段が 3 問になり、呼び出し側が「出題語が足りません」でテスト全体を
// 落としていた。
func BuildStageQuestions(items []TestItem, stage TestStage, n int, rnd *rand.Rand) []TestQuestion {
	band := make([]TestItem, 0, len(items))
	for _, it := range items {
		if it.Rank >= stage.Low && it.Rank <= stage.High && it.Word != "" && it.Gloss != "" {
			band = append(band, it)
		}
	}
	if len(band) == 0 {
		return nil
	}
	rnd.Shuffle(len(band), func(i, j int) { band[i], band[j] = band[j], band[i] })

	out := make([]TestQuestion, 0, n)
	for _, it := range band {
		if len(out) >= n {
			break
		}
		choices := []string{it.Gloss}
		used := map[string]bool{it.Gloss: true}
		for _, pool := range [][]TestItem{band, items} {
			for _, i := range rnd.Perm(len(pool)) {
				if len(choices) >= 4 {
					break
				}
				g := pool[i].Gloss
				if g == "" || used[g] {
					continue
				}
				used[g] = true
				choices = append(choices, g)
			}
		}
		// 訳の重複で 4 つ揃わない語は出さない（選択肢が減ると当たりやすい）。
		if len(choices) < 4 {
			continue
		}
		rnd.Shuffle(len(choices), func(i, j int) { choices[i], choices[j] = choices[j], choices[i] })

		answer := 0
		for i, c := range choices {
			if c == it.Gloss {
				answer = i
				break
			}
		}
		out = append(out, TestQuestion{
			Word: it.Word, Rank: it.Rank, Choices: choices, AnswerIndex: answer,
		})
	}
	return out
}
