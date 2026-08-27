package thainlp

import (
	"errors"
	"math"
	"regexp"
	"strings"
)

// 音節解析（tltk/th2ipa.py:sylparse:121）の移植。
//
// 2,223 本の規則を全位置に当ててチャートを作り、音節列の trigram 確率
// （Witten-Bell 平滑化・対数）が最大になる分割を選ぶ。
//
// 重要: Python 版の prob_wb は defaultdict の読みで欠損キーを 0 挿入するが、
// 値は 0 なので結果には影響しない。一方 compute_colloc の破壊的更新
// （th2ipa.py:893-897）は結果を変える。あれは g2p の別経路であり、
// ここでは移植しない（golden も状態リセット下で生成している）。

const (
	sylSep  = "~" // '~'
	wordSep = "|" // '|'
	ssegSep = "" // chr(30)
	segSep  = "" // chr(31)
)

// ---------------------------------------------------------------------------
// 確率（prob_trisyl / prob_wb : th2ipa.py:1156-1219）
// ---------------------------------------------------------------------------

// probWB は p(w | pw2 pw1) の Witten-Bell 平滑化。対数で返す。
func probWB(s *Stats, w, pw1, pw2 string) float64 {
	var p3, p2, p1 float64

	if c := s.TriCount[triKey{pw2, pw1, w}]; c > 0 {
		p3 = float64(c) / float64(s.BiCount[biKey{pw2, pw1}]+s.BiType[biKey{pw2, pw1}])
	}
	if c := s.BiCount[biKey{pw1, w}]; c > 0 {
		p2 = float64(c) / float64(s.Count[pw1]+s.Type[pw1])
	}
	if c := s.Count[w]; c > 0 {
		p1 = float64(c) / float64(s.TotalWord+s.TotalLex)
	}
	total := float64(s.TotalWord + s.TotalLex)
	p := 0.8*p3 + 0.15*p2 + 0.04*p1 + 1.0/(total*total)
	return math.Log(p)
}

// probTrisyl は音節列の対数確率の総和（th2ipa.py:1156）。
func probTrisyl(s *Stats, sylLst []string) float64 {
	pw2, pw1 := segSep, segSep
	probx := 1.0
	for _, w := range sylLst {
		probx += probWB(s, w, pw1, pw2)
		pw2, pw1 = pw1, w
	}
	return probx
}

// ---------------------------------------------------------------------------
// 音素置換と声調（th2ipa.py:309-497）
// ---------------------------------------------------------------------------

// errStableKey は Python の stable[x][c] が KeyError を投げる場合に対応する。
// 例: ฃ（ขวด）は stable["X"] にはあるが stable["Y"]（末子音）には無いため、
// 末子音位置に現れると KeyError になる。Go の map は既定値 "" を返してしまい
// 黙って別の結果を出すので、明示的にエラーにする。
var errStableKey = errors.New("thainlp: stable に無い子音")

// replaceSnd は ReplaceSnd:309。コード文字を実際の音素に置き換える。
func replaceSnd(rules *SylRules, phone, codematch, charmatch string) (string, error) {
	snd := phone
	chars := strings.Split(charmatch, " ")
	for i, x := range []rune(codematch) {
		if i >= len(chars) {
			break
		}
		tbl, ok := rules.Stable[string(x)]
		if !ok {
			return "", errStableKey
		}
		s, ok := tbl[chars[i]]
		if !ok {
			return "", errStableKey
		}
		snd = strings.ReplaceAll(snd, string(x), s)
	}
	return snd + "8", nil
}

var (
	reDot         = regexp.MustCompile(`\.`)
	reCRException = regexp.MustCompile(`^(?:ผ ร|ด ล|ต ล|ท ล|ด ว|ต ว|ท ว|บ ว|ป ว|พ ว|ฟ ว|ผ ว|ส ล|ส ว|ร ร|ศ ล|ศ ว)`)
	// Python 側は r'\u0E31[\0E48-\u0E4B]?ว]'。末尾の ] はリテラルで、
	// タイ語テキストに ] は現れないため**常に不一致**（TLTK 側の書き間違いで
	// この除外規則は事実上死んでいる）。挙動を変えないためリテラル ] を残す。
	reCase1        = regexp.MustCompile("ั[่-๋]?ว]")
	reKhoSpeller   = regexp.MustCompile(`[ก-ฮ] ข`)
	reKhoVowel     = regexp.MustCompile("[ุัเ]")
	reRoFinal      = regexp.MustCompile(`[ก-ฮ] ร$`)
	reAnPhone      = regexp.MustCompile(`.an`)
	reToneAssigned = regexp.MustCompile(`[0-4]8`)
	reLongVowel    = regexp.MustCompile(`[aeiouxOU@][aeiouxOU@]+`)
)

// notExceptionSyl は NotExceptionSyl:322。
//
// 注意: Python 版は 1 か -1 しか返さず、呼び出し側は `if NotExceptionSyl(...)`
// で真偽を見る。**Python では -1 も真**なので、この除外判定は実際には
// 一度も分岐を止めていない（除外のつもりで書かれた規則が全て素通りする）。
// 戻り値を bool にすると挙動が変わるため、int のまま返して 0 かどうかで
// 判定する（＝常に真）。TLTK の意図とは違うが、出力を変えないことを優先する。
func notExceptionSyl(rules *SylRules, codematch, charmatch, form, phone string) int {
	if reDot.MatchString(form) {
		return 1
	}
	if strings.Contains(codematch, "CR") {
		if reCRException.MatchString(charmatch) {
			return -1
		}
	}
	if strings.Contains(codematch, "AK") {
		clst := strings.Split(charmatch, " ")
		if len(clst) > 1 && !strings.Contains(rules.AK[clst[0]], clst[1]) {
			return -1
		}
	}
	if reCase1.MatchString(form) && strings.Contains(phone, "aw") {
		return -1
	}
	if reKhoSpeller.MatchString(charmatch) && !reKhoVowel.MatchString(form) {
		return -1
	}
	if reRoFinal.MatchString(charmatch) && reAnPhone.MatchString(phone) {
		return -1
	}
	return 1
}

const (
	middleConsonants = "กจดตฎฏบปอ"
	highConsonants   = "ขฃฉฐถผฝสศษห"
	lowSingle        = "งญณนมยรลวฬ"
	lowConsonants    = "คฅฆชฌซฑฒทธพภฟฮงญณนมยรลวฬฤฦ"
	leadHigh         = "ผฝถขสหฉศษ"
	leadMiddle       = "กจดตบปอ"
)

// 声調記号
const (
	maiEk       = "่"
	maiTho      = "้"
	maiTri      = "๊"
	maiChattawa = "๋"
)

// toneByMark は声調記号の有無で戻り値を選ぶ小道具。
// ek/tho/tri/chattawa/なし の順。
func toneByMark(keymatch, ek, tho, tri, cha, none string) string {
	switch {
	case strings.Contains(keymatch, maiEk):
		return ek
	case strings.Contains(keymatch, maiTho):
		return tho
	case strings.Contains(keymatch, maiTri):
		return tri
	case strings.Contains(keymatch, maiChattawa):
		return cha
	default:
		return none
	}
}

// toneAssign は ToneAssign:345。(phone, tone) を返す。
func toneAssign(keymatch, phone, codematch, charmatch string) (string, string) {
	if phone == "" {
		return "", "9"
	}
	if reToneAssigned.MatchString(phone) {
		// 既に声調が付いている
		phone = regexp.MustCompile(`([0-4])8`).ReplaceAllString(phone, "$1")
		return phone, ""
	}

	var lead, init, final string
	_ = final
	if strings.Contains(codematch, "X") || codematch == "GH" || codematch == "EF" {
		lx := strings.Split(charmatch, " ")
		lead = ""
		init = lx[0]
		if len(lx) > 1 {
			final = lx[1]
		}
	} else if strings.Contains(codematch, "AK") || strings.Contains(codematch, "CR") {
		lx := strings.Split(charmatch, " ")
		lead = lx[0]
		if len(lx) > 2 {
			final = lx[2]
			init = lx[1]
		} else if len(lx) > 1 {
			init = lx[1]
		}
	}

	deadsyll := deadSyl(phone)

	// 前音節の + を声調に変える
	if strings.Contains(phone, "+'") {
		switch {
		case lead != "" && strings.Contains(leadHigh, lead):
			phone = strings.ReplaceAll(phone, "+", "1")
		case lead != "" && strings.Contains(leadMiddle, lead):
			phone = strings.ReplaceAll(phone, "+", "1")
		default:
			phone = strings.ReplaceAll(phone, "+", "3")
		}
	}

	switch {
	case init != "" && strings.Contains(middleConsonants, init): // 中子音
		if deadsyll == "L" {
			return phone, toneByMark(keymatch, "1", "2", "3", "4", "0")
		}
		return phone, toneByMark(keymatch, "9", "2", "3", "4", "1")

	case init != "" && strings.Contains(highConsonants, init): // 高子音
		if deadsyll == "L" {
			return phone, toneByMark(keymatch, "1", "2", "9", "9", "4")
		}
		return phone, toneByMark(keymatch, "9", "2", "9", "9", "1")

	case init != "" && strings.Contains(lowSingle, init) && lead != "" && strings.Contains(highConsonants, lead):
		if deadsyll == "L" {
			return phone, toneByMark(keymatch, "1", "2", "9", "9", "4")
		}
		return phone, toneByMark(keymatch, "9", "2", "9", "9", "1")

	case init != "" && strings.Contains(lowSingle, init) && lead != "" && strings.Contains(middleConsonants, lead):
		if deadsyll == "L" {
			return phone, toneByMark(keymatch, "1", "2", "3", "4", "0")
		}
		return phone, toneByMark(keymatch, "9", "2", "3", "4", "1")

	case init != "" && strings.Contains(lowConsonants, init): // 低子音
		if deadsyll == "L" {
			return phone, toneByMark(keymatch, "2", "3", "9", "9", "0")
		}
		if reLongVowel.MatchString(phone) { // 長母音
			return phone, toneByMark(keymatch, "9", "3", "9", "4", "2")
		}
		return phone, toneByMark(keymatch, "2", "9", "9", "4", "3") // 短母音
	}

	// Python 版はどの分岐にも入らないと None を返す（暗黙の return）。
	// 呼び出し側は tone < '5' の比較をするので、空文字で表す。
	return phone, ""
}

var (
	reDeadFinalL = regexp.MustCompile(`[mnwjlN]8?$`)
	reDeadFinalD = regexp.MustCompile(`[pktfscC]8?$`)
	reDigits     = regexp.MustCompile(`[0-4]`)
)

// hasDoubledVowel は Python の r'([aeiouxOU@])\1'。同じ母音字が2つ続くか。
// Go の RE2 は後方参照を持たないので手で書く。
func hasDoubledVowel(s string) bool {
	const vowels = "aeiouxOU@"
	r := []rune(s)
	for i := 0; i+1 < len(r); i++ {
		if r[i] == r[i+1] && strings.ContainsRune(vowels, r[i]) {
			return true
		}
	}
	return false
}

// deadSyl は DeadSyl:463。死音節なら "D"、生音節なら "L"。
func deadSyl(phone string) string {
	inx := strings.ReplaceAll(phone, "ch", "C")
	inx = reDigits.ReplaceAllString(inx, "")
	switch {
	case reDeadFinalL.MatchString(inx):
		return "L"
	case reDeadFinalD.MatchString(inx):
		return "D"
	case hasDoubledVowel(inx):
		return "L"
	default:
		return "D"
	}
}

var (
	reXXFinal   = regexp.MustCompile(`xx[nmN][12]`)
	reEEFinal   = regexp.MustCompile(`ee[nmN][12]`)
	reAtFinal   = regexp.MustCompile(`@@[nmN][12]`)
	reYaForms   = regexp.MustCompile(`^อย่า$|^อยู่$|^อย่าง$|^อยาก$`)
	reHoExclude = regexp.MustCompile(`หนุ$|หก|หท|หพ|หฤ|หโ`)
	reClusterCS = regexp.MustCompile(`[จซศส]ร`)
	reClusterPh = regexp.MustCompile(`[cs]r`)
	reNotQuote  = regexp.MustCompile(`[^']`)
)

// transformSyl は TransformSyl:476。
func transformSyl(form, phone string) (string, string) {
	switch {
	case reXXFinal.MatchString(phone):
		phone = strings.ReplaceAll(phone, "xx", "x")
	case reEEFinal.MatchString(phone):
		phone = strings.ReplaceAll(phone, "ee", "e")
	case reAtFinal.MatchString(phone):
		// Python 側は re.sub(r'\@\@', '\@', phone)。置換文字列がエスケープ
		// された '\@'（バックスラッシュ+@）なので、結果は "@" ではなく "\@"
		// になる（th2ipa.py:482、TLTK の書き間違い）。実測で確認済み:
		//   re.sub(r'\@\@','\@','@@n1') -> '\\@n1'
		// 出力を変えないため、そのまま再現する。
		phone = strings.ReplaceAll(phone, "@@", `\@`)
	}

	switch {
	case reYaForms.MatchString(form) && strings.Contains(phone, "'"):
		x := strings.Split(phone, "'")
		phone = x[len(x)-1]
	case strings.Contains(form, "ห") && strings.Contains(phone, "ha1") && !reHoExclude.MatchString(form):
		x := strings.Split(phone, "'")
		phone = x[len(x)-1]
	case reClusterCS.MatchString(form) && reClusterPh.MatchString(phone) && reNotQuote.MatchString(phone):
		phone = strings.ReplaceAll(phone, "r", "")
	}
	return form, phone
}

// ---------------------------------------------------------------------------
// mergekaran1 (th2ipa.py:1120)
// ---------------------------------------------------------------------------

var (
	reKaranIU = regexp.MustCompile(`(.+)[ิุ]์`)
	reKaran   = regexp.MustCompile(`(.+)์`)
)

// mergeKaran1 は караン（黙字記号）を前の音節に結合する。
// pronun は PRONUN 相当で、結合語の候補音素も引き継ぐ。
func mergeKaran1(lst []string, pronun map[string][]string) []string {
	var rs []string
	found := false
	x := ""
	seen := map[string]bool{}

	// Python は Lst.reverse() してから走査する
	for i := len(lst) - 1; i >= 0; i-- {
		s := lst[i]
		if reKaranIU.MatchString(s) {
			if len([]rune(s)) < 4 {
				found = true
				x = s
				continue
			}
		} else if reKaran.MatchString(s) {
			if len([]rune(s)) < 4 {
				found = true
				x = s
				continue
			}
		}
		if found {
			for _, ph := range pronun[s] {
				key := s + x + "\x00" + ph
				if !seen[key] {
					pronun[s+x] = append(pronun[s+x], ph)
					seen[key] = true
				}
			}
			s += x
			rs = append(rs, s)
			found = false
		} else {
			rs = append(rs, s)
		}
	}
	// rs.reverse()
	for i, j := 0, len(rs)-1; i < j; i, j = i+1, j-1 {
		rs[i], rs[j] = rs[j], rs[i]
	}
	return rs
}

// ---------------------------------------------------------------------------
// sylparse 本体
// ---------------------------------------------------------------------------

var reNonCodeChars = regexp.MustCompile(`[^AKYDZCRX]`)

// SylParseResult は sylparse の結果と、後段 wordparse が使う候補音素表。
type SylParseResult struct {
	// Syllables は音節列。失敗時は nil。
	Syllables []string
	// Pronun は音節 -> 候補音素列（PRONUN 相当）。
	Pronun map[string][]string
	// Failed は <Fail> になった場合 true。
	Failed bool
	Input  string
}

// SylParse は th2ipa.py:sylparse:121。音節を '~' で連結して返す。
func SylParse(text string) (string, error) {
	r, err := sylParse(text)
	if err != nil {
		return "", err
	}
	if r.Failed {
		return "<Fail>" + r.Input + "</Fail>", nil
	}
	return strings.Join(r.Syllables, sylSep), nil
}

func sylParse(input string) (*SylParseResult, error) {
	rules, err := LoadSylRules()
	if err != nil {
		return nil, err
	}
	d, err := Load()
	if err != nil {
		return nil, err
	}
	stats := d.Stats

	runes := []rune(input)
	end := len(runes)
	pronun := map[string][]string{}

	// schart[i][k] = 音節列
	schart := map[int]map[int][]string{}
	probEnd := map[[2]int]float64{}
	getS := func(i int) map[int][]string {
		if schart[i] == nil {
			schart[i] = map[int][]string{}
		}
		return schart[i]
	}

	// charmatch は Python 側で sylparse のローカル変数として反復をまたいで
	// 残る。グループ無しパターンでは代入されず前の値が使われる。
	charmatch := ""

	// PRON を挿入順に走査する（Python の `for f in PRON:` と同じ）
	for _, rule := range rules.Pron {
		for i := range end {
			m, err := rule.Match(runes[i:])
			if err != nil {
				return nil, err
			}
			if m == nil {
				continue
			}
			keymatch := m.String()
			k := i + len([]rune(keymatch))
			getS(i)[k] = []string{keymatch}
			key := keymatch

			// Python は group(3)->group(2)->group(1) の順に触り、
			// IndexError で段を落とす（th2ipa.py:140-155）。
			// グループが1つも無いパターンでは PRONUN に PRON[f] を
			// そのまま足し、**charmatch は前の反復の値が残る**
			// （代入されないため）。その挙動をそのまま再現する。
			groups := m.Groups()
			ngroups := len(groups) - 1
			switch {
			case ngroups >= 3:
				charmatch = groups[1].String() + " " + groups[2].String() + " " + groups[3].String()
			case ngroups == 2:
				charmatch = groups[1].String() + " " + groups[2].String()
			case ngroups == 1:
				charmatch = groups[1].String()
			default:
				pronun[key] = append(pronun[key], rule.Phones...)
			}

			for _, pronF := range rule.Phones {
				codematch := reNonCodeChars.ReplaceAllString(pronF, "")
				if codematch == "" {
					continue
				}
				phone, err := replaceSnd(rules, pronF, codematch, charmatch)
				if err != nil {
					return nil, err
				}
				km := keymatch
				// Python の `if NotExceptionSyl(...)`。-1 も真なので 0 判定にする。
				if notExceptionSyl(rules, codematch, charmatch, km, phone) != 0 {
					var tone string
					phone, tone = toneAssign(km, phone, codematch, charmatch)
					// Python は `if (tone < '5')`。空文字も '' < '5' が真なので
					// 8 が削除される。tone != "" を条件に足してはいけない。
					if tone < "5" {
						phone = strings.ReplaceAll(phone, "8", tone)
					}
					km, phone = transformSyl(km, phone)
				}
				pronun[key] = append(pronun[key], phone)

				// ทร + thr => s の追加候補
				if strings.HasPrefix(km, "ทร") && strings.HasPrefix(phone, "thr") {
					pronun[key] = append(pronun[key], strings.Replace(phone, "thr", "s", 1))
				}
				probEnd[[2]int{i, k}] = probTrisyl(stats, getS(i)[k])
			}
		}
	}

	// チャートのマージ（th2ipa.py:199-219）
	for j := range end {
		schartx := deepCopyChart(schart)
		if s1, ok := getS(0)[j]; ok {
			for k, s2 := range getS(j) {
				merged := mergeKaran1(append(append([]string{}, s1...), s2...), pronun)
				if _, exists := getS(0)[k]; !exists {
					if schartx[0] == nil {
						schartx[0] = map[int][]string{}
					}
					schartx[0][k] = merged
					probEnd[[2]int{0, k}] = probTrisyl(stats, merged)
				} else {
					p := probTrisyl(stats, merged)
					if p > probEnd[[2]int{0, k}] {
						if schartx[0] == nil {
							schartx[0] = map[int][]string{}
						}
						schartx[0][k] = merged
						probEnd[[2]int{0, k}] = p
					}
				}
			}
		}
		schart = schartx
	}

	if syls, ok := getS(0)[end]; ok {
		return &SylParseResult{Syllables: syls, Pronun: pronun, Input: input}, nil
	}
	return &SylParseResult{Failed: true, Pronun: pronun, Input: input}, nil
}

func deepCopyChart(src map[int]map[int][]string) map[int]map[int][]string {
	dst := make(map[int]map[int][]string, len(src))
	for i, row := range src {
		nr := make(map[int][]string, len(row))
		for k, v := range row {
			nr[k] = append([]string{}, v...)
		}
		dst[i] = nr
	}
	return dst
}
