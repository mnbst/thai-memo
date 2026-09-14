// Command pilot は静的コーパスの生成を本番と同じ経路で試し、
// 判定の通過率を実測する。
//
// 入力は cmd/corpus が出すマニフェスト（1行1文）。語・テーマ・サブテーマ・
// 長さ・既知語の上限はマニフェストで確定しているので、ここでは抽選しない
// （時点と関係だけ Resolver に引かせる）。
//
//	go run ./cmd/corpus -out /tmp/manifest.jsonl
//	GOOGLE_CLOUD_PROJECT=thai-memo-dev go run ./cmd/pilot -n 200 -out /tmp/pilot.json
//
// 出す数字は 3 つ。
//
//	生成失敗 : LLM が返さなかった／壊れた
//	判定不合格: judge が弾いた割合（= 差し戻しが要る率）
//	再判定   : 差し戻したものが 2 回目で通った割合
package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"math/rand"
	"os"
	"strings"
	"sync"
	"time"

	"github.com/mnbst/thai-memo/functions/go/internal/bldrama"
	"github.com/mnbst/thai-memo/functions/go/internal/lang"
	"github.com/mnbst/thai-memo/functions/go/internal/llm"
	"github.com/mnbst/thai-memo/functions/go/internal/quality"
	"github.com/mnbst/thai-memo/functions/go/internal/secrets"
	"github.com/mnbst/thai-memo/functions/go/internal/sentence"
)

// judgeBatchSize は sentence_audit.go の auditBatchSize に合わせる。
const judgeBatchSize = 5

// row はマニフェストの1行。cmd/corpus の item と対応する。
type row struct {
	Rank       int     `json:"key_word_rank"`
	Word       string  `json:"key_word"`
	Topic      string  `json:"topic"`
	TopicSim   float64 `json:"topic_sim"`
	SubTheme   string  `json:"sub_theme"`
	LengthHint string  `json:"length_hint"`
	KnownRank  int     `json:"known_rank_max"`
}

type record struct {
	row
	// TargetWord は row.Word の控え。埋め込みの key_word は
	// Sentence 側の同名フィールドとぶつかって JSON から落ちる。
	TargetWord string `json:"target_word"`
	Err        string `json:"error,omitempty"`
	// Notes は judge の指摘。差し戻しプロンプトへそのまま入れる。
	Notes   []string           `json:"notes,omitempty"`
	Retried *sentence.Sentence `json:"retried,omitempty"`
	// RetryOK は差し戻したものが2回目の判定を通ったか。
	RetryOK bool `json:"retry_ok,omitempty"`
	*sentence.Sentence
}

func main() {
	in := flag.String("in", "/tmp/manifest_final.jsonl", "cmd/corpus のマニフェスト")
	n := flag.Int("n", 200, "抽出して生成する本数")
	langCode := flag.String("lang", "ja", "訳文の言語（ja / en）")
	conc := flag.Int("c", 8, "同時実行数")
	seed := flag.Int64("seed", 1, "抽出のシード")
	out := flag.String("out", "", "JSON の出力先")
	dry := flag.Bool("dry", false, "抽出した行を出すだけで生成しない")
	flag.Parse()

	rows, err := sampleRows(*in, *n, *seed)
	if err != nil {
		log.Fatal(err)
	}

	if *dry {
		b, _ := json.MarshalIndent(rows, "", " ")
		fmt.Println(string(b))
		return
	}

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
	}
	l := lang.Lang(*langCode)
	fmt.Fprintf(os.Stderr, "n=%d lang=%s model=%s\n", len(rows), *langCode, model)

	start := time.Now()
	recs := make([]record, len(rows))
	parallel(len(rows), *conc, func(i int) {
		recs[i] = record{row: rows[i], TargetWord: rows[i].Word}
		s, err := generate(ctx, svc, rows[i], l, nil)
		if err != nil {
			recs[i].Err = err.Error()
			fmt.Fprint(os.Stderr, "x")
			return
		}
		recs[i].Sentence = s
		fmt.Fprint(os.Stderr, ".")
	})
	fmt.Fprintln(os.Stderr)

	first := judge(ctx, svc, recs, func(r *record) *sentence.Sentence { return r.Sentence }, *conc)
	for i, notes := range first {
		recs[i].Notes = notes
	}

	// 差し戻し。指摘を渡して作り直す。
	var retryIdx []int
	for i := range recs {
		if len(recs[i].Notes) > 0 {
			retryIdx = append(retryIdx, i)
		}
	}
	parallel(len(retryIdx), *conc, func(k int) {
		i := retryIdx[k]
		s, err := generate(ctx, svc, recs[i].row, l, recs[i].Notes)
		if err != nil {
			fmt.Fprint(os.Stderr, "x")
			return
		}
		recs[i].Retried = s
		fmt.Fprint(os.Stderr, "+")
	})
	fmt.Fprintln(os.Stderr)

	second := judge(ctx, svc, recs, func(r *record) *sentence.Sentence { return r.Retried }, *conc)
	for i := range recs {
		if recs[i].Retried != nil && len(second[i]) == 0 {
			recs[i].RetryOK = true
		}
	}

	if *out != "" {
		b, _ := json.MarshalIndent(recs, "", " ")
		if err := os.WriteFile(*out, b, 0o644); err != nil {
			log.Fatal(err)
		}
		fmt.Fprintf(os.Stderr, "wrote %s\n", *out)
	}
	report(recs, time.Since(start))
}

// generate は1行ぶんを生成する。notes があれば差し戻しとして扱う。
//
// GenerateSentence を使わないのは、プロンプトを内部で組み立ててしまい
// マニフェストの確定値も差し戻しブロックも入れられないため。
func generate(
	ctx context.Context, svc *sentence.Service, r row, l lang.Lang, notes []string,
) (*sentence.Sentence, error) {
	words := []string{r.Word}
	params := map[string]any{"topic": r.Topic}
	// 時点と関係だけ抽選させる。サブテーマはマニフェストの値で上書きする。
	resolved := svc.Resolver.Resolve(ctx, params, words, r.KnownRank)
	resolved.SubTheme = r.SubTheme
	resolved.LengthHint = r.LengthHint

	var drama sentence.DramaSection
	if r.Topic == sentence.Topics[15] {
		drama = svc.Drama.BuildDramaSection(words)
	}
	prompt, rc := sentence.BuildPrompt(resolved, words, r.KnownRank, true, l, drama)
	if block := sentence.BuildRetryConstraint(notes); block != "" {
		prompt += "\n\n" + block
	}
	return sentence.GenerateSingle(ctx, svc.Gen, sentence.Request{
		SystemPrompt:    sentence.SystemPrompt(true, l),
		Prompt:          prompt,
		IsPremium:       true,
		TierLabel:       "premium",
		TargetWords:     words,
		ResolvedContext: rc,
		Lang:            l,
	})
}

// judge は pick で取り出した文をまとめて判定し、index ごとの指摘を返す。
// 指摘が空なら合格、pick が nil を返した index も空になる。
func judge(
	ctx context.Context, svc *sentence.Service, recs []record,
	pick func(*record) *sentence.Sentence, conc int,
) map[int][]string {
	var batch []quality.Candidate
	var idx []int
	for i := range recs {
		s := pick(&recs[i])
		if s == nil {
			continue
		}
		batch = append(batch, quality.Candidate{
			SentenceID:          fmt.Sprint(i),
			ThaiText:            s.ThaiText,
			Pronunciation:       s.Pronunciation,
			JapaneseTranslation: s.JapaneseTranslation,
			KeyWord:             recs[i].Word,
		})
		idx = append(idx, i)
	}
	notes := map[int][]string{}
	if len(batch) == 0 {
		return notes
	}

	j := &quality.Judge{Gen: svc.Gen}
	var mu sync.Mutex
	chunks := (len(batch) + judgeBatchSize - 1) / judgeBatchSize
	parallel(chunks, conc, func(c int) {
		lo := c * judgeBatchSize
		hi := min(lo+judgeBatchSize, len(batch))
		_, verdicts, err := j.JudgeBatch(ctx, batch[lo:hi])
		if err != nil {
			log.Printf("judge に失敗: %v", err)
			return
		}
		mu.Lock()
		defer mu.Unlock()
		for _, v := range verdicts {
			if v.Index < 0 || lo+v.Index >= len(idx) {
				continue
			}
			i := idx[lo+v.Index]
			notes[i] = append(notes[i], v.Reason)
		}
	})
	fmt.Fprintf(os.Stderr, "judge: %d件中 %d件が不合格\n", len(batch), len(notes))
	return notes
}

func report(recs []record, elapsed time.Duration) {
	var failed, flagged, retried, retryOK int
	reasons := map[string]int{}
	for _, r := range recs {
		if r.Sentence == nil {
			failed++
			continue
		}
		if len(r.Notes) == 0 {
			continue
		}
		flagged++
		for _, n := range r.Notes {
			reasons[head(n, 24)]++
		}
		if r.Retried != nil {
			retried++
			if r.RetryOK {
				retryOK++
			}
		}
	}
	ok := len(recs) - failed - flagged
	fmt.Printf("\n対象       %d本  %s\n", len(recs), elapsed.Round(time.Second))
	fmt.Printf("一発合格   %d (%.0f%%)\n", ok, pct(ok, len(recs)))
	fmt.Printf("判定不合格 %d (%.0f%%)  うち差し戻し成功 %d / %d\n",
		flagged, pct(flagged, len(recs)), retryOK, retried)
	fmt.Printf("生成失敗   %d\n", failed)
	fmt.Printf("最終       %.0f%% が合格文（差し戻し1回まで）\n",
		pct(ok+retryOK, len(recs)))
	if len(reasons) > 0 {
		fmt.Println("\n指摘の内訳")
		for k, v := range reasons {
			fmt.Printf("  %2d  %s\n", v, k)
		}
	}
}

// sampleRows はマニフェストから n 行を一様に抽出する。帯ごとに揃えないのは、
// 全量生成したときの合格率を知りたいため（行数の多い帯が重く出るのが正しい）。
func sampleRows(path string, n int, seed int64) ([]row, error) {
	raw, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	var all []row
	for _, line := range strings.Split(string(raw), "\n") {
		if strings.TrimSpace(line) == "" {
			continue
		}
		var r row
		if err := json.Unmarshal([]byte(line), &r); err != nil {
			return nil, err
		}
		all = append(all, r)
	}
	rng := rand.New(rand.NewSource(seed))
	rng.Shuffle(len(all), func(a, b int) { all[a], all[b] = all[b], all[a] })
	return all[:min(n, len(all))], nil
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

func pct(a, b int) float64 {
	if b == 0 {
		return 0
	}
	return float64(a) * 100 / float64(b)
}

func head(s string, n int) string {
	r := []rune(s)
	if len(r) <= n {
		return s
	}
	return string(r[:n]) + "…"
}

func envOr(key, fallback string) string {
	if v := strings.TrimSpace(os.Getenv(key)); v != "" {
		return v
	}
	return fallback
}
