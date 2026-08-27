package thainlp

import (
	"container/heap"
	"regexp"
	"strings"
	"sync"

	"github.com/dlclark/regexp2"
)

// 単語分割（newmm）と音節分割の移植。
//
// PyThaiNLP:
//
//	word_tokenize(text)                      -> newmm + rejoin_formatted_num
//	subword_tokenize(word, engine="dict")    -> word_tokenize してから
//	                                            音節辞書で再度 word_tokenize
//
// Python の文字列はコードポイント単位なので、位置計算はすべて rune で行う。
// バイト単位にすると TCC の位置集合がずれて分割結果が変わる。

// ---------------------------------------------------------------------------
// Thai Character Cluster (tcc_p.py)
// ---------------------------------------------------------------------------

// tccPatterns は tcc_p.py:_RE_TCC。k/c/t/d の置換を展開済み。
// 3つの規則が先読み (?=[เ-ไก-ฮ]|$) を使うため、Go 標準の regexp(RE2) では
// 表現できない。Python と同じバックトラック方式の regexp2 を使う。
var tccPatterns = buildTCCPatterns()

func buildTCCPatterns() string {
	raw := []string{
		"เc็ck",
		"เcctาะk",
		"เccีtยะk",
		"เccีtย(?=[เ-ไก-ฮ]|$)k",
		"เcc็ck",
		"เcิc์ck",
		"เcิtck",
		"เcีtยะ?k",
		"เcืtอะ?k",
		"เc[ิีุู]tย(?=[เ-ไก-ฮ]|$)k",
		"เctา?ะ?k",
		"cัtวะk",
		"c[ัื]tc[ุิะ]?k",
		"c[ิุู]์",
		"c[ะ-ู]tk",
		"cรรc์",
		"c็",
		"ct[ะาำ]?k",
		"ck",
		"แc็c",
		"แcc์",
		"แctะ",
		"แcc็c",
		"แccc์",
		"โctะ",
		"[เ-ไ]ct",
		"ก็",
		"อึ",
		"หึ",
	}
	// tcc_p.py と同じ順序で置換する。k が c を含むので k を先に展開する。
	rep := strings.NewReplacer()
	_ = rep
	out := make([]string, 0, len(raw))
	for _, p := range raw {
		s := strings.ReplaceAll(p, "k", "(cc?[dิ]?[์])?")
		s = strings.ReplaceAll(s, "c", "[ก-ฮ]")
		s = strings.ReplaceAll(s, "t", "[่-๋]?")
		// d は "อูอุ" から "อ" を除いたもの = "ูุ"
		s = strings.ReplaceAll(s, "d", "ูุ")
		out = append(out, s)
	}
	return strings.Join(out, "|")
}

var (
	tccOnce sync.Once
	tccRe   *regexp2.Regexp
	tccErr  error
)

func tccRegexp() (*regexp2.Regexp, error) {
	tccOnce.Do(func() {
		// Python の re.match は先頭一致なので \G(?:...) 相当にする。
		tccRe, tccErr = regexp2.Compile(`\A(?:`+tccPatterns+`)`, regexp2.None)
	})
	return tccRe, tccErr
}

// tccPos は tcc_p.py:tcc_pos。TCC 境界となる終了位置の集合（rune 単位）。
func tccPos(text []rune) (map[int]bool, error) {
	pset := map[int]bool{}
	if len(text) == 0 {
		return pset, nil
	}
	re, err := tccRegexp()
	if err != nil {
		return nil, err
	}

	p := 0
	for p < len(text) {
		n := 1
		m, err := re.FindRunesMatch(text[p:])
		if err != nil {
			return nil, err
		}
		if m != nil {
			n = m.Length
		}
		if n <= 0 {
			n = 1
		}
		p += n
		pset[p] = true
	}
	return pset, nil
}

// ---------------------------------------------------------------------------
// Trie (pythainlp/util/trie.py)
// ---------------------------------------------------------------------------

type trieNode struct {
	end      bool
	children map[rune]*trieNode
}

// Trie は PyThaiNLP の Trie 相当。
type Trie struct{ root *trieNode }

// NewTrie は語のリストから Trie を作る。前後の空白は落とす（Trie.add と同じ）。
func NewTrie(words []string) *Trie {
	t := &Trie{root: &trieNode{children: map[rune]*trieNode{}}}
	for _, w := range words {
		t.add(strings.TrimSpace(w))
	}
	return t
}

func (t *Trie) add(word string) {
	if word == "" {
		return
	}
	cur := t.root
	for _, ch := range word {
		child, ok := cur.children[ch]
		if !ok {
			child = &trieNode{children: map[rune]*trieNode{}}
			cur.children[ch] = child
		}
		cur = child
	}
	cur.end = true
}

// prefixesLen は text の接頭辞として辞書に載っている語の長さ（rune 数）を
// 短い順に返す。Python の Trie.prefixes と同じ順序。
func (t *Trie) prefixesLen(text []rune) []int {
	var res []int
	cur := t.root
	for i, ch := range text {
		child, ok := cur.children[ch]
		if !ok {
			break
		}
		if child.end {
			res = append(res, i+1)
		}
		cur = child
	}
	return res
}

// ---------------------------------------------------------------------------
// newmm (newmm.py)
// ---------------------------------------------------------------------------

var (
	// newmm.py:_PAT_NONTHAI。Python の (?x) 付きパターンと同じ内容。
	patNonThai = regexp.MustCompile(`^(?:[-a-zA-Z]+|\d+([,.]\d+)*|[ \t]+|\r?\n|[^\x{0E00}-\x{0E7F} \t\r\n]+)`)
	// newmm.py:_PAT_THAI_TWOCHARS
	patThaiTwoChars = regexp.MustCompile(`^[\x{0E01}-\x{0E2E}]{0,2}$`)
)

const maxGraphSize = 50

// intHeap は Python の heapq と同じ最小ヒープ。
type intHeap []int

func (h intHeap) Len() int           { return len(h) }
func (h intHeap) Less(i, j int) bool { return h[i] < h[j] }
func (h intHeap) Swap(i, j int)      { h[i], h[j] = h[j], h[i] }
func (h *intHeap) Push(x any)        { *h = append(*h, x.(int)) }
func (h *intHeap) Pop() any          { o := *h; n := len(o); v := o[n-1]; *h = o[:n-1]; return v }
func (h intHeap) contains(v int) bool { // Python の `x not in pos_list` は線形探索
	for _, x := range h {
		if x == v {
			return true
		}
	}
	return false
}

// bfsFirstPath は newmm.py:_bfs_paths_graph の最初の1本。
func bfsFirstPath(graph map[int][]int, start, goal int) []int {
	type item struct {
		vertex int
		path   []int
	}
	queue := []item{{start, []int{start}}}
	for len(queue) > 0 {
		cur := queue[0]
		queue = queue[1:]
		for _, pos := range graph[cur.vertex] {
			path := append(append([]int{}, cur.path...), pos)
			if pos == goal {
				return path
			}
			queue = append(queue, item{pos, path})
		}
	}
	return nil
}

// onecut は newmm.py:_onecut。
func onecut(text []rune, dict *Trie) ([]string, error) {
	var out []string
	graph := map[int][]int{}
	graphSize := 0

	validPoss, err := tccPos(text)
	if err != nil {
		return nil, err
	}

	lenText := len(text)
	posList := &intHeap{0}
	endPos := 0

	for (*posList)[0] < lenText {
		beginPos := heap.Pop(posList).(int)

		for _, l := range dict.prefixesLen(text[beginPos:]) {
			cand := beginPos + l
			if !validPoss[cand] {
				continue
			}
			graph[beginPos] = append(graph[beginPos], cand)
			graphSize++
			if !posList.contains(cand) {
				heap.Push(posList, cand)
			}
			if graphSize > maxGraphSize {
				break
			}
		}

		switch len(*posList) {
		case 1:
			path := bfsFirstPath(graph, endPos, (*posList)[0])
			graphSize = 0
			for _, pos := range path[1:] {
				out = append(out, string(text[endPos:pos]))
				endPos = pos
			}
		case 0:
			rest := string(text[beginPos:])
			if m := patNonThai.FindString(rest); m != "" {
				endPos = beginPos + len([]rune(m))
			} else {
				found := false
				for pos := beginPos + 1; pos < lenText; pos++ {
					if !validPoss[pos] {
						continue
					}
					prefix := text[pos:]
					hasWord := false
					for _, l := range dict.prefixesLen(prefix) {
						if validPoss[pos+l] && !patThaiTwoChars.MatchString(string(prefix[:l])) {
							hasWord = true
							break
						}
					}
					if hasWord {
						endPos = pos
						found = true
						break
					}
					if patNonThai.FindString(string(prefix)) != "" {
						endPos = pos
						found = true
						break
					}
				}
				if !found {
					endPos = lenText
				}
			}
			graph[beginPos] = append(graph[beginPos], endPos)
			graphSize++
			out = append(out, string(text[beginPos:endPos]))
			heap.Push(posList, endPos)
		}
	}
	return out, nil
}

// ---------------------------------------------------------------------------
// 後処理 (_utils.py:rejoin_formatted_num)
// ---------------------------------------------------------------------------

var patDigitsWithSeparator = regexp.MustCompile(`(\d+[.,:])+\d+`)

func rejoinFormattedNum(segments []string) []string {
	original := strings.Join(segments, "")
	// Python の finditer と同じく rune 位置で扱う。
	origRunes := []rune(original)
	byteToRune := make(map[int]int, len(origRunes)+1)
	{
		r := 0
		for b := range original {
			byteToRune[b] = r
			r++
		}
		byteToRune[len(original)] = r
	}
	locs := patDigitsWithSeparator.FindAllStringIndex(original, -1)
	type span struct{ start, end int }
	spans := make([]span, 0, len(locs))
	for _, l := range locs {
		spans = append(spans, span{byteToRune[l[0]], byteToRune[l[1]]})
	}

	var joined []string
	pos, segIdx, spanIdx := 0, 0, 0
	for segIdx < len(segments) && spanIdx < len(spans) {
		m := spans[spanIdx]
		if pos >= m.start {
			connected := ""
			for pos < m.end && segIdx < len(segments) {
				connected += segments[segIdx]
				pos += len([]rune(segments[segIdx]))
				segIdx++
			}
			if connected != "" {
				joined = append(joined, connected)
			}
			spanIdx++
		} else {
			joined = append(joined, segments[segIdx])
			pos += len([]rune(segments[segIdx]))
			segIdx++
		}
	}
	joined = append(joined, segments[segIdx:]...)
	return joined
}

// ---------------------------------------------------------------------------
// 公開API
// ---------------------------------------------------------------------------

var (
	wordTrieOnce sync.Once
	wordTrie     *Trie
	sylTrieOnce  sync.Once
	sylTrie      *Trie
)

func wordDictTrie() (*Trie, error) {
	var err error
	wordTrieOnce.Do(func() {
		var d *Data
		if d, err = Load(); err == nil {
			wordTrie = NewTrie(d.Words)
		}
	})
	if err != nil {
		return nil, err
	}
	return wordTrie, nil
}

func syllableDictTrie() (*Trie, error) {
	var err error
	sylTrieOnce.Do(func() {
		var d *Data
		if d, err = Load(); err == nil {
			sylTrie = NewTrie(d.Syllables)
		}
	})
	if err != nil {
		return nil, err
	}
	return sylTrie, nil
}

// wordTokenize は PyThaiNLP word_tokenize の既定（engine=newmm,
// keep_whitespace=True, join_broken_num=True）。
func wordTokenize(text string, dict *Trie) ([]string, error) {
	if text == "" {
		return []string{}, nil
	}
	segs, err := onecut([]rune(text), dict)
	if err != nil {
		return nil, err
	}
	return rejoinFormattedNum(segs), nil
}

// SubwordTokenize は subword_tokenize(word, engine="dict")（core.py:688-695）。
// 単語分割してから、各語を音節辞書で再分割する。
func SubwordTokenize(word string) ([]string, error) {
	wt, err := wordDictTrie()
	if err != nil {
		return nil, err
	}
	st, err := syllableDictTrie()
	if err != nil {
		return nil, err
	}

	words, err := wordTokenize(word, wt)
	if err != nil {
		return nil, err
	}
	var segments []string
	for _, w := range words {
		part, err := wordTokenize(w, st)
		if err != nil {
			return nil, err
		}
		segments = append(segments, part...)
	}
	if segments == nil {
		segments = []string{}
	}
	return segments, nil
}

// SegmentSyllables は nlp.py:segment_syllables:209。
func SegmentSyllables(word string) ([]string, error) {
	return SubwordTokenize(word)
}

// TokenizeWords は word_gap.py:_tokenize_words:142。
// 空白のみのトークンを落とす。
func TokenizeWords(text string) ([]string, error) {
	wt, err := wordDictTrie()
	if err != nil {
		return nil, err
	}
	words, err := wordTokenize(text, wt)
	if err != nil {
		return nil, err
	}
	out := make([]string, 0, len(words))
	for _, w := range words {
		if strings.TrimSpace(w) != "" {
			out = append(out, w)
		}
	}
	return out, nil
}
