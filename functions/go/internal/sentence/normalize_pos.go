package sentence

import (
	"github.com/mnbst/thai-memo/functions/go/internal/lang"
	"github.com/mnbst/thai-memo/functions/go/internal/thainlp"
)

// NormalizePOS は word_breakdown のうちタガーに無いラベル（文末詞・受益標識 等）を、
// タガーの品詞に置き換える。labels はそのプールのラベルの言語（プールは ja、free_pool_en だけ en）。
// 標準のラベルはそのまま残す（プール確認で人や Codex が直した品詞を戻さない）。置き換えた語数を返す。
func NormalizePOS(s *Sentence, labels lang.Lang) (int, error) {
	var bad []int
	words := make([]string, len(s.WordBreakdown))
	for i, w := range s.WordBreakdown {
		words[i] = w.Word
		if !thainlp.IsPOSLabel(w.GrammaticalRole) {
			bad = append(bad, i)
		}
	}
	if len(bad) == 0 {
		return 0, nil
	}
	tags, err := thainlp.TagWords(words)
	if err != nil {
		return 0, err
	}
	for _, i := range bad {
		tag := tags[i]
		if tag == "" || words[i] == "" {
			tag = "その他"
		}
		s.WordBreakdown[i].GrammaticalRole = thainlp.LocalizePOS(tag, labels)
	}
	return len(bad), nil
}
