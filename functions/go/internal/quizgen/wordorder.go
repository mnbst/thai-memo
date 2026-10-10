package quizgen

import (
	"math/rand"
	"strings"
)

// WordOrderSize は並べ替える語の数。実用タイ語検定の並べ替えと同じ4つ。
const WordOrderSize = 4

// WordOrderWord は word_breakdown の語1つ（出現順）。
type WordOrderWord struct {
	Text          string
	Pronunciation string
}

// WordOrder は並び替え1問ぶん。枠の外（Prefix / Suffix）はそのまま見せる。
type WordOrder struct {
	Prefix              string
	Suffix              string
	PrefixPronunciation string
	SuffixPronunciation string
	// Answer は正しい並び。枠の語はすべて異なる（クライアントは同じ選択肢が
	// 2つある問題を不正として捨てるため）。
	Answer []string
	// Tiles / TilePronunciations は混ぜた並び（添字が対応する）。
	Tiles              []string
	TilePronunciations []string
}

// BuildWordOrder は key_word を含む連続した WordOrderSize 語を切り出して混ぜる。
//
// 次のときは作らない（ok=false）。その例文は従来の形式のまま出す。
//   - 語を並べても本文に戻らない（分解に欠落・余りがある）
//   - key_word が1語として見つからない（ๆ で2語に分かれた場合など）
//   - 例文が WordOrderSize 語に足りない
//   - 枠に入る語がタイ文字だけでない（記号・数字・ๆ 単独）
//   - 枠に同じ語が2つ以上ある
func BuildWordOrder(
	thaiText string, words []WordOrderWord, keyWord string, rnd *rand.Rand,
) (WordOrder, bool) {
	text := normalizeText(thaiText)
	var cleaned []WordOrderWord
	var texts []string
	for _, w := range words {
		t := stripSpaces(normalizeText(w.Text))
		if t == "" {
			continue
		}
		cleaned = append(cleaned, WordOrderWord{Text: t, Pronunciation: normalizeText(w.Pronunciation)})
		texts = append(texts, t)
	}
	if len(cleaned) < WordOrderSize || !rebuildsText(text, texts) {
		return WordOrder{}, false
	}

	key := -1
	for i, t := range texts {
		if MatchesKeyWord(t, keyWord) {
			key = i
			break
		}
	}
	if key < 0 {
		return WordOrder{}, false
	}

	var starts []int
	for s := max(0, key-WordOrderSize+1); s <= min(key, len(texts)-WordOrderSize); s++ {
		if usableWordOrderWindow(texts[s : s+WordOrderSize]) {
			starts = append(starts, s)
		}
	}
	if len(starts) == 0 {
		return WordOrder{}, false
	}
	s := starts[rnd.Intn(len(starts))]
	window := cleaned[s : s+WordOrderSize]

	pos, size := 0, 0
	for _, t := range texts[:s] {
		pos += len(t)
	}
	for _, w := range window {
		size += len(w.Text)
	}
	start := skipSpaces(text, offsetWithSpaces(text, 0, pos))
	end := offsetWithSpaces(text, start, size)

	out := WordOrder{
		Prefix:              strings.TrimSpace(text[:start]),
		Suffix:              strings.TrimSpace(text[end:]),
		PrefixPronunciation: joinPronunciations(cleaned[:s]),
		SuffixPronunciation: joinPronunciations(cleaned[s+WordOrderSize:]),
	}
	for _, w := range window {
		out.Answer = append(out.Answer, w.Text)
	}

	// 語はすべて異なるので、恒等置換でなければ元の並びと違う。
	order := rnd.Perm(WordOrderSize)
	for isIdentity(order) {
		order = rnd.Perm(WordOrderSize)
	}
	for _, j := range order {
		out.Tiles = append(out.Tiles, window[j].Text)
		out.TilePronunciations = append(out.TilePronunciations, window[j].Pronunciation)
	}
	return out, true
}

func usableWordOrderWindow(texts []string) bool {
	for _, t := range texts {
		if t == repeatMark || !isThaiChoiceText(t) {
			return false
		}
	}
	seen := map[string]bool{}
	for _, t := range texts {
		if seen[t] {
			return false
		}
		seen[t] = true
	}
	return true
}

func joinPronunciations(words []WordOrderWord) string {
	parts := make([]string, 0, len(words))
	for _, w := range words {
		if w.Pronunciation != "" {
			parts = append(parts, w.Pronunciation)
		}
	}
	return strings.Join(parts, " ")
}

func isIdentity(order []int) bool {
	for i, j := range order {
		if i != j {
			return false
		}
	}
	return true
}
