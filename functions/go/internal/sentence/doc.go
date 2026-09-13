package sentence

import (
	"strings"

	"cloud.google.com/go/firestore"

	"github.com/mnbst/thai-memo/functions/go/internal/lang"
)

// matchKeyWord は key_word と word_breakdown の語を照合する
// （sentence_handlers.py:_match_key_word:236）。
//
// ๆ（繰り返し記号）の有無は同一視する。LLM は「คนๆ」を語として返すことも
// 「คน」と返すこともあり、どちらでも同じ語として扱いたい。
func matchKeyWord(wordText, keyWord string) bool {
	w := strings.TrimSpace(wordText)
	k := strings.TrimSpace(keyWord)
	return w == k || w == k+"ๆ" || w+"ๆ" == k
}

// KeyWordPronunciation は key_word の発音を word_breakdown から引く。
// 見つからなければ空文字。
func (s *Sentence) KeyWordPronunciation(keyWord string) string {
	for _, w := range s.WordBreakdown {
		if matchKeyWord(w.Word, keyWord) {
			return strings.TrimSpace(w.Pronunciation)
		}
	}
	return ""
}

// KeyWordMeaning は key_word の意味を word_breakdown から引く。
func (s *Sentence) KeyWordMeaning(keyWord string) string {
	for _, w := range s.WordBreakdown {
		if matchKeyWord(w.Word, keyWord) {
			return strings.TrimSpace(w.Meaning)
		}
	}
	return ""
}

// DocMeta は保存する例文ドキュメントに添える、文そのものには入らない情報。
//
// 引数を並べず構造体にしているのは、あとから足すのがこの種の付随情報だけで、
// 呼び出し側がどれを渡しているか名前で読めるようにするため。
type DocMeta struct {
	KeyWord        string
	UsePremiumSpec bool
	// Lang は訳文の言語。どちらの言語のプールへ回すかをここで決める。
	// 例文本体には言語が書かれておらず、あとから users の設定を見ても、
	// 生成後に設定を変えた人のぶんが取り違わる。
	Lang lang.Lang
	// FromCache はバンク（FreeBank / CorpusBank）から出した文かどうか。
	// 真なら品質監査もプール追加も対象外にする（既にバンクにある文なので
	// 判定し直す意味が無く、プールへ入れ直すと同じ文が二重に増える）。
	FromCache bool
}

// BuildSentenceDoc は users/{uid}/sentences へ書き込む内容を組み立てる
// （sentence_handlers.py:_build_sentence_data:252）。
//
// word_breakdown は nil のときも空配列で書く（Python の .get(..., []) 相当）。
//
// Python との差: Python は LLM が返した dict をそのまま保存するので、
// notes が無い語ではキーごと欠ける。Go は構造体なので必ず notes を書く
// （値は空文字）。読み手は欠損も空文字として扱うので実害は無く、
// ドキュメントの形が揃うぶんこちらを採る。
func (s *Sentence) BuildSentenceDoc(m DocMeta) map[string]any {
	breakdown := s.WordBreakdown
	if breakdown == nil {
		breakdown = []Word{}
	}
	context := s.Context
	if context == nil {
		context = map[string]any{}
	}
	return map[string]any{
		"thai_text":              s.ThaiText,
		"pronunciation":          s.Pronunciation,
		"japanese_translation":   s.JapaneseTranslation,
		"word_breakdown":         breakdown,
		"context":                context,
		"created_at":             firestore.ServerTimestamp,
		"key_word":               m.KeyWord,
		"key_word_pronunciation": s.KeyWordPronunciation(m.KeyWord),
		"key_word_meaning":       s.KeyWordMeaning(m.KeyWord),
		"generation_tier":        GenerationTier(m.UsePremiumSpec),
		"lang":                   string(m.Lang),
		"from_cache":             m.FromCache,
	}
}
