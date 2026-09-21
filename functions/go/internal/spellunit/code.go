// Package spellunit は綴り4択（spelling_choice）のための音節部品（unit）を扱う。
//
// 単語ごとの P（uvm）とは別に、母音・頭子音・末子音・声調という
// **部品ごと** の正誤を貯める。部品は全部で 80 種ほどの閉じた集合なので、
// 9,300 語ある単語より 100 倍速く埋まり、未知語にも外挿が効く。
//
// このパッケージのデータは uvm とは別の users/{uid}/units に置き、
// estimated_vocab には**絶対に混ぜない**（測る軸と出題を切り替える軸を
// 分けておかないと、generate_quiz.go の quizKeyWordFilter と同じ
// 自己参照ループになる）。
package spellunit

import (
	"sort"
	"strings"
	"sync"
	"unicode"

	"github.com/mnbst/thai-memo/functions/go/internal/thainlp"
)

// Dim は音節の次元。
type Dim uint8

const (
	DimOnset Dim = iota // 頭子音
	DimVowel            // 母音
	DimCoda             // 末子音
	DimTone             // 声調
)

// Dims は次元の全部。
var Dims = []Dim{DimOnset, DimVowel, DimCoda, DimTone}

func (d Dim) String() string {
	switch d {
	case DimOnset:
		return "onset"
	case DimVowel:
		return "vowel"
	case DimCoda:
		return "coda"
	default:
		return "tone"
	}
}

// Code は sylform_var.json のキー（音節形コード）を次元ごとに分けたもの。
// 例: "?OOk1" -> {Onset:"?", Vowel:"OO", Coda:"k", Tone:"1"}。
type Code struct {
	Onset, Vowel, Coda, Tone string
}

// String はコード表記に戻す。
func (c Code) String() string { return c.Onset + c.Vowel + c.Coda + c.Tone }

// At は次元の値。
func (c Code) At(d Dim) string {
	switch d {
	case DimOnset:
		return c.Onset
	case DimVowel:
		return c.Vowel
	case DimCoda:
		return c.Coda
	default:
		return c.Tone
	}
}

// With は1次元だけ差し替えたコードを返す。
func (c Code) With(d Dim, value string) Code {
	switch d {
	case DimOnset:
		c.Onset = value
	case DimVowel:
		c.Vowel = value
	case DimCoda:
		c.Coda = value
	default:
		c.Tone = value
	}
	return c
}

// UnitID は Firestore の users/{uid}/units のドキュメントID。
// 例: "vowel:OO"。末子音なしは "coda:-"。
func UnitID(d Dim, value string) string {
	if value == "" {
		value = "-"
	}
	return d.String() + ":" + value
}

// vowels は sylform_var のコードに現れる母音（22種）。長い順に当てるので
// 並びは ParseCode 側でソートする。
var vowels = []string{
	"@@", "O", "OO", "U", "UU", "UUa", "a", "aa", "e", "e-", "ee",
	"i", "ia", "ii", "iia", "o", "oo", "u", "uu", "uua", "x", "xx",
}

// codas は末子音（10種、空＝末子音なし）。
var codas = []string{"N", "j", "k", "l", "m", "n", "p", "t", "w", ""}

// tones は声調（5種）。
var tones = []string{"0", "1", "2", "3", "4"}

var (
	sortedVowels = byLenDesc(vowels)
	sortedCodas  = byLenDesc(codas)
)

func byLenDesc(src []string) []string {
	out := append([]string(nil), src...)
	sort.Slice(out, func(i, j int) bool { return len(out[i]) > len(out[j]) })
	return out
}

// ParseCode は音節形コードを分解する。
//
// 複音節（"'" 区切り）、前音節が融合したもの（"^"）、TLTK が混ぜる
// バックスラッシュ入りは扱わない（単音節だけを対象にする）。
func ParseCode(code string) (Code, bool) {
	if code == "" || strings.ContainsAny(code, `'^\`) {
		return Code{}, false
	}
	tone := code[len(code)-1:]
	if !contains(tones, tone) {
		return Code{}, false
	}
	body := code[:len(code)-1]

	coda := ""
	for _, c := range sortedCodas {
		if c != "" && strings.HasSuffix(body, c) {
			coda = c
			break
		}
	}
	rest := body[:len(body)-len(coda)]

	for _, v := range sortedVowels {
		if !strings.HasSuffix(rest, v) {
			continue
		}
		onset := rest[:len(rest)-len(v)]
		if onset == "" {
			return Code{}, false
		}
		return Code{Onset: onset, Vowel: v, Coda: coda, Tone: tone}, true
	}
	return Code{}, false
}

func contains(values []string, target string) bool {
	for _, v := range values {
		if v == target {
			return true
		}
	}
	return false
}

// Index は音節形コードと綴りの対応表。
type Index struct {
	// spellings はコード -> 実在する綴り（非語を含む）。
	spellings map[Code][]string
	// codes は綴り -> コード。複数のコードに当たる綴りは持たない
	// （どの部品を測ったのか決められないため）。
	codes map[string]Code
	// realWord は BEST.dict の見出し語。ダミーはここに無い綴りだけを使う。
	realWord map[string]bool
	// onsets は実際に現れた頭子音の一覧。
	onsets []string
}

var (
	indexOnce sync.Once
	index     *Index
	indexErr  error
)

// LoadIndex は対応表を一度だけ組む。
func LoadIndex() (*Index, error) {
	indexOnce.Do(func() { index, indexErr = loadIndex() })
	return index, indexErr
}

func loadIndex() (*Index, error) {
	data, err := thainlp.Load()
	if err != nil {
		return nil, err
	}

	ix := &Index{
		spellings: map[Code][]string{},
		codes:     map[string]Code{},
		realWord:  data.Dict,
	}
	ambiguous := map[string]bool{}
	onsets := map[string]bool{}

	for rawCode, rawForms := range data.SylVar {
		code, ok := ParseCode(rawCode)
		if !ok {
			continue
		}
		forms, ok := rawForms.([]any)
		if !ok {
			continue
		}
		onsets[code.Onset] = true
		for _, raw := range forms {
			form, ok := raw.(string)
			if !ok || form == "" {
				continue
			}
			ix.spellings[code] = append(ix.spellings[code], form)
			if existing, seen := ix.codes[form]; seen && existing != code {
				ambiguous[form] = true
				continue
			}
			ix.codes[form] = code
		}
	}
	for form := range ambiguous {
		delete(ix.codes, form)
	}
	for _, forms := range ix.spellings {
		sort.Strings(forms)
	}
	for onset := range onsets {
		ix.onsets = append(ix.onsets, onset)
	}
	sort.Strings(ix.onsets)
	return ix, nil
}

// Lookup は綴りから音節形コードを引く。単音節で、読みが一意に決まる綴りだけ。
func (ix *Index) Lookup(word string) (Code, bool) {
	code, ok := ix.codes[strings.TrimSpace(word)]
	return code, ok
}

// values は次元の取りうる値。
func (ix *Index) values(d Dim) []string {
	switch d {
	case DimOnset:
		return ix.onsets
	case DimVowel:
		return vowels
	case DimCoda:
		return codas
	default:
		return tones
	}
}

// displayLen はタイ文字の見た目の長さ。結合記号（上下に付く母音・声調記号）は
// 幅を持たないので数えない。数えてしまうと長さがそのまま答えの手がかりになる。
func displayLen(s string) int {
	n := 0
	for _, r := range s {
		if !unicode.Is(unicode.Mn, r) {
			n++
		}
	}
	return n
}
