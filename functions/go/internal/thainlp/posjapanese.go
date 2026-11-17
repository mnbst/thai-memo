package thainlp

import (
	"encoding/json"
	"slices"
	"sync"
)

// 品詞判定の日本語ラベル化。nlp.py の _tag_words / get_pos_japanese を移す。
//
// perceptron を単独で使うと未知語をすべて NOUN と推測してしまうため、
// 精度の高い順に4段階で適用する（nlp.py:145-206）。

var (
	projOnce sync.Once
	projData *projectPOS
	projErr  error
)

type projectPOS struct {
	// tagMap は UD タグ -> 日本語ラベル（nlp.py:_POS_TAG_MAP）。
	tagMap map[string]string
	// override は機能語の確定辞書（nlp.py:_POS_OVERRIDE）。
	override map[string]string
	// adjectives は形容詞辞書（pos_adjectives.ADJECTIVES）。
	adjectives map[string]bool
	// lexicon は tud に無い語の品詞（data/pos_lexicon.json、UD タグ）。
	// tud に無い語は perceptron の当て推量になり、同じ語でも文ごとに品詞が割れていた（2026-11-16）。
	lexicon map[string]string
}

func loadProjectPOS() (*projectPOS, error) {
	projOnce.Do(func() {
		raw, err := dataFS.ReadFile("data/pos_project.json")
		if err != nil {
			projErr = err
			return
		}
		var f struct {
			TagMap     map[string]string `json:"pos_tag_map"`
			Override   map[string]string `json:"pos_override"`
			Adjectives []string          `json:"adjectives"`
		}
		if err := json.Unmarshal(raw, &f); err != nil {
			projErr = err
			return
		}
		adj := make(map[string]bool, len(f.Adjectives))
		for _, a := range f.Adjectives {
			adj[a] = true
		}
		lexRaw, err := dataFS.ReadFile("data/pos_lexicon.json")
		if err != nil {
			projErr = err
			return
		}
		var lex map[string]string
		if err := json.Unmarshal(lexRaw, &lex); err != nil {
			projErr = err
			return
		}
		projData = &projectPOS{tagMap: f.TagMap, override: f.Override, adjectives: adj, lexicon: lex}
	})
	return projData, projErr
}

// POSJapanese は nlp.py:get_pos_japanese:226。
// 該当が無ければ "その他"。
func POSJapanese(word string) (string, error) {
	tags, err := TagWords([]string{word})
	if err != nil {
		return "", err
	}
	if v, ok := tags[0]; ok {
		return v, nil
	}
	return "その他", nil
}

// TagWords は nlp.py:_tag_words:145。インデックス -> 日本語の品詞名。
//
// 埋まらなかったインデックスはキーごと存在しない（Python の dict と同じ）。
func TagWords(words []string) (map[int]string, error) {
	result, err := tagWordsBase(words)
	if err != nil {
		return nil, err
	}
	tagAuxVerbs(words, result)
	tagKhong(words, result)
	tagThii(words, result)
	tagClassifiers(words, result)
	tagMonkEat(words, result)
	tagHomographs(words, result)
	tagByNeighbors(words, result)
	return result, nil
}

// clauseEndTags は直後に来ると前の語が節の終わりになる品詞。
var clauseEndTags = map[string]bool{"": true, "助詞": true, "副詞": true, "句読点": true}

// demonstratives は直後に来ると รอบ が「回」（名詞）になる語（รอบนี้・รอบหน้า）。
var demonstratives = map[string]bool{"นี้": true, "นั้น": true, "หน้า": true, "ที่แล้ว": true, "ก่อน": true}

// tagByNeighbors は unigram が1つの品詞に決めている語を、前後の品詞で分ける（2026-11-17 プール確認）。
//   - กำหนด: ก่อน・ตาม の後は「予定・期限」（名詞）。先に決めて、下の ก่อน の判定に使う
//   - ช่าง: 形容詞・副詞の前は「なんて〜」（副詞）、ช่างมัน・ช่างเถอะ は動詞、それ以外は「職人」（名詞）。unigram は助動詞にする
//   - ให้: 名詞・動詞の後で「代名詞＋節の終わり」が続くなら「〜のために」（前置詞）。
//     使役（สอนให้เรารู้จัก）は代名詞の後に動詞が来るので接続詞のまま
//   - ถึง: 文頭で後ろに แต่ があれば譲歩「たとえ〜でも」（接続詞）
//   - ก่อน: 節の終わりなら「先に」（副詞）、名詞の前なら「〜より前に」（前置詞）。動詞の前は接続詞のまま
//   - รอบ: 指示語の前は「回」（名詞）。unigram は前置詞にする
//   - ได้: 動詞の後でなく名詞の前なら「得る」（動詞）
func tagByNeighbors(words []string, result map[int]string) {
	n := len(words)
	tagAt := func(i int) string {
		if i < 0 || i >= n {
			return ""
		}
		return result[i]
	}
	for i, w := range words {
		if w == "กำหนด" && i > 0 && (words[i-1] == "ก่อน" || words[i-1] == "ตาม") {
			result[i] = "名詞"
		}
	}
	for i, w := range words {
		prev, next := tagAt(i-1), tagAt(i+1)
		switch w {
		case "ช่าง":
			if i+1 < n && (words[i+1] == "มัน" || words[i+1] == "เถอะ") {
				result[i] = "動詞" // ช่างมัน・ช่างเถอะ「放っておく」
			} else if next == "形容詞" || next == "副詞" {
				result[i] = "副詞"
			} else {
				result[i] = "名詞"
			}
		case "ให้":
			if (isNominal(prev) || prev == "動詞") && next == "代名詞" && clauseEndTags[tagAt(i+2)] {
				result[i] = "前置詞"
			}
		case "ถึง":
			if i == 0 && slices.Contains(words[1:], "แต่") {
				result[i] = "接続詞"
			}
		case "ก่อน":
			switch {
			case i > 0 && clauseEndTags[next]:
				result[i] = "副詞"
			case isNominal(next):
				result[i] = "前置詞"
			}
		case "รอบ":
			if i+1 < n && demonstratives[words[i+1]] {
				result[i] = "名詞"
			}
		case "ได้":
			if prev != "動詞" && prev != "助動詞" && isNominal(next) {
				result[i] = "動詞"
			}
		}
	}
}

// numberUnits は数詞の後ろに来る単位・類別詞（หกโมง・หกคน）。
var numberUnits = map[string]bool{
	"โมง": true, "ทุ่ม": true, "คน": true, "ตัว": true, "อัน": true, "ใบ": true, "ชิ้น": true, "เล่ม": true,
	"คัน": true, "หลัง": true, "ขวด": true, "แก้ว": true, "บาท": true, "ปี": true, "เดือน": true,
	"วัน": true, "คืน": true, "ชั่วโมง": true, "นาที": true, "วินาที": true, "ครั้ง": true, "ข้อ": true,
	"ห้อง": true, "ชั้น": true, "จาน": true, "ชาม": true, "กิโล": true, "เมตร": true, "ขวบ": true,
	"สัปดาห์": true, "อาทิตย์": true, "ที่": true, "รอบ": true, "แห่ง": true, "เรื่อง": true, "ร้อย": true,
	"พัน": true, "หมื่น": true, "แสน": true, "ล้าน": true, "สิบ": true,
}

// numberMarkers は直後の数詞が番号・順序を表す語（ข้อหก・ที่หก）。
var numberMarkers = map[string]bool{"ที่": true, "ข้อ": true, "เลข": true, "ห้อง": true, "ชั้น": true, "ครั้งที่": true, "อันดับ": true}

// nightBefore は直後の คืน が「夜」になる語（ทั้งคืน・ทุกคืน）。
var nightBefore = map[string]bool{
	"ทั้ง": true, "ทุก": true, "ตอน": true, "กลาง": true, "เมื่อ": true, "หลาย": true, "บาง": true, "ค่ำ": true,
}

// nightAfter は直前の คืน が「夜」になる語（คืนนั้น）。
var nightAfter = map[string]bool{"นี้": true, "นั้น": true, "วันศุกร์": true, "วันเสาร์": true, "สุดท้าย": true, "แรก": true}

// mannerWords は名詞の後ろなら「こういう〜」（限定詞）、それ以外は「このように」（副詞）になる語。
var mannerWords = map[string]bool{"แบบนี้": true, "แบบนั้น": true, "อย่างนี้": true, "อย่างนั้น": true}

// HomographWords は tagHomographs が前後で品詞を分ける語。
var HomographWords = map[string]bool{"หก": true, "คืน": true, "แบบนี้": true, "แบบนั้น": true, "อย่างนี้": true, "อย่างนั้น": true}

// tagHomographs は辞書が1つの品詞に決めている語を前後で分ける。
// หก は数詞「6」と動詞「こぼれる」、คืน は動詞「返す」と名詞「夜」。
// แบบนี้ 等は名詞の後ろなら限定詞（งานเลี้ยงแบบนี้）、それ以外は副詞（เล่นแบบนี้）。
func tagHomographs(words []string, result map[int]string) {
	for i, w := range words {
		prev, next := "", ""
		if i > 0 {
			prev = words[i-1]
		}
		if i+1 < len(words) {
			next = words[i+1]
		}
		if mannerWords[w] {
			if i > 0 && isNominal(result[i-1]) {
				result[i] = "限定詞"
			} else {
				result[i] = "副詞"
			}
			continue
		}
		switch w {
		case "หก":
			if numberUnits[next] || numberMarkers[prev] || (i > 0 && result[i-1] == "数詞") || result[i+1] == "数詞" || result[i+1] == "類別詞" {
				result[i] = "数詞"
			} else {
				result[i] = "動詞"
			}
		case "คืน":
			if nightBefore[prev] || nightAfter[next] || (i > 0 && result[i-1] == "数詞") {
				result[i] = "名詞"
			}
		}
	}
}

// classifierWords は名詞の後ろで類別詞になる語。unigram は ใบ・คน・ตัว を一律に名詞にする
// （ถังใบนี้ の ใบ、นักร้องคนนี้ の คน）。
var classifierWords = map[string]bool{
	"ใบ": true, "ตัว": true, "คน": true, "อัน": true, "ชิ้น": true, "เล่ม": true, "คัน": true,
	"หลัง": true, "ดอก": true, "ขวด": true, "แก้ว": true, "เครื่อง": true,
}

// classifierFollowers は類別詞の後ろに来る指示語。
var classifierFollowers = map[string]bool{
	"นี้": true, "นั้น": true, "โน้น": true, "ไหน": true, "เดียว": true,
}

// tagClassifiers は classifierWords の語を、数詞の後ろ（สองตัว）か、
// 名詞の後ろで指示語が続くとき（ถังใบนี้）に類別詞にする。
func tagClassifiers(words []string, result map[int]string) {
	for i, w := range words {
		if !classifierWords[w] || i == 0 {
			continue
		}
		prev := result[i-1]
		// หลัง は数詞の後ろでも「〜の後で」になる（ชั้นสามหลังเลิกเรียน）ので、指示語が続くときだけ。
		afterNum := prev == "数詞" && w != "หลัง"
		nounThenDemo := isNominal(prev) && i+1 < len(words) && classifierFollowers[words[i+1]]
		if afterNum || nounThenDemo {
			result[i] = "類別詞"
		}
	}
}

// monkMeals は僧侶の食事を表す語。直前の ฉัน は一人称ではなく「（僧侶が）食べる」。
var monkMeals = map[string]bool{"เพล": true, "ภัตตาหาร": true, "จังหัน": true}

// tagMonkEat は ฉันเพล の ฉัน を動詞、เพล を名詞にする。pos_override は ฉัน を常に代名詞にする。
func tagMonkEat(words []string, result map[int]string) {
	for i, w := range words {
		if w != "ฉัน" || i+1 >= len(words) || !monkMeals[words[i+1]] {
			continue
		}
		result[i] = "動詞"
		result[i+1] = "名詞"
	}
}

// isNominal は名詞・固有名詞のラベルか。
func isNominal(tag string) bool {
	return tag == "名詞" || tag == "固有名詞"
}

// tagKhong は ของ を、後ろに持ち主が続くなら前置詞（〜の）、それ以外は名詞（物）にする。
// unigram は文脈を見ないので、ซื้อของ・ของหมด の ของ まで一律に前置詞にする。
func tagKhong(words []string, result map[int]string) {
	for i, w := range words {
		if w != "ของ" {
			continue
		}
		next, nextTag := "", ""
		if i+1 < len(words) {
			next, nextTag = words[i+1], result[i+1]
		}
		afterVerb := i > 0 && result[i-1] == "動詞"
		switch {
		case khongThingFollowers[next]:
			result[i] = "名詞"
		case nextTag == "代名詞":
			// เดินทางของฉัน: 動詞の直後でも代名詞が続けば持ち主。
			result[i] = "前置詞"
		case isNominal(nextTag) && !afterVerb:
			result[i] = "前置詞"
		default:
			result[i] = "名詞"
		}
	}
}

// khongThingFollowers は直後に来ると ของ が「物」になる語（ของชิ้นนี้・ของที่ซื้อ）。
var khongThingFollowers = map[string]bool{
	"ที่": true, "ชิ้น": true, "อัน": true, "นี้": true, "นั้น": true, "พวกนี้": true, "พวกนั้น": true,
}

// thiiClauseHeads は直後の ที่ が節を導く語（ตามที่พี่สอน・ตอนที่แมวอ้อน・ที่ที่คนมาเจอกัน・ก่อนที่จุดจบจะมาถึง）。
var thiiClauseHeads = map[string]bool{
	"ตาม": true, "ตอน": true, "ครั้ง": true, "ทุกครั้ง": true, "วัน": true, "เวลา": true, "ที่": true, "ก่อน": true,
}

// tagThii は場所を示す ที่（ที่โต๊ะ）を前置詞にする。関係節の ที่ は代名詞のまま残す。
// 名詞が前にあり、後ろが「名詞＋動詞」なら関係節（ร้านที่คนรู้จักแนะนำ）とみなす。
func tagThii(words []string, result map[int]string) {
	for i, w := range words {
		if w != "ที่" || i+1 >= len(words) || !isNominal(result[i+1]) {
			continue
		}
		if i > 0 && thiiClauseHeads[words[i-1]] {
			continue
		}
		afterNoun := i > 0 && (isNominal(result[i-1]) || result[i-1] == "限定詞")
		beforeVerb := i+2 < len(words) && (result[i+2] == "動詞" || result[i+2] == "助動詞")
		if !(afterNoun && beforeVerb) {
			result[i] = "前置詞"
		}
	}
}

// auxVerbs は動詞の直後で方向・継続・完了を添える語。
// unigram は文脈を見ないので、ไป を一律に副詞にする（prod プールで 11/553 語）。
var auxVerbs = map[string]bool{
	"ไป": true, "มา": true, "อยู่": true, "ขึ้น": true, "ลง": true, "ขึ้นมา": true, "ออกมา": true,
}

// preVerbs は後ろに本動詞を取る語。จะไป・อยากไป の ไป は本動詞なので助動詞にしない。
var preVerbs = map[string]bool{
	"จะ": true, "กำลัง": true, "ต้อง": true, "ควร": true, "คง": true, "อาจ": true, "เคย": true,
	"ได้": true, "อยาก": true, "ชอบ": true, "ช่วย": true, "ลอง": true, "เริ่ม": true, "เพิ่ง": true, "ยัง": true,
}

// tagAuxVerbs は auxVerbs の語を、動詞・助動詞・形容詞（ดีขึ้น・มากไป）の直後なら助動詞、
// それ以外は動詞にする。
func tagAuxVerbs(words []string, result map[int]string) {
	for i, w := range words {
		if !auxVerbs[w] {
			continue
		}
		prev := ""
		if i > 0 {
			prev = result[i-1]
		}
		if (prev == "動詞" || prev == "助動詞" || prev == "形容詞" || (i > 0 && words[i-1] == "มาก")) && !(i > 0 && preVerbs[words[i-1]]) {
			result[i] = "助動詞"
		} else {
			result[i] = "動詞"
		}
	}
}

func tagWordsBase(words []string) (map[int]string, error) {
	result := map[int]string{}
	if len(words) == 0 {
		return result, nil
	}

	p, err := loadProjectPOS()
	if err != nil {
		return nil, err
	}

	// 1. _POS_OVERRIDE と 2. ADJECTIVES
	unresolvedIdx := make([]int, 0, len(words))
	for i, w := range words {
		if tag, ok := p.override[w]; ok && tag != "" {
			result[i] = mapTag(p, tag)
		} else if p.adjectives[w] {
			result[i] = "形容詞"
		} else if tag := p.lexicon[w]; tag != "" {
			result[i] = mapTag(p, tag)
		} else {
			unresolvedIdx = append(unresolvedIdx, i)
		}
	}
	if len(unresolvedIdx) == 0 {
		return result, nil
	}

	// 3. unigram/tud — 未知語には空文字が返るので、埋まった分だけ採用する
	targets := make([]string, len(unresolvedIdx))
	for k, i := range unresolvedIdx {
		targets[k] = words[i]
	}
	var still []int
	tags, err := POSTagSeq(targets, "tud")
	if err != nil {
		// Python 側は例外を握り潰して全件を次段へ送る（nlp.py:191-193）
		still = unresolvedIdx
	} else {
		for k, i := range unresolvedIdx {
			tag := ""
			if k < len(tags) {
				tag = tags[k][1]
			}
			if tag != "" {
				result[i] = mapTag(p, tag)
			} else {
				still = append(still, i)
			}
		}
	}
	if len(still) == 0 {
		return result, nil
	}

	// 3.5 辞書に無い複合語（ถ่ายรูป・ถุงเท้า）は頭の語の品詞を使う。
	// perceptron は未知語に 前置詞・接続詞・固有名詞 を当て推量で付ける。
	still = tagCompoundHeads(p, words, still, result)
	if len(still) == 0 {
		return result, nil
	}

	// 4. perceptron/orchid_ud — 文脈判定のため全単語を渡す（nlp.py:199）
	ptags, err := POSTagSeq(words, "orchid_ud")
	if err != nil {
		// Python 側は握り潰して埋めずに返す（nlp.py:204-205）
		return result, nil
	}
	for _, i := range still {
		if i < len(ptags) {
			result[i] = mapTag(p, ptags[i][1])
		}
	}
	return result, nil
}

// mapTag は _POS_TAG_MAP.get(tag, tag) 相当。
func mapTag(p *projectPOS, tag string) string {
	if v, ok := p.tagMap[tag]; ok {
		return v
	}
	return tag
}

// tagCompoundHeads は still の語を辞書で分け、頭の語が引ければその品詞を付ける。
// 引けなかったインデックスを返す。
func tagCompoundHeads(p *projectPOS, words []string, still []int, result map[int]string) []int {
	t, err := loadPOS()
	if err != nil {
		return still
	}
	var rest []int
	for _, i := range still {
		parts, err := TokenizeWords(words[i])
		if err != nil || len(parts) < 2 {
			rest = append(rest, i)
			continue
		}
		head, last := parts[0], parts[len(parts)-1]
		switch {
		case last == "นี้" || last == "นั้น" || last == "ไหน":
			// เย็นนี้・ร้านนี้ は名詞句。頭の語（เย็น=形容詞）を取らない。
			result[i] = "名詞"
		case auxVerbs[head]:
			// ไปทำงาน の ไป を unigram に引かせると副詞になる。
			result[i] = "動詞"
		case head == "อย่าง":
			result[i] = "副詞"
		case head == "ที่":
			rest = append(rest, i)
		case p.override[head] != "":
			result[i] = mapTag(p, p.override[head])
		case p.adjectives[head]:
			result[i] = "形容詞"
		case p.lexicon[head] != "":
			result[i] = mapTag(p, p.lexicon[head])
		case t.tud[head] != "":
			result[i] = mapTag(p, t.tud[head])
		default:
			rest = append(rest, i)
		}
	}
	return rest
}

// InLexicon は word の品詞が pos_lexicon.json で決まっているか。
// poolretag が、付け直してよい語かを見分けるのに使う。
func InLexicon(word string) bool {
	p, err := loadProjectPOS()
	if err != nil {
		return false
	}
	return p.override[word] == "" && !p.adjectives[word] && p.lexicon[word] != ""
}
