package uvm

import "testing"

// P 更新則の比較。現行は「1問正解 +0.45 / 1問不正解 -0.02」という非対称で、
// まぐれ当たりで既知になった語を後から回収できない。不正解側を強めた場合と、
// 尤度比（ベイズ）に置き換えた場合で、
//
//   - estimated_vocab が真値からどれだけ上振れるか
//   - 「P>0.5 だが実際は知らない語（pKnow<0.5）」がどれだけ残るか
//
// を見る。シミュレータ側の実際の推測率は guessRate（ヒント無しで 0.25）のまま。
type updateRule struct {
	name string
	tune func(*simUser)
}

var updateRules = []updateRule{
	{"実装(g.35)", func(u *simUser) {}},
	{"旧α則", func(u *simUser) { u.alphaRule, u.newP = true, 0.1 }},
	{"旧α則+不正解×3", func(u *simUser) {
		u.alphaRule, u.newP, u.incorrectScale = true, 0.1, 3
	}},
	{"旧α則+不正解×5", func(u *simUser) {
		u.alphaRule, u.newP, u.incorrectScale = true, 0.1, 5
	}},
	{"g.25", func(u *simUser) { u.bayesGuess, u.bayesSlip = 0.25, 0.15 }},
	{"g.45", func(u *simUser) { u.bayesGuess, u.bayesSlip = 0.45, 0.15 }},
	{"g.35 s.25", func(u *simUser) { u.bayesGuess, u.bayesSlip = 0.35, 0.25 }},
	{"g.35 s.08", func(u *simUser) { u.bayesGuess, u.bayesSlip = 0.35, 0.08 }},
}

// falseKnown は P>0.5 の語のうち、実際には知らない（pKnow<0.5）語の数と総数。
func falseKnown(u *simUser) (bad, known int) {
	for r, w := range u.words {
		if w.p > 0.5 {
			known++
			if pKnow(r, u.truth) < 0.5 {
				bad++
			}
		}
	}
	return
}

// TestUpdateRuleWorld は「世界側の推測率と slip」を振って更新則を比較する。
//
// 実際の推測率 g_true が本当に低い（＝穴埋めが難しく、まぐれで当たらない）なら
// 1問正解での大きな上昇は正当化される。逆に g_true が高いなら現行は上振れる。
// slip は既知語を落とす確率で、不正解側を強める案の副作用がここに出る。
func TestUpdateRuleWorld(t *testing.T) {
	trials := 20
	worlds := []struct {
		name        string
		guess, slip float64
	}{
		{"g_true=.25 slip=.10", 0.25, 0.10},
		{"g_true=.08 slip=.10", 0.08, 0.10},
		{"g_true=.50 slip=.10", 0.50, 0.10},
	}
	for _, w := range worlds {
		for _, truth := range []int{150, 700} {
			t.Logf("=== %s / 受験 真値%d ===", w.name, truth)
			t.Logf("%-18s %6s %6s %8s %14s", "更新則", "d30", "d90", "d90誤差", "誤既知/既知")
			for _, m := range updateRules {
				d30, d90, bad, known := 0, 0, 0, 0
				for s := range trials {
					r, u := runCellUser(s+1, truth, true, true, 90, func(su *simUser) {
						su.worldGuess, su.worldSlip = w.guess, w.slip
						m.tune(su)
					})
					d30 += r[30]
					d90 += r[90]
					b, k := falseKnown(u)
					bad += b
					known += k
				}
				avg90 := d90 / trials
				t.Logf("%-16s %6d %6d %+8d %8.1f/%.1f", m.name,
					d30/trials, avg90, avg90-truth,
					float64(bad)/float64(trials), float64(known)/float64(trials))
			}
		}
	}
}

func TestUpdateRuleSweep(t *testing.T) {
	trials := 20
	for _, tested := range []bool{false, true} {
		label := "未受験"
		if tested {
			label = "受験"
		}
		for _, truth := range []int{150, 350, 700} {
			t.Logf("=== %s 真値%d（まとめクイズあり）===", label, truth)
			t.Logf("%-18s %6s %6s %8s %14s", "更新則", "d30", "d90", "d90誤差", "誤既知/既知")
			for _, m := range updateRules {
				d30, d90, bad, known := 0, 0, 0, 0
				for s := range trials {
					r, u := runCellUser(s+1, truth, tested, true, 90, m.tune)
					d30 += r[30]
					d90 += r[90]
					b, k := falseKnown(u)
					bad += b
					known += k
				}
				avg90 := d90 / trials
				t.Logf("%-16s %6d %6d %+8d %8.1f/%.1f", m.name,
					d30/trials, avg90, avg90-truth,
					float64(bad)/float64(trials), float64(known)/float64(trials))
			}
		}
	}
}
