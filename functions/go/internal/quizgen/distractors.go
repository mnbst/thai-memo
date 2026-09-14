package quizgen

import (
	"hash/fnv"
	"math/rand"
	"sort"
	"strings"
)

// ダミー選択肢をルールベースで選ぶときの既定値。
const (
	// DistractorBand は正解の前後どこまでのランクから採るか。
	//
	// 帯を広げるほど「知らない語ばかりの4択」に近づき、狭めるほど候補が
	// 尽きて LLM 生成へ落ちる。±150 は freq_rank 上位10,000語のうち
	// 3%ぶんで、学習者が同じ時期に出会う語がだいたい収まる幅。
	DistractorBand = 150
	// DistractorWiden は候補が足りないときに帯を広げる回数。
	// 広げるたびに幅は倍。3回で ±1200 まで伸ばし、そこまでで揃わなければ
	// 諦めて LLM 生成へ落とす。
	DistractorWiden = 3
	// DistractorCount は選ぶ件数。4択なので正解以外の3件。
	DistractorCount = 3
)

// conflictingPOS は「品詞は違うが同じ位置に立てる」組。ダミーから外す。
//
// 品詞違いだけを条件にすると、空欄に入りうる語が混じる。実測で出たのが
// 代名詞と名詞で、正解 ฉัน の問題に พ่อ（父）が入り、モデルの理由が
// 「主語として配置可能だが…」と、入りうることを認める書き方になった
// （2026-09-12）。理由が書けない候補は、そもそも選ばせない。
//
// 対称に効かせるので、片方向だけ書けばよい（conflicts が両向き見る）。
var conflictingPOS = map[string][]string{
	// 主語・目的語の位置を共有する。
	"代名詞": {"名詞", "固有名詞"},
	// タイ語の形容詞は述語になれる（動詞と同じ位置）。修飾では副詞と並ぶ。
	"形容詞": {"動詞", "副詞"},
	// 動詞の前に置いて述語を修飾する位置を共有する。
	"助動詞": {"否定詞", "副詞"},
	// 名詞句の後ろに付いて数量・指示を表す位置を共有する。
	"限定詞": {"数詞", "類別詞"},
	// 句の頭に立って後続を導く位置を共有する。
	"接続詞": {"前置詞"},
}

// conflicts は2つの品詞が同じ位置に立ちうるか。同じ品詞同士も真。
func conflicts(a, b string) bool {
	if a == b {
		return true
	}
	for _, other := range conflictingPOS[a] {
		if other == b {
			return true
		}
	}
	for _, other := range conflictingPOS[b] {
		if other == a {
			return true
		}
	}
	return false
}

// Vocab はダミー選択肢を選ぶための語彙情報。
//
// 実装は freq_rank（語→ランク）と品詞タガー、語クラス辞書を持つ側
// （package function の quizVocab）。quizgen は文字列処理だけの層に
// しておきたいので、ここではインターフェースで受ける。
type Vocab interface {
	// Rank は語の頻度ランク。未知語は ok=false。
	Rank(word string) (rank int, ok bool)
	// WordsInRange は [low, high] のランクに入る語を返す（順不同でよい）。
	WordsInRange(low, high int) []string
	// POS は品詞ラベル。判定できなければ空文字。
	//
	// trusted は「文脈の中で付いた品詞か」。語を単体でタグ付けした結果は
	// ぶれるので（実測: ตอนนี้→接続詞）、ダミー候補は trusted のものだけ使う。
	// 正解側は trusted でなくても使う（そこで諦めるとダミーを作れない）。
	POS(word string) (pos string, trusted bool)
	// IsFunctionWord は類別詞・指示詞・語気助詞など、入れ替えても
	// 文法上成立してしまいやすい機能語かどうか。
	IsFunctionWord(word string) bool
}

// PickDistractors は正解と同じランク帯から、品詞の違う語を3件選ぶ。
//
// 条件は「複数正解を作らない」ことから決めている。
//
//   - 品詞が正解と違い、同じ位置に立てる組でもない（conflictingPOS）:
//     同じ品詞の語は空欄に入りうる（プロンプトの【NG例】กิน___ →
//     ข้าว/ผัก/เนื้อ がこれ）。品詞が違っても代名詞と名詞のように
//     位置を共有する組は同じことが起きる
//   - 機能語を外す: 類別詞同士・指示詞同士は複数成立する（同【NG例】）
//   - 文中の語を外す: 同じ文にある語は入れ替えても意味が通りやすい
//   - 品詞が信用できる語だけ使う: 語単体のタグ付けはぶれるので、文脈で
//     付いた品詞（辞書）がある語に限る
//
// 3件揃わなければ nil を返す。呼び出し側は従来どおり LLM にダミーを
// 作らせる（この関数が扱えるのは freq_rank に載っている語だけで、
// ランク外の語が正解のときは候補帯そのものが作れない）。
//
// rnd が nil のときは文と正解から決まる固定の乱数で引く。毎回違う3件を
// 返すと、同じ問題でも選択肢が変わってクイズのキャッシュ
// （quiz_cloze_cache.go）が当たらない。SRS は同じ例文を1/3/7/14/30日後に
// 出し直すので、ここが決定的でないとそのたびにモデルを呼ぶことになる。
func PickDistractors(v Vocab, answer string, sentenceWords []string, rnd *rand.Rand) []string {
	if v == nil || answer == "" {
		return nil
	}
	rank, ok := v.Rank(answer)
	if !ok {
		return nil
	}
	answerPOS, _ := v.POS(answer)
	if answerPOS == "" {
		// 正解の品詞が分からないと「違う品詞」を選べない。
		return nil
	}

	inSentence := make(map[string]bool, len(sentenceWords))
	for _, w := range sentenceWords {
		inSentence[normalizeText(w)] = true
	}

	if rnd == nil {
		rnd = rand.New(rand.NewSource(seedFor(answer, sentenceWords)))
	}

	picked := make([]string, 0, DistractorCount)
	usedPOS := map[string]bool{}
	seen := map[string]bool{answer: true}

	band := DistractorBand
	for range DistractorWiden {
		candidates := v.WordsInRange(max(0, rank-band), rank+band)
		// 並べ替える前に順序を固定する。Vocab の実装（map の反復など）で
		// 並びが変わると、同じ種から引いても結果が変わってキャッシュが
		// 当たらなくなる。決定性はこの関数側で担保する。
		sort.Strings(candidates)
		shuffleN(len(candidates), func(i, j int) {
			candidates[i], candidates[j] = candidates[j], candidates[i]
		}, rnd)

		// 品詞がばらけるように2周する。1周目は未使用の品詞だけ採り、
		// 足りなければ2周目で重複を許す。ダミーの品詞が3件とも同じだと、
		// dummy_reasons の3行も同じ理由になる（プロンプトが禁じている形）。
		for _, allowSamePOS := range []bool{false, true} {
			for _, word := range candidates {
				if len(picked) >= DistractorCount {
					return picked
				}
				if seen[word] || inSentence[normalizeText(word)] {
					continue
				}
				if v.IsFunctionWord(word) {
					continue
				}
				pos, trusted := v.POS(word)
				if pos == "" || !trusted || conflicts(answerPOS, pos) {
					continue
				}
				if !allowSamePOS && usedPOS[pos] {
					continue
				}
				seen[word] = true
				usedPOS[pos] = true
				picked = append(picked, word)
			}
		}
		if len(picked) >= DistractorCount {
			return picked
		}
		band *= 2
	}
	if len(picked) < DistractorCount {
		return nil
	}
	return picked
}

// shuffleN は rnd が nil なら共有の乱数源で並べ替える。
func shuffleN(n int, swap func(i, j int), rnd *rand.Rand) {
	if rnd != nil {
		rnd.Shuffle(n, swap)
		return
	}
	rand.Shuffle(n, swap)
}

// seedFor は文と正解から決まる乱数の種。同じ問題なら毎回同じ3件を返す。
func seedFor(answer string, sentenceWords []string) int64 {
	h := fnv.New64a()
	h.Write([]byte(answer))
	h.Write([]byte{0})
	h.Write([]byte(strings.Join(sentenceWords, "\x00")))
	return int64(h.Sum64())
}
