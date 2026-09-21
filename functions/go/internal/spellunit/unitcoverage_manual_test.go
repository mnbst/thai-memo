package spellunit

import (
	"encoding/json"
	"math/rand"
	"os"
	"sort"
	"testing"
)

// TestUnitCoverageByRank は「語彙スコアいくつまで出題すれば部品を網羅できるか」の
// 調査用。SPELLUNIT_UNITCOV=1 で実行する。
func TestUnitCoverageByRank(t *testing.T) {
	if os.Getenv("SPELLUNIT_UNITCOV") == "" {
		t.Skip("調査用")
	}
	raw, err := os.ReadFile("../../../../scripts/corpus/freq_rank_top10000.json")
	if err != nil {
		t.Fatal(err)
	}
	var fr map[string]int
	if err := json.Unmarshal(raw, &fr); err != nil {
		t.Fatal(err)
	}
	words := make([]string, 0, len(fr))
	for w := range fr {
		words = append(words, w)
	}
	sort.Slice(words, func(i, j int) bool { return fr[words[i]] < fr[words[j]] })

	ix, err := LoadIndex()
	if err != nil {
		t.Fatal(err)
	}

	// 語ごとに「測れる部品」= ダミーが作れる次元の正解側の値。
	// Distractors は次元を無作為に3つ選ぶので、種を変えて和を取る。
	testable := func(word string) map[string]bool {
		out := map[string]bool{}
		code, ok := ix.Lookup(word)
		if !ok {
			return out
		}
		for seed := int64(0); seed < 8; seed++ {
			rnd := rand.New(rand.NewSource(seed))
			ds, ok := ix.Distractors(word, rnd)
			if !ok {
				return map[string]bool{}
			}
			for _, d := range ds {
				out[UnitID(d.Dim, code.At(d.Dim))] = true
			}
		}
		return out
	}

	// 全体（top10000）で到達しうる部品の集合。
	universe := map[string]bool{}
	firstRank := map[string]int{}
	for _, w := range words {
		for u := range testable(w) {
			if !universe[u] {
				universe[u] = true
				firstRank[u] = fr[w]
			}
		}
	}
	t.Logf("到達しうる部品 %d 種", len(universe))

	seen2 := map[string]bool{}
	covered := 0
	seen := map[string]bool{}
	marks := []int{50, 100, 150, 200, 300, 500, 1000, 2000, 5000, 10000}
	mi := 0
	full := 0
	for _, w := range words {
		rank := fr[w]
		for mi < len(marks) && rank > marks[mi] {
			t.Logf("rank<=%-5d 部品 %3d/%d (%.0f%%)", marks[mi], covered, len(universe),
				100*float64(covered)/float64(len(universe)))
			mi++
		}
		for u := range testable(w) {
			if !seen[u] {
				seen[u] = true
				covered++
				if covered == len(universe) {
					full = rank
				}
			}
		}
	}
	for ; mi < len(marks); mi++ {
		t.Logf("rank<=%-5d 部品 %3d/%d (%.0f%%)", marks[mi], covered, len(universe),
			100*float64(covered)/float64(len(universe)))
	}
	t.Logf("全部品を覆い切る rank = %d", full)

	// 次元ごとの網羅 rank。
	dimFull := map[string]int{}
	dimTotal := map[string]int{}
	for u := range universe {
		dimTotal[u[:sortIdx(u)]]++
	}
	dimSeen := map[string]int{}
	for _, w := range words {
		for u := range testable(w) {
			if !seen2[u] {
				seen2[u] = true
				k := u[:sortIdx(u)]
				dimSeen[k]++
				if dimSeen[k] == dimTotal[k] {
					dimFull[k] = fr[w]
				}
			}
		}
	}
	for k, v := range dimFull {
		c := map[int]int{}
		for u := range universe {
			if u[:sortIdx(u)] == k {
				for _, m := range marks {
					if firstRank[u] <= m {
						c[m]++
					}
				}
			}
		}
		t.Logf("次元 %-6s %2d種 網羅 rank %d / 100まで %d / 300まで %d / 1000まで %d", k, dimTotal[k], v, c[100], c[300], c[1000])
	}
	// 最後に埋まる部品を出す。
	type ur struct {
		u string
		r int
	}
	list := make([]ur, 0, len(universe))
	for u := range universe {
		list = append(list, ur{u, firstRank[u]})
	}
	sort.Slice(list, func(i, j int) bool { return list[i].r > list[j].r })
	for i := 0; i < 15 && i < len(list); i++ {
		t.Logf("遅い部品 %-12s 初出 rank %d", list[i].u, list[i].r)
	}
}

func sortIdx(u string) int {
	for i := 0; i < len(u); i++ {
		if u[i] == ':' {
			return i
		}
	}
	return len(u)
}
