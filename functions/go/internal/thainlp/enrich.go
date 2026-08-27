package thainlp

import (
	"log"

	"github.com/mnbst/thai-memo/functions/go/internal/lang"
)

// posLabelEN は品詞ラベルの英訳。nlp.py:_POS_LABEL_EN:57。
var posLabelEN = map[string]string{
	"名詞":   "noun",
	"動詞":   "verb",
	"形容詞":  "adjective",
	"副詞":   "adverb",
	"代名詞":  "pronoun",
	"限定詞":  "determiner",
	"前置詞":  "preposition",
	"助動詞":  "auxiliary",
	"接続詞":  "conjunction",
	"助詞":   "particle",
	"感嘆詞":  "interjection",
	"数詞":   "numeral",
	"固有名詞": "proper noun",
	"句読点":  "punctuation",
	"類別詞":  "classifier",
	"否定詞":  "negator",
	"その他":  "other",
}

// LocalizePOS は品詞ラベルを訳文の言語に合わせる。未知のラベルはそのまま返す。
//
// Python 版は "ja" 以外を全て英訳に倒すが、ここは lang.Lang（ja/en）で受ける。
// lang はハンドラ側で正規化済みなので実入力に差は無い。
func LocalizePOS(label string, l lang.Lang) string {
	if l != lang.EN {
		return label
	}
	if v, ok := posLabelEN[label]; ok {
		return v
	}
	return label
}

// EnrichWord は 1 語ぶんの NLP 結果。
type EnrichWord struct {
	Syllables       []string
	Pronunciation   string
	GrammaticalRole string
}

// Enrich は語のリストに音節分割・発音・品詞を付ける。
// 戻り値は words と同じ長さで、文全体の発音と、発音を1語でも作れたかを返す。
//
// 各処理は独立していて、一部が失敗しても他は続ける。失敗はログに出すだけで
// 呼び出し側には返さない（NLP の失敗で生成全体を落とさない）。
// nlp.py:enrich_with_nlp:243 の移植。
func Enrich(words []string, l lang.Lang) ([]EnrichWord, string, bool) {
	out := make([]EnrichWord, len(words))

	// 品詞は辞書 → unigram → perceptron の順に段階的に判定するので一括で引く。
	posMap, err := TagWords(words)
	if err != nil {
		log.Printf("NLP POS failed: %v", err)
		posMap = map[int]string{}
	}

	var pronunciations []string
	for i, word := range words {
		if syllables, err := SegmentSyllables(word); err != nil {
			log.Printf("NLP syllables failed for '%s': %v", word, err)
		} else {
			out[i].Syllables = syllables
		}

		if pron, err := ThaiToPronunciation(word); err != nil {
			log.Printf("NLP pronunciation failed for '%s': %v", word, err)
		} else {
			out[i].Pronunciation = pron
			pronunciations = append(pronunciations, pron)
		}

		// 空の語には品詞が無い。word_breakdown に空エントリが混じるのは
		// LLM 出力の崩れで、タガーに渡しても意味のあるタグは付かない。
		//
		// Python 側はここでタガーが例外を投げ（string index out of range）、
		// その文全体の一括タグ付けが巻き添えで落ちて 1 語ずつの引き直しに
		// 縮退したうえで「その他」になる。Go のタガーは落ちずに前後の文脈から
		// 名詞や動詞を付けてしまうので、空の語だけ明示的に外す。
		// 出力は Python と同じ「その他」で、周りの語の文脈は壊さない。
		if word == "" {
			out[i].GrammaticalRole = LocalizePOS("その他", l)
			continue
		}

		if tag, ok := posMap[i]; ok {
			out[i].GrammaticalRole = LocalizePOS(tag, l)
			continue
		}
		// 一括タグ付けで埋まらなかった語だけ個別に引き直す。
		//
		// TagWords は最終段の perceptron で全語を埋めるので、ここへ来るのは
		// タガー自体が失敗したときだけ。実データでは通らない。
		tag, err := POSJapanese(word)
		if err != nil {
			log.Printf("NLP POS (fallback) failed for '%s': %v", word, err)
			continue
		}
		out[i].GrammaticalRole = LocalizePOS(tag, l)
	}

	// 語ごとの発音をスペースで結合して文全体の発音にする。
	//
	// 第3戻り値は「1語でも変換できたか」。結合結果が空かどうかではない。
	// 空文字の語だけの word_breakdown では結合結果も空になるが、Python 側は
	// リストが空でなければ代入する（nlp.py:299 の if word_pronunciations）ので、
	// 既存の発音は空で上書きされる。判定を結合結果に変えると、そこだけ挙動が
	// 変わって差分テストに出ない食い違いになる。
	return out, joinSpace(pronunciations), len(pronunciations) > 0
}

func joinSpace(parts []string) string {
	result := ""
	for i, p := range parts {
		if i > 0 {
			result += " "
		}
		result += p
	}
	return result
}
