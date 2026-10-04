// Command freeregen は free 例文バンク（free_sentences_<lang>.json）のうち、
// 指定テーマの項目だけを本番と同じ生成経路で作り直す。
//
// 語・ランク・estimated_vocab は元の項目のまま、free のプロンプトで生成し、
// 判定 → 差し戻し1回 → 再判定 まで通す。2回とも通らなければ元の項目を残す。
// それ以外の項目には触らない。
//
//	gcloud storage cp gs://thai-memo-prod-uvm-data/free_sentences_ja.json /tmp/
//	GOOGLE_CLOUD_PROJECT=thai-memo-dev go run ./cmd/freeregen \
//	  -in /tmp/free_sentences_ja.json -out /tmp/free_sentences_ja.new.json -lang ja -topic 1
package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"os"
	"strings"
	"sync"

	"github.com/mnbst/thai-memo/functions/go/internal/bldrama"
	"github.com/mnbst/thai-memo/functions/go/internal/embeddings"
	"github.com/mnbst/thai-memo/functions/go/internal/lang"
	"github.com/mnbst/thai-memo/functions/go/internal/llm"
	"github.com/mnbst/thai-memo/functions/go/internal/quality"
	"github.com/mnbst/thai-memo/functions/go/internal/secrets"
	"github.com/mnbst/thai-memo/functions/go/internal/sentence"
	"github.com/mnbst/thai-memo/functions/go/internal/themeshots"
)

// judgeBatchSize は sentence_audit.go の auditBatchSize に合わせる。
const judgeBatchSize = 5

type job struct {
	idx   int // バンク内の位置
	word  string
	vocab int
	s     *sentence.Sentence
	notes []string
}

func main() {
	in := flag.String("in", "", "元の free バンク JSON")
	out := flag.String("out", "", "書き出し先 JSON")
	langCode := flag.String("lang", "ja", "バンクの言語（ja / en）")
	topicIx := flag.Int("topic", 1, "作り直すテーマ（sentence.Topics の添字）")
	conc := flag.Int("c", 10, "同時実行数")
	embDir := flag.String("emb-dir", "../../scripts/corpus", "場面の選出に使う embedding のディレクトリ（空なら場面で絞らない）")
	flag.Parse()
	if *in == "" || *out == "" {
		log.Fatal("-in と -out が要る")
	}

	raw, err := os.ReadFile(*in)
	if err != nil {
		log.Fatal(err)
	}
	var bank []map[string]any
	if err := json.Unmarshal(raw, &bank); err != nil {
		log.Fatal(err)
	}

	l := lang.Lang(*langCode)
	topic := sentence.Topics[*topicIx]
	// en のバンクは context を英語ラベルで持つ。
	stored := sentence.LocalizeContext(map[string]any{"topic": topic}, l)["topic"]

	var jobs []*job
	for i, e := range bank {
		c, _ := e["context"].(map[string]any)
		if c["topic"] != stored {
			continue
		}
		vocab, _ := e["estimated_vocab"].(float64)
		word, _ := e["key_word"].(string)
		jobs = append(jobs, &job{idx: i, word: word, vocab: int(vocab)})
	}
	fmt.Fprintf(os.Stderr, "対象 %d / %d 件（%s）\n", len(jobs), len(bank), stored)

	ctx := context.Background()
	key, err := secrets.Get(ctx, "gemini-api-key")
	if err != nil {
		log.Fatalf("GEMINI_API_KEY か gemini-api-key が要る: %v", err)
	}
	model := envOr("GEMINI_MODEL", "gemini-3.1-flash-lite")
	svc := &sentence.Service{
		Gen: &llm.Client{
			GeminiKey: key, Provider: "gemini", MaxTokens: 8192,
			GeminiModel: model, GeminiModelPremium: model,
		},
		Resolver: &sentence.Resolver{},
		Drama:    &bldrama.Builder{},
		Shots:    &themeshots.Builder{Scenes: sceneFinder(*embDir)},
	}
	j, err := quality.NewJudge(ctx)
	if err != nil {
		log.Fatalf("judge を作れない: %v", err)
	}

	gen := func(jb *job) {
		s, err := svc.GenerateSentenceWithNotes(ctx, map[string]any{"topic": topic},
			false, []string{jb.word}, jb.vocab, l, jb.notes)
		if err != nil {
			log.Printf("生成失敗 %s: %v", jb.word, err)
			jb.s = nil
			return
		}
		jb.s = s
	}

	parallel(jobs, *conc, gen)
	first := judge(ctx, j, jobs, l, *conc)
	var retry []*job
	for _, jb := range jobs {
		if jb.s == nil || len(first[jb]) > 0 {
			jb.notes = first[jb]
			retry = append(retry, jb)
		}
	}
	parallel(retry, *conc, gen)
	second := judge(ctx, j, retry, l, *conc)

	replaced, kept := 0, 0
	for _, jb := range jobs {
		if jb.s == nil || len(second[jb]) > 0 {
			kept++
			continue
		}
		e := bank[jb.idx]
		e["thai_text"] = jb.s.ThaiText
		e["japanese_translation"] = jb.s.JapaneseTranslation
		e["pronunciation"] = jb.s.Pronunciation
		e["word_breakdown"] = jb.s.WordBreakdown
		e["context"] = sentence.LocalizeContext(jb.s.Context, l)
		replaced++
	}

	b, err := json.Marshal(bank)
	if err != nil {
		log.Fatal(err)
	}
	if err := os.WriteFile(*out, b, 0o644); err != nil {
		log.Fatal(err)
	}
	fmt.Fprintf(os.Stderr, "差し替え %d / 元のまま %d（差し戻し %d）→ %s\n",
		replaced, kept, len(retry), *out)
}

// judge は生成できた文を判定し、不合格の文に差し戻し用の指摘を返す。
// 判定は jobs のうち retry 対象（直前に作り直したもの）だけにかける。
func judge(ctx context.Context, j *quality.Judge, jobs []*job, l lang.Lang, conc int) map[*job][]string {
	var batch []quality.Candidate
	var idx []*job
	for _, jb := range jobs {
		if jb.s == nil {
			continue
		}
		batch = append(batch, quality.Candidate{
			SentenceID:          fmt.Sprint(jb.idx),
			ThaiText:            jb.s.ThaiText,
			Pronunciation:       jb.s.Pronunciation,
			JapaneseTranslation: jb.s.JapaneseTranslation,
			KeyWord:             jb.word,
			Lang:                l,
		})
		idx = append(idx, jb)
	}
	notes := map[*job][]string{}
	var mu sync.Mutex
	chunks := (len(batch) + judgeBatchSize - 1) / judgeBatchSize
	sem := make(chan struct{}, conc)
	var wg sync.WaitGroup
	for c := range chunks {
		wg.Add(1)
		go func(c int) {
			defer wg.Done()
			sem <- struct{}{}
			defer func() { <-sem }()
			lo := c * judgeBatchSize
			hi := min(lo+judgeBatchSize, len(batch))
			_, verdicts, err := j.JudgeBatch(ctx, batch[lo:hi])
			if err != nil {
				// 判定できなかった文は通さない（元の項目を残す側へ倒す）。
				log.Printf("judge に失敗: %v", err)
				mu.Lock()
				for _, jb := range idx[lo:hi] {
					notes[jb] = []string{"判定できなかった"}
				}
				mu.Unlock()
				return
			}
			mu.Lock()
			defer mu.Unlock()
			for _, v := range verdicts {
				if v.Index < 0 || lo+v.Index >= hi {
					continue
				}
				jb := idx[lo+v.Index]
				notes[jb] = append(notes[jb], v.RetryNotes()...)
			}
		}(c)
	}
	wg.Wait()
	fmt.Fprintf(os.Stderr, "judge: %d件中 %d件が不合格\n", len(batch), len(notes))
	return notes
}

func parallel(jobs []*job, conc int, fn func(*job)) {
	sem := make(chan struct{}, conc)
	var wg sync.WaitGroup
	for _, jb := range jobs {
		wg.Add(1)
		go func(jb *job) {
			defer wg.Done()
			sem <- struct{}{}
			defer func() { <-sem }()
			fn(jb)
		}(jb)
	}
	wg.Wait()
}

func envOr(key, fallback string) string {
	if v := strings.TrimSpace(os.Getenv(key)); v != "" {
		return v
	}
	return fallback
}

// sceneFinder は -emb-dir のローカル embedding から場面の選出器を作る。
// 空なら nil（場面で絞らずランダム）。本番は GCS の同じファイルを使う。
func sceneFinder(dir string) themeshots.SceneFinder {
	if dir == "" {
		return nil
	}
	store, err := embeddings.LoadLocalShots(dir)
	if err != nil {
		log.Fatalf("embedding を読めない: %v", err)
	}
	return store
}
