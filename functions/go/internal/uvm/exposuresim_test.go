package uvm

import "testing"

// syncOnce は sync 1 回ぶんの estimated_vocab の更新を再現する。
func syncOnce(pByRank map[int]float64, est, tested int) int {
	var entries []RankedP
	for rank, p := range pByRank {
		if rank >= max(tested, est-50) && rank < est+51 {
			entries = append(entries, RankedP{Rank: rank, P: p})
		}
	}
	return max(0, EstimateVocab(entries, est, tested))
}

// 例文生成だけを繰り返す。露出で P を動かさないので、いくら例文を作っても
// 語彙スコアは 1 も動かないこと。
//
// 露出で P を上げていた頃は ExposureP に上限が無く、同じ語が 6 回出るだけで
// P>0.5 になって knownMaxRank に昇格し、クイズ 0 問でスコアが伸びていた
// （400文で +68、800文で +154）。
func TestExposureDoesNotMoveVocab(t *testing.T) {
	for _, tested := range []int{0, 100, 250} {
		est := tested
		pByRank := map[int]float64{}

		for round := 0; round < 800; round++ {
			// key_word 帯から P 最小の語を選び、例文を作る（＝露出）
			lo, hi := ScanBand(max(est-tested, 0))
			lo, hi = lo+tested, hi+tested
			best, bestP := -1, 2.0
			for rank := lo; rank <= hi; rank++ {
				p, ok := pByRank[rank]
				if !ok {
					p = NewWordP
				}
				if p < bestP {
					best, bestP = rank, p
				}
			}
			// 未登録語は NewWordP で新規作成。既存語は P を変えない。
			if _, ok := pByRank[best]; !ok {
				pByRank[best] = NewWordP
			}

			est = syncOnce(pByRank, est, tested)
			if est != tested {
				t.Fatalf("tested=%d: 例文 %d 本目でスコアが動いた: %d（期待 %d）",
					tested, round+1, est, tested)
			}
		}
	}
}

// まとめクイズで正解して伸びたスコアが、そのあと例文を作り続けても
// 下がらないこと（新規作成される P=0.1 の語に引き戻されない）。
func TestVocabHoldsAfterQuiz(t *testing.T) {
	const tested = 250
	pByRank := map[int]float64{}
	for _, off := range []int{20, 25, 30, 35, 40} {
		pByRank[tested+off] = 0.55 // まとめクイズ全問正解
	}

	est := tested
	for i := 0; i < 30; i++ { // 目的地まで歩く
		est = syncOnce(pByRank, est, tested)
	}
	if est != tested+40 {
		t.Fatalf("到達点が違う: %d（期待 %d）", est, tested+40)
	}

	peak := est
	for round := 0; round < 500; round++ { // そのあと例文を作り続ける
		lo, hi := ScanBand(max(est-tested, 0))
		lo, hi = lo+tested, hi+tested
		for rank := lo; rank <= hi; rank++ {
			if _, ok := pByRank[rank]; !ok {
				pByRank[rank] = NewWordP
				break
			}
		}
		est = syncOnce(pByRank, est, tested)
		if est != peak {
			t.Fatalf("例文 %d 本目でスコアが動いた: %d（期待 %d）", round+1, est, peak)
		}
	}
	t.Logf("測定250 → まとめクイズ正解で %d に到達し、例文500本でも %d のまま", peak, est)
}
