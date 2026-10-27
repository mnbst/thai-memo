package uvm

import (
	"fmt"
	"sort"
	"testing"
)

// TestCeilingGrowth は語彙テストの上限（3000）に届く層の伸びを比べる。
//
// 前方幅は est が上がるほど狭まり、測定値から 60 上がると 8 に固定される
// （ScanBand）。上級者は 1 日 5 語 × 前方 8 ランクでしか境界が進まないので、
// 真値が上限より上にあると 90 日でも届かない。前方幅を est に比例させる案と、
// 上限到達者の開始値を引き上げる案を、真値と世界側の推測率・slip を振って見る。
func TestCeilingGrowth(t *testing.T) {
	if testing.Short() {
		t.Skip("シミュレーション")
	}
	type variant struct {
		name string
		tune func(*simUser)
	}
	variants := []variant{
		{"旧現行", func(u *simUser) { u.noCeilingScale = true }},
		{"現行（上限到達のみ1.5%）", nil},
		{"前方 est×1%", func(u *simUser) { u.aheadScale = 0.01 }},
		{"前方 est×2%", func(u *simUser) { u.aheadScale = 0.02 }},
		{"前方 est×3%", func(u *simUser) { u.aheadScale = 0.03 }},
		{"上限到達は3500開始", func(u *simUser) { u.startEst = 3500 }},
		{"上限到達のみ est×1%", func(u *simUser) { u.aheadScale, u.ceilingOnly = 0.01, true }},
		{"上限到達のみ est×1.5%", func(u *simUser) { u.aheadScale, u.ceilingOnly = 0.015, true }},
		{"上限到達のみ est×2%", func(u *simUser) { u.aheadScale, u.ceilingOnly = 0.02, true }},
	}
	worlds := []struct {
		name        string
		guess, slip float64
	}{
		{"推測0.25/slip0", 0.25, 0},
		{"推測0.45/slip0.10", 0.45, 0.10},
	}
	truths := []int{300, 1000, 2000, 3000, 3500, 4500, 6000}
	const trials = 12

	for _, w := range worlds {
		t.Logf("=== 世界: %s（受験あり・まとめクイズあり、%d 試行の中央値）", w.name, trials)
		t.Logf("%-20s %s", "案", header(truths))
		for _, v := range variants {
			row := ""
			for _, truth := range truths {
				var d30, d90, bad, known []int
				for s := 0; s < trials; s++ {
					out, u := runCellUser(s+1, truth, true, true, 90, func(u *simUser) {
						u.worldGuess, u.worldSlip = w.guess, w.slip
						if v.tune != nil {
							v.tune(u)
						}
					})
					d30 = append(d30, out[30])
					d90 = append(d90, out[90])
					b, k := falseKnown(u)
					bad, known = append(bad, b), append(known, k)
				}
				row += fmt.Sprintf(" %5d/%5d(%3d%%)", median(d30), median(d90),
					100*sum(bad)/max(1, sum(known)))
			}
			t.Logf("%-20s%s", v.name, row)
		}
	}
	t.Log("各セル: d30/d90(誤既知率)。誤既知率 = P>0.5 の語のうち実際は知らない語の割合")
}

func header(truths []int) string {
	h := ""
	for _, tr := range truths {
		h += fmt.Sprintf(" %17s", fmt.Sprintf("真値%d", tr))
	}
	return h
}

func median(xs []int) int {
	s := append([]int(nil), xs...)
	sort.Ints(s)
	return s[len(s)/2]
}

func sum(xs []int) int {
	t := 0
	for _, x := range xs {
		t += x
	}
	return t
}

// TestFlatAhead は前方幅の逓減をやめ、全スコアで一定幅にした場合を比べる。
// 受験者・未受験者の両方、世界側の推測率と slip を振る。
func TestFlatAhead(t *testing.T) {
	if testing.Short() {
		t.Skip("シミュレーション")
	}
	widths := []int{0, 8, 12, 16, 20, 30}
	worlds := []struct {
		name        string
		guess, slip float64
	}{
		{"推測0.25/slip0", 0.25, 0},
		{"推測0.45/slip0.10", 0.45, 0.10},
	}
	truths := []int{150, 300, 700, 1500, 3000, 4500, 6000}
	const trials = 12
	for _, tested := range []bool{true, false} {
		for _, w := range worlds {
			t.Logf("=== 受験=%v 世界: %s（d90 の中央値）", tested, w.name)
			t.Logf("%-8s %s", "前方幅", header(truths))
			for _, width := range widths {
				row := ""
				for _, truth := range truths {
					var d90 []int
					for s := 0; s < trials; s++ {
						out, _ := runCellUser(s+1, truth, tested, true, 90, func(u *simUser) {
							u.worldGuess, u.worldSlip = w.guess, w.slip
							u.aheadOverride = width
							u.noCeilingScale = true
						})
						d90 = append(d90, out[90])
					}
					row += fmt.Sprintf(" %17d", median(d90))
				}
				name := fmt.Sprint(width)
				if width == 0 {
					name = "現行"
				}
				t.Logf("%-8s%s", name, row)
			}
		}
	}
}

// TestAheadScaleByBand は前方幅を est に比例させる率を真値ごとに掃引し、
// d90 の誤差が最小になる率を帯ごとに選ぶ。
//
// 誤差は世界 2 通り（推測0.25/slip0 と 推測0.45/slip0.10）の d90 中央値 −
// 真値。最適は |誤差| の大きいほうが最小になる率（どちらの世界でも外さない）。
// 前方幅は max(現行, est×率)。率 0 は現行。
func TestAheadScaleByBand(t *testing.T) {
	if testing.Short() {
		t.Skip("シミュレーション")
	}
	scales := []float64{0, 0.005, 0.01, 0.015, 0.02, 0.03, 0.04}
	worlds := [][2]float64{{0.25, 0}, {0.45, 0.10}}
	truths := []int{150, 300, 500, 700, 1000, 1500, 2000, 2500, 3000, 3500, 4500, 6000}
	const trials = 10
	for _, tested := range []bool{true, false} {
		t.Logf("=== 受験=%v（セル: 世界A/世界B の d90 誤差、* が最適）", tested)
		h := fmt.Sprintf("%-6s", "真値")
		for _, sc := range scales {
			h += fmt.Sprintf(" %13s", fmt.Sprintf("%.1f%%", sc*100))
		}
		t.Log(h)
		for _, truth := range truths {
			errs := make([][2]int, len(scales))
			best, bestWorst := 0, 1<<30
			for i, sc := range scales {
				for wi, w := range worlds {
					var d90 []int
					for s := 0; s < trials; s++ {
						out, _ := runCellUser(s+1, truth, tested, true, 90, func(u *simUser) {
							u.worldGuess, u.worldSlip = w[0], w[1]
							u.aheadScale = sc
							u.noCeilingScale = true
						})
						d90 = append(d90, out[90])
					}
					errs[i][wi] = median(d90) - truth
				}
				worst := max(abs(errs[i][0]), abs(errs[i][1]))
				if worst < bestWorst {
					best, bestWorst = i, worst
				}
			}
			row := fmt.Sprintf("%-6d", truth)
			for i := range scales {
				mark := " "
				if i == best {
					mark = "*"
				}
				row += fmt.Sprintf(" %12s%s", fmt.Sprintf("%+d/%+d", errs[i][0], errs[i][1]), mark)
			}
			t.Log(row)
		}
	}
}

func abs(x int) int {
	if x < 0 {
		return -x
	}
	return x
}

func TestKeyWordBand(t *testing.T) {
	ceiling := TestStages[len(TestStages)-1].High
	for _, c := range []struct {
		est, tested, low, high int
	}{
		{0, 0, 0, 20},                             // 未受験・新規
		{500, 0, 450, 508},                        // 未受験は ScanBand そのまま
		{1500, 1200, 1450, 1508},                  // 上限未満の受験者は平行移動だけ
		{ceiling, ceiling, ceiling, ceiling + 45}, // 上限到達: 3000×1.5%
		{ceiling + 1000, ceiling, ceiling + 950, ceiling + 1000 + 60}, // 4000×1.5%
	} {
		low, high := KeyWordBand(c.est, c.tested)
		if low != c.low || high != c.high {
			t.Errorf("KeyWordBand(%d, %d) = [%d, %d], want [%d, %d]",
				c.est, c.tested, low, high, c.low, c.high)
		}
	}
}
