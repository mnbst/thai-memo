package uvm

import (
	"math"
	"testing"
)

// 確認クイズ以外の回答は境界推定の母数に入る（IsGradedResult）。
// ヒント・例文レビューは α 側で既に弱めているので、母数からは外さない。
func TestIsGradedResult(t *testing.T) {
	cases := []struct {
		name     string
		quizType string
		result   Result
		want     bool
	}{
		{"まとめクイズ・ヒント無し", "review", Result{}, true},
		{"確認クイズ", "learning", Result{}, false},
		{"ヒント1段", "review", Result{HintLevel: 1}, true},
		{"ヒント2段", "review", Result{HintLevel: 2}, true},
		{"ヒント2段で不正解", "review", Result{HintLevel: 2}, true},
		{"例文レビュー由来", "review", Result{SentenceReviewed: true}, true},
		{"確認クイズはヒント無しでも外す", "learning", Result{HintLevel: 0}, false},
		{"quiz_type 未指定", "", Result{}, true},
	}
	for _, c := range cases {
		if got := IsGradedResult(c.quizType, c.result); got != c.want {
			t.Errorf("%s: IsGradedResult = %v, want %v", c.name, got, c.want)
		}
	}
}

// 採点区分を持たない既存 doc は母数に残す（移行中に母数が急減しない）。
func TestGradedFieldDefaultsToTrue(t *testing.T) {
	if !boolField(map[string]any{"p": 0.5}, "graded", true) {
		t.Error("graded の無い doc が母数から外れた")
	}
	if boolField(map[string]any{"graded": false}, "graded", true) {
		t.Error("graded=false の doc が母数に入った")
	}
}

// ResultEvidence は正誤で変わってはいけない。変わると「確認クイズは不正解だけ
// が母数に入る」ような結果依存の選別になり、境界推定に下方バイアスが乗る。
func TestResultEvidenceIgnoresOutcome(t *testing.T) {
	cases := []struct {
		name     string
		quizType string
		result   Result
		want     float64
	}{
		{"まとめクイズ・ヒント無し", "review", Result{}, 1.0},
		{"ヒント1段", "review", Result{HintLevel: 1}, 0.5},
		{"ヒント2段", "review", Result{HintLevel: 2}, 0.25},
		{"確認クイズ", "learning", Result{}, 0.1},
		{"例文レビュー", "review", Result{SentenceReviewed: true}, 0.1},
		{"ヒント1段+例文レビュー", "review", Result{HintLevel: 1, SentenceReviewed: true}, 0.05},
	}
	for _, c := range cases {
		for _, correct := range []bool{true, false} {
			r := c.result
			r.IsCorrect = correct
			if got := ResultEvidence(c.quizType, r); math.Abs(got-c.want) > 1e-9 {
				t.Errorf("%s (correct=%v): ResultEvidence = %v, want %v",
					c.name, correct, got, c.want)
			}
		}
	}
}

// UpdateP は正解でだけ P を上げ、不正解では必ず下げる（片方向にならない）。
// g > 1-s になると尤度比が反転して「正解で下がる」ため、GuessRate は
// MaxGuessRate < 1-BayesSlip で頭打ちにしてある。
func TestUpdatePDirection(t *testing.T) {
	if MaxGuessRate >= 1-BayesSlip {
		t.Fatalf("MaxGuessRate(%v) は 1-BayesSlip(%v) 未満でなければならない",
			MaxGuessRate, 1-BayesSlip)
	}
	for _, hint := range []int{0, 1, 2, 5} {
		// PFloor が UpdateP の下限なので、それ未満の P は本番では出てこない。
		for _, p := range []float64{PFloor, NewWordP, 0.5, 0.95} {
			if up := UpdateP(p, true, hint, 1); up <= p {
				t.Errorf("hint=%d p=%v: 正解で上がらない (%v)", hint, p, up)
			}
			dn := UpdateP(p, false, hint, 1)
			// 下限に張り付いている語は不正解でも動かない（これが「しつこい
			// 再出題」を止めている）。それ以外は必ず下がる。
			if p <= PFloor {
				if dn != PFloor {
					t.Errorf("hint=%d p=%v: 不正解で下限を割った (%v)", hint, p, dn)
				}
				continue
			}
			if dn >= p {
				t.Errorf("hint=%d p=%v: 不正解で下がらない (%v)", hint, p, dn)
			}
		}
	}
	// prior から 1 問正解すれば cutoff(0.42) を越える（未受験の伸びの前提）。
	if got := UpdateP(NewWordP, true, 0, 1); got <= 0.42 {
		t.Errorf("prior から 1 問正解で cutoff を越えない: %v", got)
	}
	// ヒントを出すほど正解の情報量は落ちる。
	prev := 1.0
	for _, hint := range []int{0, 1, 2} {
		got := UpdateP(NewWordP, true, hint, 1)
		if got >= prev {
			t.Errorf("hint=%d の正解が hint=%d より効いている: %v", hint, hint-1, got)
		}
		prev = got
	}
	// weight は証拠の重み。確認クイズ（0.1）はほとんど動かさない。
	// 21 ランクの窓の平均に効くのは 1/21 なので、prior + 0.03 以内に収まれば
	// 単独で cutoff を割らせる/越えさせることはない。
	if got := UpdateP(NewWordP, true, 0, LearningCorrectMultiplier); got > NewWordP+0.03 {
		t.Errorf("確認クイズ 1 問で動きすぎ: %v", got)
	}
}

// 移行: evidence を持たない既存 doc は graded から導いて挙動を変えない。
func TestEvidenceFieldMigration(t *testing.T) {
	cases := []struct {
		name string
		data map[string]any
		want float64
	}{
		{"evidence あり", map[string]any{"evidence": 0.6}, 0.6},
		{"evidence 0 は 0 のまま", map[string]any{"evidence": 0.0, "graded": true}, 0},
		{"graded=true の旧 doc", map[string]any{"graded": true}, 1},
		{"graded=false の旧 doc（露出のみ）", map[string]any{"graded": false}, 0},
		{"どちらも無い最古の doc", map[string]any{"p": 0.5}, 1},
	}
	for _, c := range cases {
		if got := evidenceField(c.data); math.Abs(got-c.want) > 1e-9 {
			t.Errorf("%s: evidenceField = %v, want %v", c.name, got, c.want)
		}
	}
}

// TestUpdatePRecovery は「間違えた語も、ヒント無しで 2 回連続正解すれば
// 既知判定(P>0.5)へ戻る」ことを固定する。PFloor の存在理由そのもの。
//
// 下限が無かった頃は、間違え続けた語の P がいくらでも 0 に近づき、出題が
// 低 P 語優先なので同じ語が毎日出続けていた。
func TestUpdatePRecovery(t *testing.T) {
	const known = 0.5

	// どんな履歴の語でも、下限から 2 連続正解で既知へ戻る。
	starts := []float64{PFloor, 0.0, 1e-9, 0.05}
	for _, start := range starts {
		p := math.Max(start, PFloor) // 本番の P は必ず PFloor 以上
		p = UpdateP(p, true, 0, 1)
		if p > known {
			t.Errorf("start=%v: 1 問目で既知に戻ってしまう (%v)", start, p)
		}
		p = UpdateP(p, true, 0, 1)
		if p <= known {
			t.Errorf("start=%v: 2 連続正解で既知に戻らない (%v)", start, p)
		}
	}

	// 間違え続けても下限より下へは行かない。
	p := NewWordP
	for range 20 {
		p = UpdateP(p, false, 0, 1)
	}
	if p != PFloor {
		t.Errorf("20 連続不正解で下限に張り付かない: %v", p)
	}

	// prior から 1 問不正解 → 2 連続正解で既知へ戻る（体感の主経路）。
	p = UpdateP(NewWordP, false, 0, 1)
	p = UpdateP(p, true, 0, 1)
	p = UpdateP(p, true, 0, 1)
	if p <= known {
		t.Errorf("不正解1回のあと2連続正解で既知に戻らない: %v", p)
	}
}
