// Command resyncvocab は全ユーザーの estimated_vocab を今の推定式で計算し直す。
//
// 既定は dry run で、何も書かずに変わる人数と一覧を出す。-write で書く。
// 書くときは先に元の値を -backup へ保存し、ランキングも SyncEstimatedVocab が更新する。
//
//	GCLOUD_PROJECT=thai-memo-67139 go run ./cmd/resyncvocab -out /tmp/plan.json
//	GCLOUD_PROJECT=thai-memo-67139 go run ./cmd/resyncvocab -write -backup /tmp/before.json
package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"os"

	"cloud.google.com/go/firestore"
	"google.golang.org/api/iterator"

	"github.com/mnbst/thai-memo/functions/go/internal/fbapp"
	"github.com/mnbst/thai-memo/functions/go/internal/uvm"
)

type change struct {
	UID    string `json:"uid"`
	Stored int    `json:"stored"`
	Next   int    `json:"next"`
}

func main() {
	out := flag.String("out", "", "計算結果の JSON の書き出し先")
	write := flag.Bool("write", false, "estimated_vocab を書き換える")
	backup := flag.String("backup", "", "-write のとき元の値を保存する JSON（必須）")
	flag.Parse()
	if *write && *backup == "" {
		log.Fatal("-write には -backup が要る")
	}

	ctx := context.Background()
	db, err := fbapp.Firestore(ctx)
	if err != nil {
		log.Fatal(err)
	}
	freqRank, err := uvm.GetFreqRank(ctx, fbapp.ProjectID())
	if err != nil || len(freqRank) == 0 {
		log.Fatalf("順位表を読めない: %v", err)
	}

	changes, total, err := plan(ctx, db, freqRank)
	if err != nil {
		log.Fatal(err)
	}
	up, down := 0, 0
	for _, c := range changes {
		if c.Next > c.Stored {
			up++
		} else {
			down++
		}
	}
	fmt.Printf("project=%s users=%d 下がる=%d 上がる=%d 同じ=%d\n",
		fbapp.ProjectID(), total, down, up, total-len(changes))

	if *out != "" {
		if err := writeJSON(*out, changes); err != nil {
			log.Fatal(err)
		}
	}
	if !*write {
		return
	}
	if err := writeJSON(*backup, changes); err != nil {
		log.Fatal(err)
	}
	for _, c := range changes {
		for range 10 {
			uvm.SyncEstimatedVocab(ctx, db, c.UID, freqRank)
			stored, next, err := uvm.PreviewEstimatedVocab(ctx, db, c.UID, freqRank)
			if err != nil {
				log.Fatal(err)
			}
			if stored == next {
				break
			}
		}
	}
	fmt.Printf("書き換え %d 人\n", len(changes))
}

func plan(ctx context.Context, db *firestore.Client, freqRank map[string]int) ([]change, int, error) {
	var changes []change
	total := 0
	it := db.Collection("users").Documents(ctx)
	defer it.Stop()
	for {
		doc, err := it.Next()
		if err == iterator.Done {
			return changes, total, nil
		}
		if err != nil {
			return nil, 0, err
		}
		total++
		stored, next, err := uvm.PreviewEstimatedVocab(ctx, db, doc.Ref.ID, freqRank)
		if err != nil {
			return nil, 0, err
		}
		if stored != next {
			changes = append(changes, change{UID: doc.Ref.ID, Stored: stored, Next: next})
		}
	}
}

func writeJSON(path string, v any) error {
	b, err := json.MarshalIndent(v, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(path, b, 0o600)
}
