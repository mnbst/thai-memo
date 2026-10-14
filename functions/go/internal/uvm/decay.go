package uvm

// DecayPerDay は dailyBatch が全登録語の P に毎日かける減衰幅。
//
// key_word の候補が未出題語（UVM 未登録 or P=0）で埋まらなくなると、
// GetSessionWords は 1-p 重み（UnknownWeights）にフォールバックして既習語から
// 引き直す。P を毎日減衰させておくと、そのとき放置された語が
// 復習されたばかりの語より優先される。
//
// 休眠日数（last_seen からの日数）で速める案は採らない。語彙スコアの走査帯
// ごと P が沈み、未受験者の estimated_vocab が sync のたびに 50 ずつ崩れる
// （真値350・60日休眠で戻った翌週に 0。TestIdleReturn）。
const DecayPerDay = 0.001

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
