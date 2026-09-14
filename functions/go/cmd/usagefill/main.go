// Command usagefill は最終コーパスの各文に「使い方」の説明を付ける。
//
// 入力は cmd/translate の JSONL（一文二訳）。タイ語文も訳も触らず、
// アプリの「使い方」欄が読む4項目（style / emotion / usage_scenarios /
// cultural_notes）だけを internal/corpususage で作る。出力は本体とは別の
// サイドカー JSONL で、scripts/export_corpus_bank.py が context へ合成する。
//
//	GOOGLE_CLOUD_PROJECT=thai-memo-dev go run ./cmd/usagefill \
//	  -in scripts/corpus/corpus.jsonl -out scripts/corpus/usage.jsonl -c 10
//
// 同じ -out を指して再実行すると、書けている行を飛ばして続きから流す。
// -max-rank で頻度の高い語から先に埋められる（配信に当たるのはこの帯から）。
package main

import (
	"bufio"
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"os"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/mnbst/thai-memo/functions/go/internal/corpususage"
	"github.com/mnbst/thai-memo/functions/go/internal/llm"
	"github.com/mnbst/thai-memo/functions/go/internal/secrets"
	"github.com/mnbst/thai-memo/functions/go/internal/sentence"
)

// corpusRow は cmd/translate が書いた1行のうち、この処理で読む項目。
//
// key_word_rank は JSONL では数値と文字列が混在しているので、どちらでも
// 読めるようにしておく（scripts/corpus/corpus.jsonl は文字列）。
type corpusRow struct {
	Rank          json.Number `json:"key_word_rank"`
	TargetWord    string      `json:"target_word"`
	Topic         string      `json:"topic"`
	SubTheme      string      `json:"sub_theme"`
	ThaiText      string      `json:"thai_text"`
	Pronunciation string      `json:"pronunciation"`
	JA            string      `json:"ja"`
	EN            string      `json:"en"`
}

func (r corpusRow) rank() int {
	n, err := strconv.Atoi(strings.TrimSpace(r.Rank.String()))
	if err != nil {
		return 0
	}
	return n
}

// usageRow はサイドカーの1行。thai_text で本体と突き合わせる
// （コーパスの thai_text は一意。export_corpus_bank.py 側も同じキーで引く）。
type usageRow struct {
	ThaiText   string `json:"thai_text"`
	TargetWord string `json:"target_word"`
	Style      string `json:"style,omitempty"`
	EmotionJA  string `json:"emotion_ja,omitempty"`
	EmotionEN  string `json:"emotion_en,omitempty"`
	UsageJA    string `json:"usage_ja,omitempty"`
	UsageEN    string `json:"usage_en,omitempty"`
	CultureJA  string `json:"culture_ja,omitempty"`
	CultureEN  string `json:"culture_en,omitempty"`
	Err        string `json:"error,omitempty"`
}

func main() {
	in := flag.String("in", "scripts/corpus/corpus.jsonl", "コーパスの JSONL")
	out := flag.String("out", "scripts/corpus/usage.jsonl", "JSONL の出力先（追記）")
	conc := flag.Int("c", 10, "同時実行数")
	block := flag.Int("block", 200, "追記するまとまりの件数")
	limit := flag.Int("limit", 0, "先頭 N 件だけ流す（0 は全部）")
	maxRank := flag.Int("max-rank", 0, "この頻度ランクまでで切る（0 は全部）")
	flag.Parse()

	rows, err := loadRows(*in)
	if err != nil {
		log.Fatal(err)
	}
	done, err := loadDone(*out)
	if err != nil {
		log.Fatal(err)
	}
	var todo []corpusRow
	for _, r := range rows {
		if *maxRank > 0 && r.rank() > *maxRank {
			continue
		}
		if !done[r.ThaiText] {
			todo = append(todo, r)
		}
	}
	if *limit > 0 && *limit < len(todo) {
		todo = todo[:*limit]
	}
	fmt.Fprintf(os.Stderr, "コーパス %d件 / 済み %d件 / これから %d件\n",
		len(rows), len(done), len(todo))
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
		recs := make([]usageRow, hi-lo)
		parallel(hi-lo, *conc, func(i int) { recs[i] = fill(ctx, gen, todo[lo+i]) })
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
			hi, len(todo), failed, el.Round(time.Second), eta.Round(time.Minute))
	}
	fmt.Printf("\n使い方の付与 %d本  %s  失敗 %d\n",
		len(todo), time.Since(start).Round(time.Second), failed)
}

func fill(ctx context.Context, gen sentence.Generator, r corpusRow) usageRow {
	row := usageRow{ThaiText: r.ThaiText, TargetWord: r.TargetWord}
	res, err := corpususage.Fill(ctx, gen, corpususage.Input{
		ThaiText:      r.ThaiText,
		Pronunciation: r.Pronunciation,
		JA:            r.JA,
		EN:            r.EN,
		TargetWord:    r.TargetWord,
		Topic:         r.Topic,
		SubTheme:      r.SubTheme,
	})
	if err != nil {
		row.Err = err.Error()
		return row
	}
	row.Style = res.Style
	row.EmotionJA, row.EmotionEN = res.EmotionJA, res.EmotionEN
	row.UsageJA, row.UsageEN = res.UsageJA, res.UsageEN
	row.CultureJA, row.CultureEN = res.CultureJA, res.CultureEN
	return row
}

func loadRows(path string) ([]corpusRow, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()
	var all []corpusRow
	sc := bufio.NewScanner(f)
	sc.Buffer(make([]byte, 1<<22), 1<<22)
	for sc.Scan() {
		if strings.TrimSpace(sc.Text()) == "" {
			continue
		}
		var r corpusRow
		if err := json.Unmarshal(sc.Bytes(), &r); err != nil {
			return nil, err
		}
		if r.ThaiText == "" {
			continue
		}
		all = append(all, r)
	}
	return all, sc.Err()
}

// loadDone は書けている行の thai_text を集める。失敗した行は済み扱いに
// しない（同じ -out を指すともう一度流れる）。
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
		var r usageRow
		if json.Unmarshal(sc.Bytes(), &r) != nil || r.ThaiText == "" || r.Err != "" {
			continue
		}
		done[r.ThaiText] = true
	}
	return done, sc.Err()
}

func appendJSONL(f *os.File, recs []usageRow) error {
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
