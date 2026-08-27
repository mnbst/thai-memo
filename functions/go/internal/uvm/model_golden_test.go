package uvm

import (
	"encoding/json"
	"math"
	"os"
	"strconv"
	"testing"
)

// goldenPath は functions/python/scripts/uvm_golden/gen_golden.py の出力。
// uvm.py を変えたら再生成すること。
const goldenPath = "../../testdata/python/uvm_golden/golden.json"

type goldenFile struct {
	UpdateP []struct {
		P              float64 `json:"p"`
		Correct        bool    `json:"correct"`
		QuizAttempts   int     `json:"quiz_attempts"`
		Rank           *int    `json:"rank"`
		HintMultiplier float64 `json:"hint_multiplier"`
		Want           float64 `json:"want"`
	} `json:"update_p"`
	MovingAvg []struct {
		WordsByRank map[string]float64 `json:"words_by_rank"`
		Center      int                `json:"center"`
		Window      int                `json:"window"`
		Want        float64            `json:"want"`
	} `json:"moving_avg"`
	EstimateVocab []struct {
		Entries []struct {
			Rank int     `json:"rank"`
			P    float64 `json:"p"`
		} `json:"entries"`
		Center int `json:"center"`
		Want   int `json:"want"`
	} `json:"estimate_vocab"`
}

func loadGolden(t *testing.T) *goldenFile {
	t.Helper()
	b, err := os.ReadFile(goldenPath)
	if err != nil {
		t.Fatalf("golden を読めない（gen_golden.py を実行したか？）: %v", err)
	}
	var g goldenFile
	if err := json.Unmarshal(b, &g); err != nil {
		t.Fatal(err)
	}
	return &g
}

// 浮動小数は Python と Go で同じ IEEE754 演算をしているので、
// 演算順序を揃えてある限り完全一致するはず。許容差は丸め1ulp相当だけ見る。
const eps = 1e-12

func TestUpdatePMatchesPython(t *testing.T) {
	g := loadGolden(t)
	if len(g.UpdateP) == 0 {
		t.Fatal("ケースが空")
	}
	bad := 0
	for _, c := range g.UpdateP {
		got := UpdateP(c.P, c.Correct, c.QuizAttempts, c.Rank, c.HintMultiplier)
		if math.Abs(got-c.Want) > eps {
			if bad < 5 {
				t.Errorf("UpdateP(p=%v correct=%v attempts=%d rank=%v mult=%v) = %v, want %v",
					c.P, c.Correct, c.QuizAttempts, c.Rank, c.HintMultiplier, got, c.Want)
			}
			bad++
		}
	}
	if bad > 0 {
		t.Fatalf("%d/%d 件不一致", bad, len(g.UpdateP))
	}
	t.Logf("%d 件一致", len(g.UpdateP))
}

func TestMovingAvgMatchesPython(t *testing.T) {
	g := loadGolden(t)
	for i, c := range g.MovingAvg {
		m := make(map[int]float64, len(c.WordsByRank))
		for k, v := range c.WordsByRank {
			n, err := strconv.Atoi(k)
			if err != nil {
				t.Fatal(err)
			}
			m[n] = v
		}
		got := MovingAvg(m, c.Center, c.Window)
		if math.Abs(got-c.Want) > eps {
			t.Fatalf("case %d: MovingAvg = %v, want %v", i, got, c.Want)
		}
	}
	t.Logf("%d 件一致", len(g.MovingAvg))
}

func TestEstimateVocabMatchesPython(t *testing.T) {
	g := loadGolden(t)
	for i, c := range g.EstimateVocab {
		entries := make([]RankedP, 0, len(c.Entries))
		for _, e := range c.Entries {
			entries = append(entries, RankedP{Rank: e.Rank, P: e.P})
		}
		got := EstimateVocab(entries, c.Center)
		if got != c.Want {
			t.Fatalf("case %d (center=%d, %d entries): EstimateVocab = %d, want %d",
				i, c.Center, len(entries), got, c.Want)
		}
	}
	t.Logf("%d 件一致", len(g.EstimateVocab))
}
