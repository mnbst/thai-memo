package sentence

import (
	"strings"

	"cloud.google.com/go/firestore"
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

// BuildSentenceDoc は users/{uid}/sentences へ書き込む内容を組み立てる
// （sentence_handlers.py:_build_sentence_data:252）。
//
// word_breakdown は nil のときも空配列で書く（Python の .get(..., []) 相当）。
//
// Python との差: Python は LLM が返した dict をそのまま保存するので、
// notes が無い語ではキーごと欠ける。Go は構造体なので必ず notes を書く
// （値は空文字）。読み手は欠損も空文字として扱うので実害は無く、
// ドキュメントの形が揃うぶんこちらを採る。
func (s *Sentence) BuildSentenceDoc(keyWord string, usePremiumSpec bool) map[string]any {
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
		"key_word":               keyWord,
		"key_word_pronunciation": s.KeyWordPronunciation(keyWord),
		"key_word_meaning":       s.KeyWordMeaning(keyWord),
		"generation_tier":        GenerationTier(usePremiumSpec),
	}
}
