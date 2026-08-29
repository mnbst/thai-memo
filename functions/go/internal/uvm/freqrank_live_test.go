package uvm

import (
	"context"
	"os"
	"testing"
)

// TestFreqRankIsContiguous は GCS 上の freq_rank に穴が無いことを確かめる。
//
// uvm.moving_avg は「rank に穴はない」前提で書かれている。穴があると
// その rank は UVM 登録済みでも常に UnknownWordP として数えられ、
// 周辺の平均習熟度が実態より低く出る。
func TestFreqRankIsContiguous(t *testing.T) {
	if os.Getenv("LIVE_FIRESTORE_TEST") == "" {
		t.Skip("LIVE_FIRESTORE_TEST が未設定")
	}
	fr, err := GetFreqRank(context.Background(), os.Getenv("GCLOUD_PROJECT"))
	if err != nil {
		t.Fatal(err)
	}
	if len(fr) == 0 {
		t.Fatal("freq_rank が空")
	}

	minR, maxR := 1<<31, 0
	seen := map[int]bool{}
	for _, r := range fr {
		seen[r] = true
		if r < minR {
			minR = r
		}
		if r > maxR {
			maxR = r
		}
	}

	var gaps []int
	for r := minR; r <= maxR; r++ {
		if !seen[r] {
			gaps = append(gaps, r)
		}
	}

	t.Logf("%d語 rank %d..%d", len(fr), minR, maxR)
	if minR != 1 {
		t.Errorf("最小 rank が 1 でない: %d", minR)
	}
	if len(gaps) > 0 {
		show := gaps
		if len(show) > 20 {
			show = show[:20]
		}
		t.Errorf("欠番が %d 件ある: %v", len(gaps), show)
	}
	if maxR != len(fr) {
		t.Errorf("最大 rank %d と語数 %d が一致しない", maxR, len(fr))
	}
}
