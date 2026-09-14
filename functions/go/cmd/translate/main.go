// Command translate は生成済みコーパスに日本語訳と英訳を付ける。
//
// 入力は cmd/gencorpus の JSONL。タイ語文は確定済みなので触らず、
// 訳と語義だけを internal/corpustrans の専用プロンプトで作り直す。
// 生成時に付いた日本語訳は判定に使った下書き扱いで、ここで置き換える。
//
//	GOOGLE_CLOUD_PROJECT=thai-memo-dev go run ./cmd/translate \
//	  -in /tmp/corpus_ja.jsonl -out /tmp/corpus.jsonl -c 10
//
// 同じ -out を指して再実行すると、書けている行を飛ばして続きから流す。
package main

import (
	"bufio"
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"os"
	"strings"
	"sync"
	"time"

	"github.com/mnbst/thai-memo/functions/go/internal/corpustrans"
	"github.com/mnbst/thai-memo/functions/go/internal/llm"
	"github.com/mnbst/thai-memo/functions/go/internal/secrets"
	"github.com/mnbst/thai-memo/functions/go/internal/sentence"
)

// genRow は cmd/gencorpus が書いた1行。
type genRow struct {
	Rank       int                `json:"key_word_rank"`
	TargetWord string             `json:"target_word"`
	Topic      string             `json:"topic"`
	SubTheme   string             `json:"sub_theme"`
	Status     string             `json:"status"`
	Retried    *sentence.Sentence `json:"retried"`
	sentence.Sentence
}

// accepted は採用する文。差し戻しで通ったものは作り直したほう。
func (r genRow) accepted() *sentence.Sentence {
	switch r.Status {
	case "ok":
		return &r.Sentence
	case "repaired":
		return r.Retried
	}
	return nil
}

// word は最終コーパスの1語。読みと音節は生成時の NLP 後処理の結果で、
// 言語に依らないのでそのまま持ち越す。
type word struct {
	Word          string   `json:"word"`
	JA            string   `json:"ja"`
	EN            string   `json:"en"`
	Syllables     []string `json:"syllables,omitempty"`
	Pronunciation string   `json:"pronunciation,omitempty"`
	Role          string   `json:"grammatical_role,omitempty"`
}

// outRow は最終コーパスの1文。一文二訳の形。
type outRow struct {
	Rank          int    `json:"key_word_rank"`
	TargetWord    string `json:"target_word"`
	Topic         string `json:"topic"`
	SubTheme      string `json:"sub_theme"`
	ThaiText      string `json:"thai_text"`
	Pronunciation string `json:"pronunciation,omitempty"`
	JA            string `json:"ja"`
	EN            string `json:"en"`
	NoteJA        string `json:"note_ja,omitempty"`
	NoteEN        string `json:"note_en,omitempty"`
	Words         []word `json:"words"`
	Err           string `json:"error,omitempty"`
}

func (o outRow) key() string { return o.TargetWord + "\x00" + o.Topic }

func main() {
	in := flag.String("in", "/tmp/corpus_ja.jsonl", "cmd/gencorpus の JSONL")
	out := flag.String("out", "/tmp/corpus.jsonl", "JSONL の出力先（追記）")
	conc := flag.Int("c", 10, "同時実行数")
	block := flag.Int("block", 200, "追記するまとまりの件数")
	limit := flag.Int("limit", 0, "先頭 N 件だけ流す（0 は全部）")
	maxRank := flag.Int("max-rank", 0, "この頻度ランクまでで切る（0 は全部）")
	flag.Parse()

	rows, skipped, err := loadRows(*in)
	if err != nil {
		log.Fatal(err)
	}
	done, err := loadDone(*out)
	if err != nil {
		log.Fatal(err)
	}
	var todo []genRow
	for _, r := range rows {
		if *maxRank > 0 && r.Rank > *maxRank {
			continue
		}
		if !done[r.TargetWord+"\x00"+r.Topic] {
			todo = append(todo, r)
		}
	}
	if *limit > 0 && *limit < len(todo) {
		todo = todo[:*limit]
	}
	fmt.Fprintf(os.Stderr, "採用 %d件 / 不採用 %d件 / 済み %d件 / これから %d件\n",
		len(rows), skipped, len(done), len(todo))
	if len(todo) == 0 {
		return
	}

	ctx := context.Background()
	key, err := secrets.Get(ctx, "gemini-api-key")
	if err != nil {
		log.Fatalf("GEMINI_API_KEY か gemini-api-key が要る: %v", err)
	}
	model := envOr("GEMINI_MODEL", "gemini-3.1-flash-lite")
	gen := &llm.Client{
		GeminiKey: key, Provider: "gemini", MaxTokens: 8192,
		GeminiModel: model, GeminiModelPremium: model,
	}

	f, err := os.OpenFile(*out, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0o644)
	if err != nil {
		log.Fatal(err)
	}
	defer f.Close()

	start := time.Now()
	var failed int
	for lo := 0; lo < len(todo); lo += *block {
		hi := min(lo+*block, len(todo))
		recs := make([]outRow, hi-lo)
		parallel(hi-lo, *conc, func(i int) { recs[i] = translate(ctx, gen, todo[lo+i]) })
		if err := appendJSONL(f, recs); err != nil {
			log.Fatal(err)
		}
		for _, r := range recs {
			if r.Err != "" {
				failed++
			}
		}
		el := time.Since(start)
		eta := time.Duration(float64(el) / float64(hi) * float64(len(todo)-hi))
		fmt.Fprintf(os.Stderr, "%d/%d  失敗 %d  経過 %s 残り約 %s\n",
			hi, len(todo), failed, el.Round(time.Minute), eta.Round(time.Minute))
	}
	fmt.Printf("\n訳付け %d本  %s  失敗 %d\n", len(todo), time.Since(start).Round(time.Second), failed)
}

func translate(ctx context.Context, gen sentence.Generator, r genRow) outRow {
	s := r.accepted()
	row := outRow{
		Rank: r.Rank, TargetWord: r.TargetWord, Topic: r.Topic, SubTheme: r.SubTheme,
		ThaiText: s.ThaiText, Pronunciation: s.Pronunciation,
	}
	words := s.BreakdownWords()
	res, err := corpustrans.Translate(ctx, gen, corpustrans.Input{
		ThaiText:      s.ThaiText,
		Pronunciation: s.Pronunciation,
		Words:         words,
		TargetWord:    r.TargetWord,
		Topic:         r.Topic,
		SubTheme:      r.SubTheme,
	})
	if err != nil {
		row.Err = err.Error()
		return row
	}
	row.JA, row.EN = res.JA, res.EN
	row.NoteJA, row.NoteEN = res.NoteJA, res.NoteEN
	row.Words = make([]word, len(words))
	for i, w := range s.WordBreakdown {
		row.Words[i] = word{
			Word: w.Word, JA: res.Words[i].JA, EN: res.Words[i].EN,
			Syllables: w.Syllables, Pronunciation: w.Pronunciation,
			Role: w.GrammaticalRole,
		}
	}
	return row
}

// loadRows は採用できる行だけ返す。2つめの戻り値は落とした件数。
func loadRows(path string) ([]genRow, int, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, 0, err
	}
	defer f.Close()
	var all []genRow
	var skipped int
	sc := bufio.NewScanner(f)
	sc.Buffer(make([]byte, 1<<22), 1<<22)
	for sc.Scan() {
		if strings.TrimSpace(sc.Text()) == "" {
			continue
		}
		var r genRow
		if err := json.Unmarshal(sc.Bytes(), &r); err != nil {
			return nil, 0, err
		}
		if r.accepted() == nil {
			skipped++
			continue
		}
		all = append(all, r)
	}
	return all, skipped, sc.Err()
}

// loadDone は書けている行の (語, テーマ) を集める。訳に失敗した行は
// 済み扱いにしない（同じ -out を指すともう一度流れる）。
func loadDone(path string) (map[string]bool, error) {
	done := map[string]bool{}
	f, err := os.Open(path)
	if os.IsNotExist(err) {
		return done, nil
	}
	if err != nil {
		return nil, err
	}
	defer f.Close()
	sc := bufio.NewScanner(f)
	sc.Buffer(make([]byte, 1<<22), 1<<22)
	for sc.Scan() {
		var r outRow
		if json.Unmarshal(sc.Bytes(), &r) != nil || r.TargetWord == "" || r.Err != "" {
			continue
		}
		done[r.key()] = true
	}
	return done, sc.Err()
}

func appendJSONL(f *os.File, recs []outRow) error {
	w := bufio.NewWriter(f)
	enc := json.NewEncoder(w)
	for _, r := range recs {
		if err := enc.Encode(r); err != nil {
			return err
		}
	}
	if err := w.Flush(); err != nil {
		return err
	}
	return f.Sync()
}

func parallel(n, conc int, fn func(i int)) {
	sem := make(chan struct{}, conc)
	var wg sync.WaitGroup
	for i := range n {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			sem <- struct{}{}
			defer func() { <-sem }()
			fn(i)
		}(i)
	}
	wg.Wait()
}

func envOr(key, fallback string) string {
	if v := strings.TrimSpace(os.Getenv(key)); v != "" {
		return v
	}
	return fallback
}
