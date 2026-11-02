package thainlp

import (
	"encoding/json"
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
		projData = &projectPOS{tagMap: f.TagMap, override: f.Override, adjectives: adj}
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
	return result, nil
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

// tagAuxVerbs は auxVerbs の語を、動詞（または助動詞）の直後なら助動詞、それ以外は動詞にする。
func tagAuxVerbs(words []string, result map[int]string) {
	for i, w := range words {
		if !auxVerbs[w] {
			continue
		}
		prev := ""
		if i > 0 {
			prev = result[i-1]
		}
		if (prev == "動詞" || prev == "助動詞") && !preVerbs[words[i-1]] {
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
		case t.tud[head] != "":
			result[i] = mapTag(p, t.tud[head])
		default:
			rest = append(rest, i)
		}
	}
	return rest
}
