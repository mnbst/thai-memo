package spellunit

import "math"

// 部品ごとの P(見分けられる) の更新。uvm.UpdateP と同じ尤度比だが、
// 定数はこの形式専用に持つ。**uvm の値を流用しない**のは、推測率 g が
// 形式で違うため（uvm.BayesGuessTop=0.35 は穴埋めの4択で、周辺のタイ語から
// 絞れるぶん高く置いてある）。
//
// 綴り4択はダミー3件とも「実在しない綴り」なので、知らなければ本当に
// 4つが等確率になる。g は素の 0.25。
const (
	// GuessRate は知らなくても当たる確率 g。
	GuessRate = 0.25
	// Slip は見分けられるのに落とす確率 s。
	Slip = 0.15
	// PFloor は P の下限。0 にすると間違え続けた部品が戻れなくなる
	// （uvm.PFloor と同じ理由）。
	PFloor = 0.15
	// PMax は P の上限。
	PMax = 0.99
	// NewUnitP は未登録の部品の初期値。
	NewUnitP = 0.4
)

// UpdateP は部品の P を尤度比で更新する。
//
//	正解: LR = (1-s)/g = 3.4   不正解: LR = s/(1-g) = 0.2
//
// 正解の尤度比 3.4 は uvm の 2.43 より大きい。ダミーが全部非語で
// 「消去法で当てる」余地が無いぶん、1回の回答が持つ情報が多い。
func UpdateP(p float64, correct bool) float64 {
	p = math.Max(1e-6, math.Min(1-1e-6, p))
	lr := Slip / (1 - GuessRate)
	if correct {
		lr = (1 - Slip) / GuessRate
	}
	odds := p / (1 - p) * lr
	lower := math.Min(PFloor, p)
	return math.Max(lower, math.Min(PMax, odds/(1+odds)))
}
