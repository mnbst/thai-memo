package uvm

import (
	"context"
	"math"
	"testing"
)

// gradedEmb は rank が peak に近いほどテーマに似ている embedding スタブ。
// 類似度は cos(|rank-peak| * 0.01) なので peak で最大、離れるほど単調に下がる。
type gradedEmb struct {
	freqRank FreqRank
	peak     int
}

func (e gradedEmb) Embedding(word string) []float32 {
	r, ok := e.freqRank[word]
	if !ok {
		return nil
	}
	th := math.Abs(float64(r-e.peak)) * 0.01
	return []float32{float32(math.Cos(th)), float32(math.Sin(th))}
}

func (e gradedEmb) TopicEmbedding(context.Context, string) ([]float32, error) {
	return []float32{1, 0}, nil
}

func (e gradedEmb) FindBestTopic(context.Context, string, []string, int, float64) (string, error) {
	return "", nil
}

func testFreqRank(n int) FreqRank {
	fr := FreqRank{}
	for r := range n {
		fr[string(rune('あ'+r%80))+string(rune('ア'+r/80))] = r
	}
	return fr
}

// TestTopicFallbackStaysInBand は、テーマ一致語が帯内に無いときのフォールバックが
// 帯を出ないこと、既出を除いた中から一番近い語を選ぶこと、同じ語を繰り返さない
// ことを確かめる。
func TestTopicFallbackStaysInBand(t *testing.T) {
	freqRank := testFreqRank(600)
	const low, high = 250, 300
	// 一致のピークは帯の外（rank 100）。旧実装はここへ降りていた。
	emb := gradedEmb{freqRank: freqRank, peak: 100}
	topicEmb, _ := emb.TopicEmbedding(context.Background(), "x")

	band := BandCandidates(freqRank, low, high)
	if got := FilterCandidatesByTopic(emb, band, topicEmb); len(got) != 0 {
		t.Fatalf("閾値を超える語は無いはずなのに %d 件返った", len(got))
	}

	seen := map[string]bool{}
	var picks []int
	for range 5 {
		// 既出（UVM 登録済み）を落とす。GetSessionWords の zeroP と同じ扱い。
		var fresh []Candidate
		for _, c := range band {
			if !seen[c.Word] {
				fresh = append(fresh, c)
			}
		}
		got := ClosestToTopic(emb, fresh, topicEmb, 1)
		if len(got) != 1 {
			t.Fatalf("1 語返るはず: got %d", len(got))
		}
		c := got[0]
		if c.Rank < low || c.Rank > high {
			t.Fatalf("帯 [%d,%d] を出た: rank=%d", low, high, c.Rank)
		}
		if seen[c.Word] {
			t.Fatalf("既出を除いたのに同じ語を返した: %s", c.Word)
		}
		seen[c.Word] = true
		picks = append(picks, c.Rank)
	}
	// ピークが帯の下にあるので、帯内で一番近いのは下端から順になる。
	want := []int{250, 251, 252, 253, 254}
	for i := range want {
		if picks[i] != want[i] {
			t.Fatalf("選出順が違う: got %v want %v", picks, want)
		}
	}
	t.Logf("帯 [%d,%d] 内から既出を避けて選出: rank=%v（旧実装はピークの rank=100 へ降りていた）",
		low, high, picks)
}
