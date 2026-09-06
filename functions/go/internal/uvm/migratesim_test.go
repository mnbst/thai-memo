package uvm

import "testing"

// TestUpdateRuleMigration は「旧 α 則で 90 日ぶん溜まった doc を引き継いで、
// 新実装（尤度比 + NewWordP=prior）に切り替えたらどうなるか」を見る。
//
// P は再計算しないので切替日そのものでは動かない。問題は、旧則が作った
// 「実際は知らないのに P>0.5 の語」（誤既知）が以後の不正解で回収され、
// estimated_vocab が下がりうること。ランキングに出る値なので下げ幅を測る。
//
// 比較対象は「旧則のまま 180 日回した場合」。
func TestUpdateRuleMigration(t *testing.T) {
	trials := 20
	for _, tested := range []bool{true, false} {
		label := "受験"
		if !tested {
			label = "未受験"
		}
		for _, truth := range []int{150, 350, 700} {
			t.Logf("=== %s 真値%d ===", label, truth)
			t.Logf("%-16s %5s %5s %5s %5s %5s %5s %12s",
				"", "d90", "d91", "d93", "d97", "d120", "d180", "誤既知/既知")
			for _, c := range []struct {
				name string
				tune func(*simUser)
			}{
				{"旧則のまま", func(u *simUser) {
					u.alphaRule, u.newP, u.totalDays = true, 0.1, 180
				}},
				{"d90で新実装へ", func(u *simUser) { u.alphaUntilDay = 90; u.totalDays = 180 }},
				{"最初から新実装", func(u *simUser) { u.totalDays = 180 }},
			} {
				sum := map[int]int{}
				bad, known := 0, 0
				for s := range trials {
					r, u := runCellUser(s+1, truth, tested, true, 180, c.tune)
					for _, d := range []int{90, 91, 93, 97, 120, 180} {
						sum[d] += r[d]
					}
					b, k := falseKnown(u)
					bad += b
					known += k
				}
				t.Logf("%-14s %5d %5d %5d %5d %5d %5d %6.1f/%.1f", c.name,
					sum[90]/trials, sum[91]/trials, sum[93]/trials, sum[97]/trials,
					sum[120]/trials, sum[180]/trials,
					float64(bad)/float64(trials), float64(known)/float64(trials))
			}
		}
	}
}
