package function

import (
	"context"
	"log"
	"sort"
	"sync"

	"github.com/mnbst/thai-memo/functions/go/internal/fbapp"
	"github.com/mnbst/thai-memo/functions/go/internal/quizgen"
	"github.com/mnbst/thai-memo/functions/go/internal/thainlp"
	"github.com/mnbst/thai-memo/functions/go/internal/uvm"
	"github.com/mnbst/thai-memo/functions/go/internal/wordclass"
)

// quizVocab は quizgen.Vocab の実装。ダミー選択肢の選定に使う語彙情報を束ねる。
//
//	freq_rank      正解の前後のランク帯を取る
//	thainlp        候補の品詞（正解と違う品詞だけ採るため）
//	wordclass      類別詞・指示詞などの機能語（複数正解になりやすい）
//
// 品詞は1語ずつタガーに引くので、同じリクエスト内の引き直しに備えて
// キャッシュする。1問あたり実際に引くのは十数語で、帯の全語は引かない。
type quizVocab struct {
	freqRank uvm.FreqRank
	// sorted は freq_rank をランク昇順に並べたもの。帯の取り出しに二分探索を使う。
	sorted []rankedWord

	mu  sync.Mutex
	pos map[string]string
}

type rankedWord struct {
	word string
	rank int
}

// newQuizVocab は freq_rank を読んで語彙情報を組み立てる。
// 読めなければ nil を返し、呼び出し側は従来どおりモデルにダミーを作らせる。
//
// 戻り値をインターフェースにしているのは、失敗時に *quizVocab の nil を
// 返すと、呼び出し側の nil 比較が偽になるため（型付き nil）。
func newQuizVocab(ctx context.Context) quizgen.Vocab {
	freqRank, err := uvm.GetFreqRank(ctx, fbapp.ProjectID())
	if err != nil || len(freqRank) == 0 {
		log.Printf("quiz_distractor_vocab_unavailable error=%v", err)
		return nil
	}
	sorted := make([]rankedWord, 0, len(freqRank))
	for word, rank := range freqRank {
		sorted = append(sorted, rankedWord{word: word, rank: rank})
	}
	sort.Slice(sorted, func(i, j int) bool { return sorted[i].rank < sorted[j].rank })
	return &quizVocab{freqRank: freqRank, sorted: sorted, pos: map[string]string{}}
}

func (v *quizVocab) Rank(word string) (int, bool) {
	rank, ok := v.freqRank[word]
	return rank, ok
}

func (v *quizVocab) WordsInRange(low, high int) []string {
	lo := sort.Search(len(v.sorted), func(i int) bool { return v.sorted[i].rank >= low })
	hi := sort.Search(len(v.sorted), func(i int) bool { return v.sorted[i].rank > high })
	out := make([]string, 0, hi-lo)
	for _, rw := range v.sorted[lo:hi] {
		out = append(out, rw.word)
	}
	return out
}

// POS は品詞ラベル（日本語）と、それが文脈の中で付いたものかを返す。
//
// 先に corpusPOS（静的コーパスの文中で付いた品詞を集計した辞書、
// scripts/build_pos_dict.py 生成）を引き、当たれば trusted=true。
// 語を単体でタガーに渡すと文脈が無いぶんぶれる（実測: ตอนนี้→接続詞、
// ที่จะ→代名詞）ので、そちらは trusted=false として扱う。
func (v *quizVocab) POS(word string) (string, bool) {
	if role, ok := corpusPOS[word]; ok {
		return role, true
	}
	v.mu.Lock()
	cached, ok := v.pos[word]
	v.mu.Unlock()
	if ok {
		return cached, false
	}
	tag, err := thainlp.POSJapanese(word)
	if err != nil {
		log.Printf("quiz_distractor_pos_failed word=%q error=%v", word, err)
		tag = ""
	}
	if tag == "その他" {
		// 品詞が決まらなかった語。正解と違う品詞だと言えないので使わない。
		tag = ""
	}
	v.mu.Lock()
	v.pos[word] = tag
	v.mu.Unlock()
	return tag, false
}

// IsFunctionWord は入れ替えても成立しやすい語かどうか。
//
// 語クラス辞書（類別詞・指示詞・代名詞・語気助詞など）に載っている語と、
// key_word から外している語（古語・方言）を落とす。前者は複数正解に
// なりやすく、後者はダミーとしても学習の役に立たない。
func (v *quizVocab) IsFunctionWord(word string) bool {
	return wordclass.Classify(word) != "" || uvm.IsExcludedTargetWord(word)
}

// dummyPronunciations はダミーの発音を NLP で作る。
//
// 選択肢の発音をモデルの理由文から切り出すのはやめる（書式が崩れると空になる）。
// 例文の発音を作っているのと同じ関数なので、表記もそろう。
// 変換できない語は入れない（呼び出し先が従来どおり理由から切り出す）。
func dummyPronunciations(words []string) map[string]string {
	out := make(map[string]string, len(words))
	for _, word := range words {
		pron, err := thainlp.ThaiToPronunciation(word)
		if err != nil {
			log.Printf("quiz_distractor_pronunciation_failed word=%q error=%v", word, err)
			continue
		}
		if pron != "" {
			out[word] = pron
		}
	}
	return out
}
