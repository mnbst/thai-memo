package thainlp

import (
	"compress/gzip"
	"encoding/json"
	"fmt"
	"strings"
	"sync"
	"unicode"
)

// POS タグ付けの移植。
//
// nlp.py が使うのは2経路だけ:
//
//	pos_tag(words, engine="unigram",    corpus="tud")        nlp.py:183
//	pos_tag(words, engine="perceptron", corpus="orchid_ud")  nlp.py:199

var (
	posOnce sync.Once
	posData *posTables
	posErr  error
)

type posTables struct {
	// tud は単語 -> UD タグ。見つからなければ空文字。
	tud map[string]string

	// perceptron モデル（ORCHID タグ体系）
	weights map[string]map[string]float64
	tagdict map[string]string
	classes []string

	// ORCHID の記号エスケープと UD 変換
	charToEscape map[string]string
	escapeToChar map[string]string
	toUD         map[string]string
}

func loadPOS() (*posTables, error) {
	posOnce.Do(func() { posData, posErr = doLoadPOS() })
	return posData, posErr
}

func doLoadPOS() (*posTables, error) {
	t := &posTables{}

	raw, err := dataFS.ReadFile("data/pos_tud_unigram.json")
	if err != nil {
		return nil, err
	}
	if err := json.Unmarshal(raw, &t.tud); err != nil {
		return nil, fmt.Errorf("pos_tud_unigram: %w", err)
	}

	f, err := dataFS.Open("data/pos_orchid_perceptron.json.gz")
	if err != nil {
		return nil, err
	}
	defer f.Close()
	gz, err := gzip.NewReader(f)
	if err != nil {
		return nil, err
	}
	defer gz.Close()

	var model struct {
		Weights map[string]map[string]float64 `json:"weights"`
		Tagdict map[string]string             `json:"tagdict"`
		Classes []string                      `json:"classes"`
	}
	if err := json.NewDecoder(gz).Decode(&model); err != nil {
		return nil, fmt.Errorf("pos_orchid_perceptron: %w", err)
	}
	t.weights, t.tagdict, t.classes = model.Weights, model.Tagdict, model.Classes

	raw, err = dataFS.ReadFile("data/orchid_maps.json")
	if err != nil {
		return nil, err
	}
	var maps struct {
		CharToEscape map[string]string `json:"char_to_escape"`
		EscapeToChar map[string]string `json:"escape_to_char"`
		ToUD         map[string]string `json:"to_ud"`
	}
	if err := json.Unmarshal(raw, &maps); err != nil {
		return nil, fmt.Errorf("orchid_maps: %w", err)
	}
	t.charToEscape, t.escapeToChar, t.toUD = maps.CharToEscape, maps.EscapeToChar, maps.ToUD

	return t, nil
}

// POSTag は PyThaiNLP pos_tag 相当。corpus は "tud" または "orchid_ud"。
func POSTag(word, corpus string) ([][2]string, error) {
	return POSTagSeq([]string{word}, corpus)
}

// POSTagSeq は単語列をまとめてタグ付けする。
//
// perceptron は直前2語のタグを特徴量に使うため、1語ずつ渡すのと
// まとめて渡すのでは結果が変わる。nlp.py:199 は文脈判定のため全単語を
// まとめて渡すので、そちらが本番の実挙動。
func POSTagSeq(words []string, corpus string) ([][2]string, error) {
	t, err := loadPOS()
	if err != nil {
		return nil, err
	}
	switch corpus {
	case "tud":
		return tagUnigramTUD(t, words), nil
	case "orchid_ud":
		return tagPerceptronOrchidUD(t, words)
	default:
		return nil, fmt.Errorf("thainlp: 未対応の corpus %q", corpus)
	}
}

// tagUnigramTUD は unigram.py の _find_tag 相当。未知語は空タグ。
func tagUnigramTUD(t *posTables, words []string) [][2]string {
	out := make([][2]string, 0, len(words))
	for _, w := range words {
		out = append(out, [2]string{w, t.tud[w]})
	}
	return out
}

// tagPerceptronOrchidUD は orchid.pre_process -> PerceptronTagger.tag ->
// orchid.post_process(to_ud=True) の流れ。
func tagPerceptronOrchidUD(t *posTables, words []string) ([][2]string, error) {
	// --- pre_process: 記号をエスケープ名に置き換える ------------------------
	pre := make([]string, len(words))
	for i, w := range words {
		if esc, ok := t.charToEscape[w]; ok {
			pre[i] = esc
		} else {
			pre[i] = w
		}
	}

	tagged := perceptronTag(t, pre)

	// --- post_process(to_ud=True) ------------------------------------------
	out := make([][2]string, 0, len(tagged))
	for _, wt := range tagged {
		w, tag := wt[0], wt[1]
		ud, ok := t.toUD[tag]
		if !ok {
			return nil, fmt.Errorf("thainlp: TO_UD に無いタグ %q", tag)
		}
		if orig, isEsc := t.escapeToChar[w]; isEsc {
			// Python 版は ud_exception にエスケープ名のままの w を渡す
			// （orchid.py:158-160）。同じ順序にする。
			out = append(out, [2]string{orig, udException(w, ud)})
		} else {
			out = append(out, [2]string{w, udException(w, ud)})
		}
	}
	return out, nil
}

// udException は orchid.ud_exception:122-127。
func udException(w, tag string) string {
	if w == "การ" || w == "ความ" {
		return "NOUN"
	}
	return tag
}

var (
	perceptronStart = []string{"-START-", "-START2-"}
	perceptronEnd   = []string{"-END-", "-END2-"}
)

// perceptronTag は _tag_perceptron.py:131-145。
func perceptronTag(t *posTables, tokens []string) [][2]string {
	prev, prev2 := perceptronStart[0], perceptronStart[1]

	context := make([]string, 0, len(tokens)+4)
	context = append(context, perceptronStart...)
	for _, w := range tokens {
		context = append(context, normalizeWord(w))
	}
	context = append(context, perceptronEnd...)

	out := make([][2]string, 0, len(tokens))
	for i, word := range tokens {
		tag, ok := t.tagdict[word]
		if !ok || tag == "" {
			// Python は `if not tag:` なので空文字も未登録扱いになる。
			feats := perceptronFeatures(i, word, context, prev, prev2)
			tag = perceptronPredict(t, feats)
		}
		out = append(out, [2]string{word, tag})
		prev2 = prev
		prev = tag
	}
	return out
}

// normalizeWord は _tag_perceptron.py:216-233。
func normalizeWord(word string) string {
	r := []rune(word)
	if len(r) == 0 {
		return word
	}
	if strings.Contains(word, "-") && r[0] != '-' {
		return "!HYPHEN"
	}
	if len(r) == 4 && allDigits(r) {
		return "!YEAR"
	}
	if unicode.IsDigit(r[0]) {
		return "!DIGITS"
	}
	return strings.ToLower(word)
}

// allDigits は Python の str.isdigit() 相当。Unicode の数字全般を含む。
func allDigits(r []rune) bool {
	for _, c := range r {
		if !unicode.IsDigit(c) {
			return false
		}
	}
	return len(r) > 0
}

// lastRunes は Python の word[-3:] 相当（rune 単位）。
func lastRunes(s string, n int) string {
	r := []rune(s)
	if len(r) <= n {
		return s
	}
	return string(r[len(r)-n:])
}

// firstRune は Python の word[0] 相当。
func firstRune(s string) string {
	for _, c := range s {
		return string(c)
	}
	return ""
}

// perceptronFeatures は _tag_perceptron.py:235-266。
// 特徴量名は Python と1バイトも違ってはならない（重みの引き方が変わるため）。
func perceptronFeatures(i int, word string, context []string, prev, prev2 string) map[string]float64 {
	feats := map[string]float64{}
	add := func(name string, args ...string) {
		key := name
		if len(args) > 0 {
			key = name + " " + strings.Join(args, " ")
		}
		feats[key]++
	}

	i += len(perceptronStart)
	add("bias")
	add("i suffix", lastRunes(word, 3))
	add("i pref1", firstRune(word))
	add("i-1 tag", prev)
	add("i-2 tag", prev2)
	add("i tag+i-2 tag", prev, prev2)
	add("i word", context[i])
	add("i-1 tag+i word", prev, context[i])
	add("i-1 word", context[i-1])
	add("i-1 suffix", lastRunes(context[i-1], 3))
	add("i-2 word", context[i-2])
	add("i+1 word", context[i+1])
	add("i+1 suffix", lastRunes(context[i+1], 3))
	add("i+2 word", context[i+2])
	return feats
}

// perceptronPredict は AveragedPerceptron.predict:48-61。
//
// Python は max(classes, key=lambda l: (scores[l], l)) なので、
// 同点のときは辞書順で大きいラベルが勝つ。Go でも同じ規則にする。
func perceptronPredict(t *posTables, feats map[string]float64) string {
	scores := make(map[string]float64, len(t.classes))
	for feat, value := range feats {
		if value == 0 {
			continue
		}
		weights, ok := t.weights[feat]
		if !ok {
			continue
		}
		for label, w := range weights {
			scores[label] += value * w
		}
	}

	best, bestScore := "", 0.0
	for i, label := range t.classes {
		s := scores[label] // 未出現は 0
		if i == 0 || s > bestScore || (s == bestScore && label > best) {
			best, bestScore = label, s
		}
	}
	return best
}
