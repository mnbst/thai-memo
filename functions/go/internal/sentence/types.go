package sentence

import (
	"encoding/json"

	"github.com/mnbst/thai-memo/functions/go/internal/wordgap"
)

// Word は word_breakdown の 1 件。
//
// Syllables / Pronunciation / GrammaticalRole は NLP 後処理で埋まる。
// Notes は target_notes から展開する（対象外の語では空文字）。
type Word struct {
	Word            string   `json:"word" firestore:"word"`
	Meaning         string   `json:"meaning" firestore:"meaning"`
	Notes           string   `json:"notes" firestore:"notes"`
	Syllables       []string `json:"syllables,omitempty" firestore:"syllables,omitempty"`
	Pronunciation   string   `json:"pronunciation,omitempty" firestore:"pronunciation,omitempty"`
	GrammaticalRole string   `json:"grammatical_role,omitempty" firestore:"grammatical_role,omitempty"`
}

// TargetNote は LLM が返すターゲット語の補足。
// word_breakdown へ展開したあとは保存も送信もしない。
type TargetNote struct {
	Word string `json:"word"`
	Note string `json:"note"`
}

// Sentence は生成された例文 1 件。
//
// LLM のレスポンス（RESPONSE_JSON_SCHEMA 準拠）をそのまま受け、
// 後処理で Pronunciation と各語の NLP 情報が足される。
type Sentence struct {
	ThaiText            string         `json:"thai_text"`
	JapaneseTranslation string         `json:"japanese_translation"`
	Pronunciation       string         `json:"pronunciation,omitempty"`
	WordBreakdown       []Word         `json:"word_breakdown"`
	TargetNotes         []TargetNote   `json:"target_notes,omitempty"`
	Context             map[string]any `json:"context,omitempty"`
	TargetWords         []string       `json:"target_words,omitempty"`
	// KeyWord は free 例文バンク（GCS）の項目だけが持つ。LLM 生成では空。
	KeyWord string `json:"key_word,omitempty"`
	// GenerationTier は "premium" / "free"。生成後にハンドラが付ける。
	GenerationTier string `json:"generation_tier,omitempty"`
}

// FromMap は LLM のレスポンス map を Sentence に読み込む。
//
// Python 版は dict をそのまま持ち回すが、レスポンスに載せるフィールドは
// ハンドラ側で明示的に組み直しているので（sentence_handlers.py）、
// 型を付けても外へ出る内容は変わらない。
func FromMap(raw map[string]any) (*Sentence, error) {
	data, err := json.Marshal(raw)
	if err != nil {
		return nil, err
	}
	var s Sentence
	if err := json.Unmarshal(data, &s); err != nil {
		return nil, err
	}
	return &s, nil
}

// BreakdownWords は word_breakdown の語だけを取り出す。
func (s *Sentence) BreakdownWords() []string {
	words := make([]string, len(s.WordBreakdown))
	for i, w := range s.WordBreakdown {
		words[i] = w.Word
	}
	return words
}

// gapWords は wordgap が扱う形へ落とす。
func (s *Sentence) gapWords() []wordgap.Word {
	words := make([]wordgap.Word, len(s.WordBreakdown))
	for i, w := range s.WordBreakdown {
		words[i] = wordgap.Word{Word: w.Word, Meaning: w.Meaning}
	}
	return words
}

// remarshal は map を JSON 経由で構造体へ移す。
func remarshal(raw map[string]any, out any) error {
	data, err := json.Marshal(raw)
	if err != nil {
		return err
	}
	return json.Unmarshal(data, out)
}
