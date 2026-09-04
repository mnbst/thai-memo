package uvm

import (
	"math/rand"
	"testing"
)

func rp(i int) *int { return &i }

// 混在した正誤でクイズを回したときの estimated_vocab の揺れ。
// maxDelta=0 は clamp 無し（撤廃後）、3 は撤廃前。
func jitter(seed int64, tested, maxDelta, rounds int, correctRate float64) []int {
	rnd := rand.New(rand.NewSource(seed))
	est := tested
	p := map[int]float64{}
	att := map[int]int{}
	var hist []int

	for r := 0; r < rounds; r++ {
		lo, hi := ScanBand(max(est-tested, 0))
		lo, hi = lo+tested, hi+tested
		// 5問: 帯の中からランダムに出題（既出も再出題される）
		for q := 0; q < 5; q++ {
			rank := lo + rnd.Intn(hi-lo+1)
			old, ok := p[rank]
			if !ok {
				old = NewWordP
			}
			p[rank] = UpdateP(old, rnd.Float64() < correctRate, att[rank], rp(rank), 1.0)
			att[rank]++
		}
		// クイズ5問 + 例文生成1 = sync 6回
		for s := 0; s < 6; s++ {
			var e []RankedP
			for rk, pv := range p {
				if rk >= max(tested, est-50) && rk < est+51 {
					e = append(e, RankedP{Rank: rk, P: pv})
				}
			}
			raw := EstimateVocab(e, est, tested)
			d := raw - est
			if maxDelta > 0 {
				d = max(-maxDelta, min(maxDelta, d))
			}
			est += d
		}
		hist = append(hist, est)
	}
	return hist
}

// 正誤が混在する現実的なクイズでの不変条件。
//
// 完全一致は成り立たない。UpdateP の α が絶対 rank に依存する
// （scale = RankScaleRef/(rank+RankScaleRef)）ため、高ランク帯にいる測定
// ユーザーほど 1 問あたりの P の伸びが小さいのはモデルの設計どおり。
//
// ここで固定するのは 2 つ。
//
//   - 測定値を 1 度も下回らない（シードごとに厳格に見る）
//   - 伸びが 0 スタートを上回らない（**平均で**見る）
//
// 伸びをシードごとに比べてはいけない。出題 rank 列が変わるだけで
// 0 スタート自身の伸びが 110〜181 のように振れるので、1 シードの差は
// 原点の効果ではなくただの分散になる。
func TestJitterOriginInvariants(t *testing.T) {
	const seeds = 20
	for _, rate := range []float64{0.9, 0.7, 0.5, 0.3} {
		baseSum := 0
		sum := map[int]int{}
		for seed := int64(1); seed <= seeds; seed++ {
			baseSum += jitter(seed, 0, 0, 40, rate)[39]
			for _, tested := range []int{100, 250, 500} {
				h := jitter(seed, tested, 0, 40, rate)
				for i, v := range h {
					if v < tested {
						t.Fatalf("rate=%.1f seed=%d tested=%d round=%d: 測定値を下回った (%d)",
							rate, seed, tested, i+1, v)
					}
				}
				sum[tested] += h[39] - tested
			}
		}
		baseAvg := float64(baseSum) / seeds
		for _, tested := range []int{100, 250, 500} {
			avg := float64(sum[tested]) / seeds
			// 原点をずらして得をしないこと。α の rank 依存で本来は
			// わずかに不利側に出る。
			if avg > baseAvg+2 {
				t.Errorf("rate=%.1f tested=%d: 平均の伸び %.1f が 0 スタート %.1f を上回った",
					rate, tested, avg, baseAvg)
			}
			t.Logf("rate=%.1f tested=%-3d 平均の伸び %.1f（0 スタート %.1f）",
				rate, tested, avg, baseAvg)
		}
	}
}
