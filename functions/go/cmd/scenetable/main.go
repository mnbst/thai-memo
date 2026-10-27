// Command scenetable は場面合致の表（themeshots.MatchTable）を作る。
//
// ショット（bldrama・themeshots の data.go）を足したら、build_shot_embeddings.py の
// あとにこれを流し、upload_corpus.sh で GCS に上げる。表の版がショットと合わないと
// 本番は表を使わず、その場で計算する（遅いが結果は同じ）。
//
//	go run ./cmd/scenetable [-dir ../../scripts/corpus]
package main

import (
	"encoding/json"
	"flag"
	"log"
	"os"
	"path/filepath"
	"time"

	"github.com/mnbst/thai-memo/functions/go/internal/embeddings"
	"github.com/mnbst/thai-memo/functions/go/internal/themeshots"
)

func main() {
	dir := flag.String("dir", "../../scripts/corpus", "語・ショットの embedding があるディレクトリ")
	flag.Parse()
	store, err := embeddings.LoadLocalShots(*dir)
	if err != nil {
		log.Fatal(err)
	}
	raw, err := os.ReadFile(filepath.Join(*dir, "vocab_words.json"))
	if err != nil {
		log.Fatal(err)
	}
	var vocab []embeddings.Word
	if err := json.Unmarshal(raw, &vocab); err != nil {
		log.Fatal(err)
	}
	words := make([]string, len(vocab))
	for i, w := range vocab {
		words[i] = w.Word
	}
	start := time.Now()
	t := (&themeshots.Builder{Scenes: store}).BuildMatchTable(words)
	out, err := json.Marshal(t)
	if err != nil {
		log.Fatal(err)
	}
	path := filepath.Join(*dir, themeshots.MatchTableBlob)
	if err := os.WriteFile(path, out, 0o644); err != nil {
		log.Fatal(err)
	}
	log.Printf("%s: %d語・%dショット・%dKB 版=%s（%v）", path, len(t.Rows), len(t.Shots), len(out)>>10, t.Version, time.Since(start).Round(time.Second))
}
