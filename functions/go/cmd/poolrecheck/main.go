// Command poolrecheck は GCS の例文プールを今の判定で洗い直す。
//
// プールに入った文は後から判定し直さないので、観点を足したり直したりしたら
// これで既存の文にもかける。生成時の観点（quality.Aspects）とプール用の観点
// （quality.PoolAspects）の両方に通った文だけを残す。
//
// 既定は dry run（落とす文を出すだけ）。-write で、元のファイルを
// <name>.bak-YYYYMMDD に写してから書き戻す。判定に失敗した文は残す。
//
//	GCLOUD_PROJECT=thai-memo-prod go run ./cmd/poolrecheck -lang ja
//	GCLOUD_PROJECT=thai-memo-prod go run ./cmd/poolrecheck -lang ja -write
package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"os"
	"sync"
	"time"

	"cloud.google.com/go/storage"

	"github.com/mnbst/thai-memo/functions/go/internal/lang"
	"github.com/mnbst/thai-memo/functions/go/internal/quality"
	"github.com/mnbst/thai-memo/functions/go/internal/sentence"
)

func main() {
	langCode := flag.String("lang", "ja", "プールの言語（ja / en）")
	write := flag.Bool("write", false, "落とした結果を GCS へ書き戻す（バックアップを取ってから）")
	conc := flag.Int("c", 8, "同時実行数")
	flag.Parse()

	l, ok := lang.Parse(*langCode)
	if !ok {
		log.Fatalf("-lang %q は ja / en のどちらか", *langCode)
	}
	project := os.Getenv("GCLOUD_PROJECT")
	if project == "" {
		log.Fatal("GCLOUD_PROJECT が未設定")
	}

	ctx := context.Background()
	client, err := storage.NewClient(ctx)
	if err != nil {
		log.Fatal(err)
	}
	defer client.Close()
	bucket := client.Bucket(project + "-uvm-data")
	name := sentence.PoolObject(l)

	// ReadSentences は開けないとき nil を返す。空のまま書き戻さないよう止める。
	pool, err := sentence.ReadSentences(ctx, bucket, name)
	if err != nil {
		log.Fatal(err)
	}
	if pool == nil {
		log.Fatalf("%s を開けない", name)
	}

	judge, err := quality.NewJudge(ctx)
	if err != nil {
		log.Fatal(err)
	}

	drop := make([]string, len(pool)) // 落とす理由。空なら残す
	failed := 0
	var mu sync.Mutex
	var wg sync.WaitGroup
	sem := make(chan struct{}, *conc)
	for i, s := range pool {
		wg.Add(1)
		go func() {
			defer wg.Done()
			sem <- struct{}{}
			defer func() { <-sem }()
			c := []quality.Candidate{{
				ThaiText: s.ThaiText, JapaneseTranslation: s.JapaneseTranslation,
				KeyWord: s.KeyWord, Lang: l,
			}}
			reason, err := recheck(ctx, judge, c)
			mu.Lock()
			defer mu.Unlock()
			if err != nil {
				failed++
				log.Printf("判定失敗（残す）: %s: %v", s.ThaiText, err)
				return
			}
			drop[i] = reason
		}()
	}
	wg.Wait()

	var kept []sentence.Sentence
	for i, s := range pool {
		if drop[i] == "" {
			kept = append(kept, s)
			continue
		}
		fmt.Printf("drop key_word=%s %s | %s | %s\n", s.KeyWord, drop[i], s.ThaiText, s.JapaneseTranslation)
	}
	fmt.Printf("\n%s: %d本 → %d本（落とす %d・判定失敗 %d）\n", name, len(pool), len(kept), len(pool)-len(kept), failed)

	if !*write || len(kept) == len(pool) {
		return
	}
	backup := fmt.Sprintf("%s.bak-%s", name, time.Now().Format("20060102"))
	if _, err := bucket.Object(backup).CopierFrom(bucket.Object(name)).Run(ctx); err != nil {
		log.Fatalf("バックアップに失敗（書き戻さない）: %v", err)
	}
	data, err := json.Marshal(kept)
	if err != nil {
		log.Fatal(err)
	}
	w := bucket.Object(name).NewWriter(ctx)
	w.ContentType = "application/json"
	if _, err := w.Write(data); err != nil {
		w.Close()
		log.Fatal(err)
	}
	if err := w.Close(); err != nil {
		log.Fatal(err)
	}
	fmt.Printf("書き戻した（バックアップ: %s）\n", backup)
}

// recheck は生成時の観点とプール用の観点で判定し、落とすなら理由を返す。
func recheck(ctx context.Context, judge *quality.Judge, c []quality.Candidate) (string, error) {
	res, err := judge.Review(ctx, c)
	if err != nil {
		return "", err
	}
	if len(res.Flagged) > 0 {
		return res.Verdicts[0].Reason, nil
	}
	res, err = judge.ReviewPool(ctx, c)
	if err != nil {
		return "", err
	}
	if len(res.Flagged) > 0 {
		return res.Verdicts[0].Reason, nil
	}
	return "", nil
}
