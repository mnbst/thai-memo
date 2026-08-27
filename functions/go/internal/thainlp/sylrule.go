package thainlp

import (
	"encoding/json"
	"fmt"
	"sync"

	"github.com/dlclark/regexp2"
)

// th2ipa の音韻規則テーブル（tltk/th2ipa.py:read_sylpattern:1225）。
//
// データは export_tltk_data.py が Python 側から書き出す。stable / AK は
// コード中にベタ書きされた大きなタイ文字テーブルなので、書き写さず機械的に出す。

// PronRule は sylrule.lts 1行ぶんの規則。
type PronRule struct {
	// Pattern は文字クラスを展開済みのタイ文字パターン。
	Pattern string
	// Phones は対応する音素列の候補。1つのパターンに複数付くことがある。
	Phones []string

	re *regexp2.Regexp
}

// Match は Python の re.match（先頭一致）相当。
func (r *PronRule) Match(text []rune) (*regexp2.Match, error) {
	return r.re.FindRunesMatch(text)
}

// SylRules は th2ipa の規則一式。
type SylRules struct {
	// Pron は PRON。**挿入順が意味を持つ**ので配列で保持する。
	// sylparse の `for f in PRON:` がこの順に走査し、PRONUN への
	// 追加順が後段の SelectPhones の候補順を決める。
	Pron []*PronRule

	// Stable は子音 -> 音素の対応表（頭子音 X 系 / 末子音 Y 系）。
	Stable map[string]map[string]string
	// AK は連続子音の組み合わせ表。
	AK map[string]string
	// EngAbbr は英字1文字のタイ語読み。
	EngAbbr []string
}

var (
	sylRulesOnce sync.Once
	sylRules     *SylRules
	sylRulesErr  error
)

// LoadSylRules は規則テーブルを一度だけ読み込む。
func LoadSylRules() (*SylRules, error) {
	sylRulesOnce.Do(func() { sylRules, sylRulesErr = loadSylRules() })
	return sylRules, sylRulesErr
}

func loadSylRules() (*SylRules, error) {
	raw, err := dataFS.ReadFile("data/sylrule_pron.json")
	if err != nil {
		return nil, err
	}
	var f struct {
		Pron    [][2]json.RawMessage         `json:"pron"`
		Stable  map[string]map[string]string `json:"stable"`
		AK      map[string]string            `json:"ak"`
		EngAbbr []string                     `json:"eng_abbr"`
	}
	if err := json.Unmarshal(raw, &f); err != nil {
		return nil, fmt.Errorf("sylrule_pron.json: %w", err)
	}

	s := &SylRules{Stable: f.Stable, AK: f.AK, EngAbbr: f.EngAbbr}
	for i, pair := range f.Pron {
		var pattern string
		var phones []string
		if err := json.Unmarshal(pair[0], &pattern); err != nil {
			return nil, fmt.Errorf("pron[%d] pattern: %w", i, err)
		}
		if err := json.Unmarshal(pair[1], &phones); err != nil {
			return nil, fmt.Errorf("pron[%d] phones: %w", i, err)
		}
		// Python の re.match は先頭一致。regexp2 は Python と同じ
		// バックトラック方式なので交替順・貪欲量化の意味論を保てる。
		re, err := regexp2.Compile(`\A(?:`+pattern+`)`, regexp2.None)
		if err != nil {
			return nil, fmt.Errorf("pron[%d] %q のコンパイルに失敗: %w", i, pattern, err)
		}
		s.Pron = append(s.Pron, &PronRule{Pattern: pattern, Phones: phones, re: re})
	}
	return s, nil
}
