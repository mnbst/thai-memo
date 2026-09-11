// Command sample はプロンプトの改訂前後を見比べるためのサンプル生成。
//
// 語はランク帯から散らし、テーマは16種を順に割り当てる。結果は JSON と
// 1行要約で出すので、そのまま品質判定にかけられる。
//
//	go run ./cmd/sample -n 40 -out /tmp/sample.json
//	go run ./cmd/sample -n 20 -lang en -topic 恋愛
package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"math/rand"
	"os"
	"sort"
	"strings"
	"sync"

	"github.com/mnbst/thai-memo/functions/go/internal/bldrama"
	"github.com/mnbst/thai-memo/functions/go/internal/lang"
	"github.com/mnbst/thai-memo/functions/go/internal/llm"
	"github.com/mnbst/thai-memo/functions/go/internal/quality"
	"github.com/mnbst/thai-memo/functions/go/internal/secrets"
	"github.com/mnbst/thai-memo/functions/go/internal/sentence"
)

const rankPath = "../../scripts/corpus/freq_rank_top10000.json"

// bands はサンプルを散らすランク帯。静的コーパスの帯分けに合わせてある。
var bands = [][2]int{{1, 300}, {301, 500}, {501, 1500}, {1501, 3000}, {3001, 5000}}

type record struct {
	Rank  int    `json:"key_word_rank"`
	Word  string `json:"key_word"`
	Topic string `json:"requested_topic,omitempty"`
	Err   string `json:"error,omitempty"`
	// Retried は差し戻して作り直した文。空なら judge を通っている。
	Retried *sentence.Sentence `json:"retried,omitempty"`
	// Notes は judge の指摘。差し戻しプロンプトへそのまま入れる。
	Notes []string `json:"notes,omitempty"`
	*sentence.Sentence
}

func main() {
	n := flag.Int("n", 40, "生成本数")
	langCode := flag.String("lang", "ja", "訳文の言語（ja / en）")
	free := flag.Bool("free", false, "free ティアで生成する")
	vocab := flag.Int("vocab", 800, "estimated_vocab")
	topic := flag.String("topic", "", "テーマを固定する（部分一致）。空なら16種を順に割り当てる")
	conc := flag.Int("c", 5, "同時実行数")
	seed := flag.Int64("seed", 1, "語の抽選シード")
	out := flag.String("out", "", "JSON の出力先。空なら標準出力に要約のみ")
	fix := flag.Bool("fix", false, "生成後に judge をかけ、不合格を指摘つきで差し戻す")
	rankFile := flag.String("rank", rankPath, "freq_rank_top10000.json のパス")
	flag.Parse()

	words, err := pickWords(*rankFile, *n, *seed)
	if err != nil {
		log.Fatal(err)
	}
	topics := pickTopics(*topic)

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
		Resolver: &sentence.Resolver{SubThemes: randomSubTheme{}},
		// ドラマ回の専用ブロック。Shots が nil ならシーンをランダムに引く。
		Drama: &bldrama.Builder{},
	}
	fmt.Fprintf(os.Stderr, "n=%d lang=%s tier=%s vocab=%d model=%s\n",
		*n, *langCode, tierLabel(*free), *vocab, model)

	recs := make([]record, len(words))
	sem := make(chan struct{}, *conc)
	var wg sync.WaitGroup
	for i, w := range words {
		wg.Add(1)
		go func(i int, w wordRank) {
			defer wg.Done()
			sem <- struct{}{}
			defer func() { <-sem }()

			params := map[string]any{}
			topic := topics[i%len(topics)]
			if topic != "" {
				params["topic"] = topic
			}
			s, err := svc.GenerateSentence(ctx, params, !*free,
				[]string{w.Word}, *vocab, lang.Lang(*langCode))
			recs[i] = record{Rank: w.Rank, Word: w.Word, Topic: topic, Sentence: s}
			if err != nil {
				recs[i].Err = err.Error()
				fmt.Fprint(os.Stderr, "x")
				return
			}
			fmt.Fprint(os.Stderr, ".")
		}(i, w)
	}
	wg.Wait()
	fmt.Fprintln(os.Stderr)

	if *fix {
		retry(ctx, svc, recs, *free, *vocab, lang.Lang(*langCode), *conc)
	}

	if *out != "" {
		b, err := json.MarshalIndent(recs, "", " ")
		if err != nil {
			log.Fatal(err)
		}
		if err := os.WriteFile(*out, b, 0o644); err != nil {
			log.Fatal(err)
		}
		fmt.Fprintf(os.Stderr, "wrote %s\n", *out)
	}
	summarize(recs)
}

// retry は judge をかけ、不合格だったものを指摘つきで作り直す。
//
// 差し戻しでは BuildPrompt をこちら側で呼び、末尾に BuildRetryConstraint を
// 足してから GenerateSingle に渡す。GenerateSentence はプロンプトを内部で
// 組み立ててしまうので使えない。コーパス生成のバッチも同じ形になる。
func retry(
	ctx context.Context, svc *sentence.Service, recs []record,
	free bool, vocab int, l lang.Lang, conc int,
) {
	var batch []quality.Candidate
	var idx []int
	for i, r := range recs {
		if r.Sentence == nil {
			continue
		}
		batch = append(batch, quality.Candidate{
			SentenceID:          fmt.Sprint(i),
			ThaiText:            r.ThaiText,
			Pronunciation:       r.Pronunciation,
			JapaneseTranslation: r.JapaneseTranslation,
			KeyWord:             r.Word,
		})
		idx = append(idx, i)
	}
	if len(batch) == 0 {
		return
	}

	j := &quality.Judge{Gen: svc.Gen}
	flagged, verdicts, err := j.JudgeBatch(ctx, batch)
	if err != nil {
		log.Printf("judge に失敗: %v", err)
		return
	}
	fmt.Fprintf(os.Stderr, "judge: %d件中 %d件が不合格\n", len(batch), len(flagged))
	if len(flagged) == 0 {
		return
	}

	sem := make(chan struct{}, conc)
	var wg sync.WaitGroup
	for n, v := range verdicts {
		i := idx[v.Index]
		recs[i].Notes = []string{verdicts[n].Reason}
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			sem <- struct{}{}
			defer func() { <-sem }()

			s, err := regenerate(ctx, svc, recs[i], free, vocab, l)
			if err != nil {
				log.Printf("差し戻しに失敗 [%s]: %v", recs[i].Word, err)
				fmt.Fprint(os.Stderr, "x")
				return
			}
			recs[i].Retried = s
			fmt.Fprint(os.Stderr, "+")
		}(i)
	}
	wg.Wait()
	fmt.Fprintln(os.Stderr)
}

func regenerate(
	ctx context.Context, svc *sentence.Service, r record,
	free bool, vocab int, l lang.Lang,
) (*sentence.Sentence, error) {
	params := map[string]any{}
	if r.Topic != "" {
		params["topic"] = r.Topic
	}
	words := []string{r.Word}
	resolved := svc.Resolver.Resolve(ctx, params, words, vocab)

	var drama sentence.DramaSection
	if svc.Drama != nil && resolved.Topic == sentence.Topics[15] {
		drama = svc.Drama.BuildDramaSection(words)
	}
	prompt, rc := sentence.BuildPrompt(resolved, words, vocab, !free, l, drama)
	if block := sentence.BuildRetryConstraint(r.Notes); block != "" {
		prompt += "\n\n" + block
	}
	tier := "premium"
	if free {
		tier = "free"
	}
	return sentence.GenerateSingle(ctx, svc.Gen, sentence.Request{
		SystemPrompt:    sentence.SystemPrompt(!free, l),
		Prompt:          prompt,
		IsPremium:       !free,
		TierLabel:       tier,
		TargetWords:     words,
		ResolvedContext: rc,
		Lang:            l,
	})
}

func summarize(recs []record) {
	var failed int
	for i, r := range recs {
		if r.Err != "" || r.Sentence == nil {
			failed++
			fmt.Printf("%3d r%-5d [%s] 失敗: %s\n", i+1, r.Rank, r.Word, r.Err)
			continue
		}
		c, _ := r.Context["topic"].(string)
		sub, _ := r.Context["subTheme"].(string)
		fmt.Printf("%3d r%-5d [%s] %s\n     %s\n     %s  (%s/%s)\n",
			i+1, r.Rank, r.Word, r.ThaiText, r.Pronunciation,
			r.JapaneseTranslation, truncate(c, 14), sub)
		for _, n := range r.Notes {
			fmt.Printf("     ✗ %s\n", n)
		}
		if r.Retried != nil {
			fmt.Printf("     → %s\n       %s\n       %s\n",
				r.Retried.ThaiText, r.Retried.Pronunciation,
				r.Retried.JapaneseTranslation)
		}
	}
	fmt.Printf("\n生成 %d / 失敗 %d\n", len(recs)-failed, failed)
}

type wordRank struct {
	Word string
	Rank int
}

// pickWords は各帯から均等に語を引く。同じ seed なら同じ語が出るので、
// 改訂前後で同じ語を生成して比べられる。
func pickWords(path string, n int, seed int64) ([]wordRank, error) {
	raw, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	var m map[string]int
	if err := json.Unmarshal(raw, &m); err != nil {
		return nil, err
	}
	byBand := make([][]wordRank, len(bands))
	for w, r := range m {
		for i, b := range bands {
			if r >= b[0] && r <= b[1] {
				byBand[i] = append(byBand[i], wordRank{w, r})
				break
			}
		}
	}
	rng := rand.New(rand.NewSource(seed))
	var out []wordRank
	for i := range byBand {
		sort.Slice(byBand[i], func(a, b int) bool { return byBand[i][a].Rank < byBand[i][b].Rank })
		per := n / len(bands)
		if i < n%len(bands) {
			per++
		}
		rng.Shuffle(len(byBand[i]), func(a, b int) {
			byBand[i][a], byBand[i][b] = byBand[i][b], byBand[i][a]
		})
		if per > len(byBand[i]) {
			per = len(byBand[i])
		}
		out = append(out, byBand[i][:per]...)
	}
	sort.Slice(out, func(a, b int) bool { return out[a].Rank < out[b].Rank })
	return out, nil
}

// pickTopics は固定テーマ1つ、または16種すべてを返す。
func pickTopics(filter string) []string {
	if filter == "" {
		return append([]string(nil), sentence.Topics...)
	}
	for _, t := range sentence.Topics {
		if strings.Contains(t, filter) {
			return []string{t}
		}
	}
	log.Fatalf("テーマが見つからない: %q", filter)
	return nil
}

type randomSubTheme struct{}

func (randomSubTheme) FindBestSubTheme(
	_ context.Context, _ string, subThemes []string,
) (string, error) {
	if len(subThemes) == 0 {
		return "", nil
	}
	return subThemes[rand.Intn(len(subThemes))], nil
}

func tierLabel(free bool) string {
	if free {
		return "free"
	}
	return "premium"
}

func truncate(s string, n int) string {
	r := []rune(s)
	if len(r) <= n {
		return s
	}
	return string(r[:n])
}

func envOr(key, fallback string) string {
	if v := strings.TrimSpace(os.Getenv(key)); v != "" {
		return v
	}
	return fallback
}
