package main

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"sort"

	"cloud.google.com/go/firestore"
	"google.golang.org/api/iterator"

	"github.com/mnbst/thai-memo/functions/go/internal/uvm"
)

// 実際の UVM で EstimateVocab が何を返すかを、sync と同じ手順で再現する。
func main() {
	ctx := context.Background()
	db, err0 := firestore.NewClient(ctx, "thai-memo-dev")
	if err0 != nil {
		panic(err0)
	}
	b, _ := os.ReadFile("../../scripts/corpus/freq_rank_top10000.json")
	var rank map[string]int
	json.Unmarshal(b, &rank)

	n := 0
	_ = n
	it := db.Collection("users").Documents(ctx)
	for {
		d, err := it.Next()
		if err == iterator.Done {
			fmt.Println("(users の走査終了)")
			return
		}
		if err != nil {
			panic(err)
		}
		n++
		x := d.Data()
		cur64, ok := x["estimated_vocab"].(int64)
		if !ok {
			continue
		}
		current := int(cur64)
		tested := 0
		if v, ok := x["vocab_test_vocab"].(int64); ok {
			tested = int(v)
		}
		fmt.Printf("uid=%s current=%d tested=%v\n",
			d.Ref.ID[:6], current, x["vocab_test_vocab"])

		pOf := map[string]float64{}
		answeredOf := map[string]bool{}
		lastOf := map[string]any{}
		attemptsOf := map[string]int{}
		wit := d.Ref.Collection("uvm").Documents(ctx)
		for {
			u, err := wit.Next()
			if err == iterator.Done {
				break
			}
			if err != nil {
				panic(err)
			}
			ud := u.Data()
			p, _ := ud["p"].(float64)
			pOf[u.Ref.ID] = p
			attempts, _ := ud["quiz_attempts"].(int64)
			answeredOf[u.Ref.ID] = attempts > 0 || ud["last_result"] != nil
			lastOf[u.Ref.ID] = ud["last_result"]
			attemptsOf[u.Ref.ID] = int(attempts)
		}

		// store.go と同じ帯で entries を作る
		low, high := max(0, current-50), current+51
		var entries []uvm.RankedP
		for w, p := range pOf {
			if r, ok := rank[w]; ok && r >= low && r < high {
				entries = append(entries, uvm.RankedP{Rank: r, P: p})
			}
		}
		raw := uvm.EstimateVocab(entries, current, tested)
		fmt.Printf("  帯=[%d,%d) entries=%d raw=%d delta=%+d\n",
			low, high, len(entries), raw,
			raw-current)
		sort.Slice(entries, func(a, b int) bool { return entries[a].Rank < entries[b].Rank })
		for _, e := range entries {
			w := ""
			for word, r := range rank {
				if r == e.Rank {
					w = word
					break
				}
			}
			fmt.Printf("    rank=%d p=%.3f answered=%v attempts=%d last=%v %s\n",
				e.Rank, e.P, answeredOf[w], attemptsOf[w], lastOf[w], w)
		}
	}
}
