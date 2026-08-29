package thainlp

import (
	"bufio"
	"compress/gzip"
	"encoding/json"
	"fmt"
	"math"
	"regexp"
	"sort"
	"strings"
	"sync"
)

// 語の組み立てと音素列の確定（tltk/th2ipa.py:wordparse:498）の移植。
//
// sylparse が作った音節列と候補音素表（PRONUN）を受け取り、
//   1. TDICT に載る音節連結を語の候補としてチャートに入れる
//   2. 相互情報量（compute_colloc "mi"）の合計が最大になる語分割を選ぶ
//   3. 各語について SelectPhones が ProbPhone 最大の音素列を選ぶ
//
// 重要: Python の compute_colloc は未知バイグラムに対して BiCount / Count /
// TotalWord を破壊的に加算する（th2ipa.py:893-897）。これが th2ipa の
// 非決定性の発生源で、golden は状態リセット下で生成している。
// したがってここでは加算をローカルに閉じ、共有状態を書き換えない。

// ---------------------------------------------------------------------------
// ProbPhone 用テーブル
// ---------------------------------------------------------------------------

type phoneStats struct {
	tdict map[string]bool

	phSTrigram  map[[4]string]float64
	frmSTrigram map[[3]string]float64
	phSBigram   map[[3]string]float64
	frmSBigram  map[[2]string]float64
	phSUnigram  map[[2]string]float64
	frmSUnigram map[string]float64
	absUnigram  map[[2]string]float64
	absFrmSUni  map[string]float64
}

var (
	phoneOnce sync.Once
	phoneData *phoneStats
	phoneErr  error
)

func loadPhoneStats() (*phoneStats, error) {
	phoneOnce.Do(func() { phoneData, phoneErr = doLoadPhoneStats() })
	return phoneData, phoneErr
}

// eachGzLine は gzip 圧縮された JSONL を1行ずつ渡す。
func eachGzLine(name string, fn func([]byte) error) error {
	f, err := dataFS.Open(name)
	if err != nil {
		return err
	}
	defer f.Close()
	gz, err := gzip.NewReader(f)
	if err != nil {
		return err
	}
	defer gz.Close()

	sc := bufio.NewScanner(gz)
	sc.Buffer(make([]byte, 0, 64*1024), 4*1024*1024)
	for sc.Scan() {
		if len(sc.Bytes()) == 0 {
			continue
		}
		if err := fn(sc.Bytes()); err != nil {
			return fmt.Errorf("%s: %w", name, err)
		}
	}
	return sc.Err()
}

// decodeRow は ["k1",...,"kN", value] を分解する。
func decodeRow(line []byte, arity int) ([]string, float64, error) {
	var raw []json.RawMessage
	if err := json.Unmarshal(line, &raw); err != nil {
		return nil, 0, err
	}
	if len(raw) != arity+1 {
		return nil, 0, fmt.Errorf("要素数 %d、想定 %d", len(raw), arity+1)
	}
	keys := make([]string, arity)
	for i := range arity {
		if err := json.Unmarshal(raw[i], &keys[i]); err != nil {
			return nil, 0, err
		}
	}
	var v float64
	if err := json.Unmarshal(raw[arity], &v); err != nil {
		return nil, 0, err
	}
	return keys, v, nil
}

func doLoadPhoneStats() (*phoneStats, error) {
	p := &phoneStats{
		tdict:       map[string]bool{},
		phSTrigram:  map[[4]string]float64{},
		frmSTrigram: map[[3]string]float64{},
		phSBigram:   map[[3]string]float64{},
		frmSBigram:  map[[2]string]float64{},
		phSUnigram:  map[[2]string]float64{},
		frmSUnigram: map[string]float64{},
		absUnigram:  map[[2]string]float64{},
		absFrmSUni:  map[string]float64{},
	}

	if err := eachGzLine("data/tdict.txt.gz", func(b []byte) error {
		p.tdict[string(b)] = true
		return nil
	}); err != nil {
		return nil, err
	}

	loaders := []struct {
		file  string
		arity int
		put   func([]string, float64)
	}{
		{"PhSTrigram", 4, func(k []string, v float64) { p.phSTrigram[[4]string{k[0], k[1], k[2], k[3]}] = v }},
		{"FrmSTrigram", 3, func(k []string, v float64) { p.frmSTrigram[[3]string{k[0], k[1], k[2]}] = v }},
		{"PhSBigram", 3, func(k []string, v float64) { p.phSBigram[[3]string{k[0], k[1], k[2]}] = v }},
		{"FrmSBigram", 2, func(k []string, v float64) { p.frmSBigram[[2]string{k[0], k[1]}] = v }},
		{"PhSUnigram", 2, func(k []string, v float64) { p.phSUnigram[[2]string{k[0], k[1]}] = v }},
		{"FrmSUnigram", 1, func(k []string, v float64) { p.frmSUnigram[k[0]] = v }},
		{"AbsUnigram", 2, func(k []string, v float64) { p.absUnigram[[2]string{k[0], k[1]}] = v }},
		{"AbsFrmSUnigram", 1, func(k []string, v float64) { p.absFrmSUni[k[0]] = v }},
	}
	for _, l := range loaders {
		if err := eachGzLine("data/"+l.file+".jsonl.gz", func(b []byte) error {
			k, v, err := decodeRow(b, l.arity)
			if err != nil {
				return err
			}
			l.put(k, v)
			return nil
		}); err != nil {
			return nil, err
		}
	}
	return p, nil
}

// ---------------------------------------------------------------------------
// ProbPhone (th2ipa.py:593)
// ---------------------------------------------------------------------------

var (
	reToneMarks   = regexp.MustCompile("[่้๊๋]")
	reThaiConso   = regexp.MustCompile("[ก-ฮ]")
	reDigitsAll   = regexp.MustCompile(`[0-9]`)
	reNonVowelSet = regexp.MustCompile(`[^aeio@OuxU]`)
)

// probPhone は ProbPhone:593。
//
// 加算順序は Python の式をそのまま保つ。順序を変えると丸めが変わり、
// 僅差の候補で argmax が反転しうる。
func probPhone(s *phoneStats, p, pw, w, nw string) float64 {
	var p3, p2, p1, p0 float64

	if c := s.phSTrigram[[4]string{pw, w, nw, p}]; c > 0 {
		p3 = (1. + math.Log(c)) / (1. + math.Log(s.frmSTrigram[[3]string{pw, w, nw}]))
	}
	if c := s.phSBigram[[3]string{pw, w, p}]; c > 0 {
		p2 = (1. + math.Log(c)) / (1. + math.Log(s.frmSBigram[[2]string{pw, w}])) * 0.25
	}
	if c := s.phSBigram[[3]string{w, nw, p}]; c > 0 {
		p2 = p2 + (1.+math.Log(c))/(1.+math.Log(s.frmSBigram[[2]string{w, nw}]))*0.75
	}
	if c := s.phSUnigram[[2]string{w, p}]; c > 0 {
		p1 = (1 + math.Log(c)) / (1. + math.Log(s.frmSUnigram[w]))
	}

	// 抽象化した形（声調記号を落とし子音を C に、音素の数字を落とし非母音を C に）
	absW := reToneMarks.ReplaceAllString(w, "")
	absW = reThaiConso.ReplaceAllString(absW, "C")
	absP := reDigitsAll.ReplaceAllString(p, "")
	absP = reNonVowelSet.ReplaceAllString(absP, "C")
	if c := s.absUnigram[[2]string{absW, absP}]; c > 0 {
		p0 = (1 + math.Log(c)) / (1. + math.Log(s.absFrmSUni[absW]))
	}

	return 0.8*p3 + 0.16*p2 + 0.03*p1 + 0.00001*p0 + 0.00000000001
}

var reQuote = regexp.MustCompile(`'`)

// selectPhones は SelectPhones:558。音節ごとに最尤の音素列を選ぶ。
func selectPhones(s *phoneStats, pronun map[string][]string, slst []string) string {
	padded := make([]string, 0, len(slst)+2)
	padded = append(padded, "|")
	padded = append(padded, slst...)
	padded = append(padded, "|")

	out := make([]string, 0, len(slst))
	for i := 1; i < len(padded)-1; i++ {
		cands := pronun[padded[i]]
		if len(cands) == 1 {
			out = append(out, cands[0])
			continue
		}
		outp := ""
		prmax := 0.
		for _, p := range cands {
			pr := probPhone(s, p, padded[i-1], padded[i], padded[i+1])
			if pr > prmax {
				prmax = pr
				outp = p
			} else if pr == prmax {
				// 同点なら、連結記号 ' を含みより長い候補を優先する
				if reQuote.MatchString(p) && len(p) > len(outp) {
					prmax = pr
					outp = p
				}
			}
		}
		out = append(out, outp)
	}
	return strings.Join(out, sylSep)
}

// ---------------------------------------------------------------------------
// compute_colloc (th2ipa.py:883) — 相互情報量
// ---------------------------------------------------------------------------

// collocState は compute_colloc の加算スムージングを1回の wordparse 呼び出しの
// 中だけで累積させるための重ね書き。
//
// Python の compute_colloc は未知バイグラムに対して BiCount / Count / TotalWord
// を破壊的に加算する（th2ipa.py:893-897）。この加算は**同じ wordparse の中で
// 後続の MI 計算に影響する**。例: ส.ว.ท. では ส.ว. の MI を求めた副作用で
// Count["ว."] が増え、続く ว.ท. の MI が変わる。その結果どちらの語区切りが
// 勝つかが決まる。
//
// 一方、この加算がプロセス全体に残ることが th2ipa の非決定性の原因だった。
// そこで呼び出しごとに使い捨てる重ね書きに閉じ込める。呼び出し内の挙動は
// Python と同一で、呼び出しをまたぐ汚染だけが消える（golden も状態リセット下で
// 生成しているので、これが一致する形）。
type collocState struct {
	base  *Stats
	bi    map[biKey]int
	cnt   map[string]int
	total int
}

func newCollocState(st *Stats) *collocState {
	return &collocState{base: st, bi: map[biKey]int{}, cnt: map[string]int{}, total: st.TotalWord}
}

func (c *collocState) biCount(k biKey) int {
	if v, ok := c.bi[k]; ok {
		return v
	}
	return c.base.BiCount[k]
}

func (c *collocState) count(w string) int {
	if v, ok := c.cnt[w]; ok {
		return v
	}
	return c.base.Count[w]
}

// mi は compute_colloc(stat="mi")。
func (c *collocState) mi(w1, w2 string) float64 {
	k := biKey{w1, w2}
	bi := c.biCount(k)
	c1 := c.count(w1)
	c2 := c.count(w2)

	if bi < 1 || c1 < 1 || c2 < 1 {
		c.bi[k] = bi + 1
		c.cnt[w1] = c1 + 1
		// w1 と w2 が同じ語なら Python も同じキーを2回増やす
		c.cnt[w2] = c.count(w2) + 1
		c.total += 2
		bi = c.biCount(k)
		c1 = c.count(w1)
		c2 = c.count(w2)
	}
	mi := float64(bi) * float64(c.total) / (float64(c1) * float64(c2))
	return math.Abs(math.Log2(mi))
}

// ---------------------------------------------------------------------------
// wordparse 本体
// ---------------------------------------------------------------------------

var (
	reMaiyamokFind = regexp.MustCompile(`(<tr/>|\|)([?a-zENOU0-9~'@^]+?)[|~]ๆ`)
)

// WordParse は th2ipa.py:wordparse:498。"タイ文字<tr/>音素列" を返す。
//
// Python は wordparse(sylparse(x)) と文字列を渡す。sylparse が失敗して
// "<Fail>...</Fail>" を返した場合もそのまま次段へ流れ、その文字列全体が
// 1音節として扱われる。PRONUN に候補が無いので音素列は空になり、
// 結果は "<Fail>...</Fail><tr/>" になる。その挙動に合わせる。
func WordParse(text string) (string, error) {
	r, err := sylParse(text)
	if err != nil {
		return "", err
	}
	syls := r.Syllables
	if r.Failed {
		syls = []string{"<Fail>" + r.Input + "</Fail>"}
	}
	return wordParse(syls, r.Pronun)
}

func wordParse(sylLst []string, pronun map[string][]string) (string, error) {
	ps, err := loadPhoneStats()
	if err != nil {
		return "", err
	}
	d, err := Load()
	if err != nil {
		return "", err
	}
	cs := newCollocState(d.Stats)

	end := len(sylLst)

	chart := map[int]map[int][]string{}
	collocSt := map[[2]int]float64{}
	getC := func(i int) map[int][]string {
		if chart[i] == nil {
			chart[i] = map[int][]string{}
		}
		return chart[i]
	}

	for i := range end {
		getC(i)[i+1] = []string{sylLst[i]}
	}
	for i := range end {
		for j := i; j <= end; j++ {
			wrd := strings.Join(sylLst[i:j], "")
			if !ps.tdict[wrd] {
				continue
			}
			getC(i)[j] = []string{strings.Join(sylLst[i:j], sylSep)}
			if j > i+1 {
				stv := 0.0
				for ii := i; ii < j-1; ii++ {
					stv += cs.mi(sylLst[ii], sylLst[ii+1])
				}
				collocSt[[2]int{i, j}] = stv
			} else {
				collocSt[[2]int{i, j}] = 0.0
			}
		}
	}

	// chart_parse (th2ipa.py:989)
	for j := range end {
		chartx := deepCopyChart(chart)
		if s1, ok := getC(0)[j]; ok {
			// Python は dict を挿入順に走査する。chart[i] のキーは
			//   chart[i][i+1] を先に入れ、その後 TDICT ヒットを j 昇順で入れる
			// ので、結果として**昇順**になる。Go の map 反復順はランダムなので
			// 明示的に昇順へ並べないと、同点時にどちらが残るかが変わる。
			ks := make([]int, 0, len(getC(j)))
			for k := range getC(j) {
				ks = append(ks, k)
			}
			sort.Ints(ks)
			for _, k := range ks {
				s2 := getC(j)[k]
				merged := append(append([]string{}, s1...), s2...)
				sum := collocSt[[2]int{0, j}] + collocSt[[2]int{j, k}]
				if _, exists := getC(0)[k]; !exists {
					if chartx[0] == nil {
						chartx[0] = map[int][]string{}
					}
					chartx[0][k] = merged
					collocSt[[2]int{0, k}] = sum
				} else if sum > collocSt[[2]int{0, k}] {
					if chartx[0] == nil {
						chartx[0] = map[int][]string{}
					}
					chartx[0][k] = merged
					collocSt[[2]int{0, k}] = sum
				}
			}
		}
		chart = chartx
	}

	words, ok := getC(0)[end]
	if !ok {
		return "<Fail>" + strings.Join(sylLst, sylSep) + "</Fail>", nil
	}

	outx := strings.Join(words, wordSep)
	outx = strings.ReplaceAll(outx, "~ๆ", "|ๆ")
	outx += "<tr/>"

	outp := make([]string, 0, len(words))
	for _, wx := range words {
		outp = append(outp, selectPhones(ps, pronun, strings.Split(wx, sylSep)))
	}
	outx += strings.Join(outp, wordSep)

	// ๆ の直前語を複製する
	outx = reMaiyamokFind.ReplaceAllString(outx, "$1$2"+wordSep+"$2")
	return outx, nil
}
