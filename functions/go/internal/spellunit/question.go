package spellunit

import "math/rand"

// Distractor は非語のダミー1件。Dim/Value は正解と違う次元とその値
// （＝選んでしまったときの「取り違え先」）。
type Distractor struct {
	Text  string
	Dim   Dim
	Value string
}

// distractorCount は1問のダミー数。
const distractorCount = 3

// Distractors は word の綴りを1次元だけ変えた**非語**のダミーを3件返す。
//
//   - 変異先は sylform_var に実在する音節形コードだけ。自由に字を足すと
//     「รรร」のような音節ですらない綴りが出る（非語であって非音節ではない）。
//   - BEST.dict にある綴りは実在語なので使わない。
//   - 見た目の長さを正解と揃える。揃えないと長さが手がかりになる。
//   - できるだけ違う次元から1件ずつ選ぶ（1問で3つの部品を切り分けられる）。
//     揃わないときだけ同じ次元から足す。
//
// rnd は呼び出しごとに変えること。毎回同じダミーを出すと、誤った綴りの
// 繰り返し露出になる。
func (ix *Index) Distractors(word string, rnd *rand.Rand) ([]Distractor, bool) {
	code, ok := ix.Lookup(word)
	if !ok {
		return nil, false
	}
	want := displayLen(word)

	byDim := map[Dim][]Distractor{}
	for _, d := range Dims {
		current := code.At(d)
		var cands []Distractor
		for _, value := range ix.values(d) {
			if value == current {
				continue
			}
			for _, form := range ix.spellings[code.With(d, value)] {
				if form == word || ix.realWord[form] || displayLen(form) != want {
					continue
				}
				cands = append(cands, Distractor{Text: form, Dim: d, Value: value})
			}
		}
		if len(cands) > 0 {
			rnd.Shuffle(len(cands), func(i, j int) { cands[i], cands[j] = cands[j], cands[i] })
			byDim[d] = cands
		}
	}

	order := append([]Dim(nil), Dims...)
	rnd.Shuffle(len(order), func(i, j int) { order[i], order[j] = order[j], order[i] })

	out := make([]Distractor, 0, distractorCount)
	used := map[string]bool{word: true}
	// まず次元を散らして1件ずつ。
	for _, d := range order {
		if len(out) >= distractorCount {
			break
		}
		for _, c := range byDim[d] {
			if used[c.Text] {
				continue
			}
			used[c.Text] = true
			out = append(out, c)
			break
		}
	}
	// 次元が3つ揃わなければ、残りを次元を問わず詰める。
	for _, d := range order {
		for _, c := range byDim[d] {
			if len(out) >= distractorCount {
				break
			}
			if used[c.Text] {
				continue
			}
			used[c.Text] = true
			out = append(out, c)
		}
	}
	if len(out) < distractorCount {
		return nil, false
	}
	rnd.Shuffle(len(out), func(i, j int) { out[i], out[j] = out[j], out[i] })
	return out, true
}

// Observation は1問から取れる部品ごとの証拠。
type Observation struct {
	// Unit は**正解側**の部品（この部品を見分けられたか）。
	Dim   Dim
	Value string
	// Correct は見分けられたか。
	Correct bool
	// ConfusedWith は取り違えた先の値（不正解のときだけ）。
	ConfusedWith string
}

// UnitID は Firestore のドキュメントID。
func (o Observation) UnitID() string { return UnitID(o.Dim, o.Value) }

// Observations は綴り4択の回答から部品ごとの証拠を取り出す。
//
// choices は出題した4択（正解を含む）。正解と1次元だけ違う選択肢が
// 「その部品を測った」ことを表す。正解なら測った部品すべてに正の証拠、
// 不正解なら選んだ選択肢の部品にだけ負の証拠を立てる（残りの部品に
// ついては何も分からない）。
func (ix *Index) Observations(
	word string, choices []string, selected string, correct bool,
) []Observation {
	code, ok := ix.Lookup(word)
	if !ok {
		return nil
	}

	tested := map[Dim]string{} // 次元 -> ダミー側の値
	for _, choice := range choices {
		if choice == word {
			continue
		}
		other, ok := ix.Lookup(choice)
		if !ok {
			continue
		}
		if d, value, ok := diffDim(code, other); ok {
			tested[d] = value
		}
	}
	if len(tested) == 0 {
		return nil
	}

	if !correct {
		other, ok := ix.Lookup(selected)
		if !ok {
			return nil
		}
		d, value, ok := diffDim(code, other)
		if !ok {
			return nil
		}
		return []Observation{{
			Dim: d, Value: code.At(d), Correct: false, ConfusedWith: value,
		}}
	}

	out := make([]Observation, 0, len(tested))
	for _, d := range Dims {
		if _, ok := tested[d]; !ok {
			continue
		}
		out = append(out, Observation{Dim: d, Value: code.At(d), Correct: true})
	}
	return out
}

// diffDim は2つのコードがちょうど1次元だけ違うとき、その次元と
// 相手側の値を返す。
func diffDim(correct, other Code) (Dim, string, bool) {
	var found Dim
	n := 0
	for _, d := range Dims {
		if correct.At(d) != other.At(d) {
			found = d
			n++
		}
	}
	if n != 1 {
		return 0, "", false
	}
	return found, other.At(found), true
}
