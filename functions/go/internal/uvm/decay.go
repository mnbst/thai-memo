package uvm

// DecayPerDay は dailyBatch が全登録語の P に毎日かける減衰幅。
//
// key_word の候補が未出題語（UVM 未登録 or P=0）で埋まらなくなると、
// GetSessionWords は last_seen の古い既習語から選ぶ（selectUnknown）。
//
// 休眠日数（last_seen からの日数）で速める案は採らない。語彙スコアの走査帯
// ごと P が沈み、未受験者の estimated_vocab が sync のたびに 50 ずつ崩れる
// （真値350・60日休眠で戻った翌週に 0。TestIdleReturn）。
//
// 0.001 だと、まとめクイズ 1 問正解の P=0.618 が最後の回答から 198 日で
// cutoff(0.42) を割り、真値350・未受験・120日休眠で戻った日に 357→176 と
// 崩れた（確認クイズの正解で P を上げなくなってから表に出た）。0.0006 なら
// 330 日持ち、不正解で PFloor に落ちた語も 13 日以内の 2 回正解で P>0.5 に
// 戻る。並び順に使うだけなので、幅を小さくしても目的は変わらない。
const DecayPerDay = 0.0006

// DecayP は1日分の減衰後の P。
//
// 下限は PFloor。ここだけ 0 にすると、間違えた語が 150 日かけて PFloor の
// 下へ沈み、「2 回連続正解で P>0.5 に戻る」保証が崩れる（PFloor のコメントを参照）。
func DecayP(p float64) float64 {
	if p <= PFloor {
		return p
	}
	return max(PFloor, p-DecayPerDay)
}
