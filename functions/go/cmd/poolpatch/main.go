// Command poolpatch は GCS の例文プールから指定の文を外し、直した文を足す。
//
// patch.json は {"remove": [thai_text...], "add": [プールの1件...]}。
// 足す文は poolreview と同じ検査（CheckFixed）を通し、品詞をタガーの品詞に揃える。
// 既定は dry run。-write でバックアップを取ってから、読んだ版のまま書き戻す
// （間に別の書き込みがあれば失敗する）。
//
//	GCLOUD_PROJECT=thai-memo-prod go run ./cmd/poolpatch -patch patch.json [-write]
package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"os"
	"time"

	"cloud.google.com/go/storage"

	"github.com/mnbst/thai-memo/functions/go/internal/lang"
	"github.com/mnbst/thai-memo/functions/go/internal/poolreview"
	"github.com/mnbst/thai-memo/functions/go/internal/sentence"
)

type patch struct {
	Remove []string            `json:"remove"`
	Add    []sentence.Sentence `json:"add"`
}

func main() {
	langCode := flag.String("lang", "ja", "プールの言語（ja / en）")
	tier := flag.String("tier", "premium", "プールのティア（premium / free）")
	patchPath := flag.String("patch", "", "外す文・足す文の JSON")
	write := flag.Bool("write", false, "GCS へ書き戻す（バックアップを取ってから）")
	flag.Parse()

	l, ok := lang.Parse(*langCode)
	if !ok {
		log.Fatalf("-lang %q は ja / en のどちらか", *langCode)
	}
	project := os.Getenv("GCLOUD_PROJECT")
	if project == "" || *patchPath == "" {
		log.Fatal("GCLOUD_PROJECT と -patch が要る")
	}
	raw, err := os.ReadFile(*patchPath)
	if err != nil {
		log.Fatal(err)
	}
	var p patch
	if err := json.Unmarshal(raw, &p); err != nil {
		log.Fatalf("%s の JSON 解析に失敗: %v", *patchPath, err)
	}
	labels := poolreview.PoolLabels(*tier, l)
	for i := range p.Add {
		if _, err := sentence.NormalizePOS(&p.Add[i], labels); err != nil {
			log.Fatalf("add %s: %v", p.Add[i].ThaiText, err)
		}
		if err := poolreview.CheckFixed(p.Add[i]); err != nil {
			log.Fatalf("add %s: %v", p.Add[i].ThaiText, err)
		}
	}

	ctx := context.Background()
	client, err := storage.NewClient(ctx)
	if err != nil {
		log.Fatal(err)
	}
	defer client.Close()
	bucket := client.Bucket(project + "-uvm-data")
	name := sentence.PoolObjectFor(*tier, l)
	obj := bucket.Object(name)
	attrs, err := obj.Attrs(ctx)
	if err != nil {
		log.Fatalf("%s を読めない: %v", name, err)
	}
	r, err := obj.Generation(attrs.Generation).NewReader(ctx)
	if err != nil {
		log.Fatal(err)
	}
	var pool []sentence.Sentence
	err = json.NewDecoder(r).Decode(&pool)
	r.Close()
	if err != nil {
		log.Fatalf("%s の JSON 解析に失敗: %v", name, err)
	}

	drop := map[string]bool{}
	for _, t := range p.Remove {
		drop[t] = true
	}
	found := map[string]bool{}
	var kept []sentence.Sentence
	for _, s := range pool {
		if drop[s.ThaiText] {
			found[s.ThaiText] = true
			continue
		}
		kept = append(kept, s)
	}
	for _, t := range p.Remove {
		if !found[t] {
			log.Printf("プールに無い（飛ばす）: %s", t)
		}
	}
	merged, added := poolreview.MergePool(kept, p.Add)
	fmt.Printf("%s: %d本 → %d本（外す %d・足す %d）\n", name, len(pool), len(merged), len(pool)-len(kept), added)
	if !*write {
		fmt.Println("dry run（-write で書く）")
		return
	}

	backup := fmt.Sprintf("%s.bak-%s-patch", name, time.Now().Format("20060102-150405"))
	if _, err := bucket.Object(backup).CopierFrom(obj.Generation(attrs.Generation)).Run(ctx); err != nil {
		log.Fatalf("バックアップに失敗（書き戻さない）: %v", err)
	}
	data, err := json.Marshal(merged)
	if err != nil {
		log.Fatal(err)
	}
	w := obj.If(storage.Conditions{GenerationMatch: attrs.Generation}).NewWriter(ctx)
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
