package uvm

import "testing"

// クイズ出題の下端 F の取り方で estimated_vocab が収束するかを見る。
// floorMode: "est"=現状(estimated_vocab), "tested"=修正後(測定値固定), "none"=0スタート
func runLoop(t *testing.T, tested int, floorMode string, rounds int) []int {
	est := tested
	pByRank := map[int]float64{} // 正解済み(P=0.55)の語
	var hist []int

	for round := 0; round < rounds; round++ {
		// key_word 帯（原点シフト後）
		lo, hi := ScanBand(max(est-tested, 0))
		lo, hi = lo+tested, hi+tested

		// 出題下端
		f := lo
		switch floorMode {
		case "est":
			f = max(lo, est)
		case "tested":
			f = max(lo, tested)
		}

		// 未回答のうち下から5語に正解
		n := 0
		for r := f; r <= hi && n < 5; r++ {
			if _, ok := pByRank[r]; !ok {
				pByRank[r] = 0.55
				n++
			}
		}

		// 1ラウンドで sync 6回（クイズ5問＋例文生成1）
		for s := 0; s < 6; s++ {
			var entries []RankedP
			for r, p := range pByRank {
				if r >= max(tested, est-50) && r < est+51 {
					entries = append(entries, RankedP{Rank: r, P: p})
				}
			}
			est = max(0, EstimateVocab(entries, est, tested))
		}
		hist = append(hist, est)
	}
	return hist
}

// TestQuizFloorLoop は、まとめクイズの出題下端を測定値に固定すると
// 「測定 M のユーザー」の estimated_vocab 軌道が「0 スタートのユーザー」の
// 軌道と平行移動を除いて一致することを確認する。
//
// 下端を estimated_vocab にすると自己参照の正のフィードバックになり、
// 同条件で 2 倍以上の速度で発散する（quizKeyWordFilter のコメントを参照）。
func TestQuizFloorLoop(t *testing.T) {
	const rounds = 40
	base := runLoop(t, 0, "none", rounds)

	for _, tested := range []int{100, 250} {
		got := runLoop(t, tested, "tested", rounds)
		for i := range base {
			if got[i] != base[i]+tested {
				t.Errorf("tested=%d round=%d: got %d, want %d（0スタート %d + %d）",
					tested, i+1, got[i], base[i]+tested, base[i], tested)
				break
			}
		}
	}

	// 下端を estimated_vocab にした場合は発散する（回帰の目印）。
	runaway := runLoop(t, 250, "est", rounds)
	if runaway[rounds-1]-250 <= base[rounds-1] {
		t.Errorf("floor=estimated_vocab が発散していない: %d（0スタート %d）",
			runaway[rounds-1]-250, base[rounds-1])
	}
	t.Logf("40ラウンド後の増分: 修正=%+d / 0スタート=%+d / 修正前=%+d",
		runLoop(t, 250, "tested", rounds)[rounds-1]-250, base[rounds-1],
		runaway[rounds-1]-250)
}
