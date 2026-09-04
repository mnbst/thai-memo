// Command sample は現行プロンプトでオフラインに例文を量産する。
//
// Firestore もクォータも通さず LLM だけを叩くため、プロンプト修正 → 生成 →
// 目視レビューを高速に回せる。ablation 用（旧 scripts/sample_sentences.py の
// 後継。Python 実装の削除で動かなくなったため Go へ移した）。
//
//	GEMINI_API_KEY=... go run ./cmd/sample \
//	  -words "ลอง,แต่ว่า" -vocab 200,800 -n 5 -out /tmp/abl_a.json
//
// 接続の不自然さを測るなら -vocab 1500 -timeframe これからの予定 に寄せる
// （台帳の実測でこの層の NG 率が 12%、他は 0.7〜6%）。
//
// -topic を省くと本番と同じくテーマは LLM が選ぶ。指定するとサブテーマも付く
// （本番は embeddings が選ぶが、ここは GCS を引かずに候補から一様に引く）。
package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"math/rand"
	"os"
	"strconv"
	"strings"
	"sync"

	"github.com/mnbst/thai-memo/functions/go/internal/lang"
	"github.com/mnbst/thai-memo/functions/go/internal/llm"
	"github.com/mnbst/thai-memo/functions/go/internal/secrets"
	"github.com/mnbst/thai-memo/functions/go/internal/sentence"
)

type record struct {
	TargetWord  string `json:"target_word"`
	Vocab       int    `json:"vocab"`
	ThaiText    string `json:"thai_text"`
	Translation string `json:"japanese_translation"`
	// WordCount は word_breakdown の語数（長さヒントの遵守を見る）。
	WordCount int            `json:"word_count"`
	Context   map[string]any `json:"context,omitempty"`
	Error     string         `json:"error,omitempty"`
}

func main() {
	words := flag.String("words", "", "ターゲット語のカンマ区切り（必須）")
	vocabs := flag.String("vocab", "200,800", "estimated_vocab のカンマ区切り")
	n := flag.Int("n", 5, "語×語彙帯ごとの生成数")
	langCode := flag.String("lang", "ja", "訳文の言語（ja / en）")
	free := flag.Bool("free", false, "free ティアのプロンプトで生成する")
	out := flag.String("out", "", "出力 JSON のパス（省略時は標準出力）")
	conc := flag.Int("c", 4, "同時実行数")
	topic := flag.String("topic", "", "テーマを固定する（省略時は LLM に選ばせる）")
	timeFrame := flag.String("timeframe", "",
		"話している時点を固定する（省略時は抽選）: "+strings.Join(sentence.TimeFrames, " / "))
	flag.Parse()

	targetWords := splitCSV(*words)
	if len(targetWords) == 0 {
		log.Fatal("-words は必須")
	}
	var bands []int
	for _, v := range splitCSV(*vocabs) {
		iv, err := strconv.Atoi(v)
		if err != nil {
			log.Fatalf("-vocab の値が数値でない: %q", v)
		}
		bands = append(bands, iv)
	}

	ctx := context.Background()
	key, err := secrets.Get(ctx, "gemini-api-key")
	if err != nil {
		log.Fatalf("GEMINI_API_KEY か gemini-api-key が要る: %v", err)
	}

	model := envOr("GEMINI_MODEL_PREMIUM", "gemini-3.1-flash-lite")
	svc := &sentence.Service{
		Gen: &llm.Client{
			GeminiKey:          key,
			Provider:           "gemini",
			MaxTokens:          8192,
			GeminiModel:        envOr("GEMINI_MODEL", "gemini-3.1-flash-lite"),
			GeminiModelPremium: model,
		},
		// サブテーマは本番なら embeddings が選ぶ。ここは GCS を引かずに
		// 候補からランダムに引く（偏りではなく被覆を見るため）。
		Resolver: &sentence.Resolver{SubThemes: randomSubTheme{}},
	}

	type job struct {
		word  string
		vocab int
	}
	var jobs []job
	for _, w := range targetWords {
		for _, v := range bands {
			for range *n {
				jobs = append(jobs, job{w, v})
			}
		}
	}

	results := make([]record, len(jobs))
	sem := make(chan struct{}, *conc)
	var wg sync.WaitGroup
	for i, j := range jobs {
		wg.Add(1)
		go func() {
			defer wg.Done()
			sem <- struct{}{}
			defer func() { <-sem }()

			rec := record{TargetWord: j.word, Vocab: j.vocab}
			params := map[string]any{}
			if *topic != "" {
				params["topic"] = *topic
			}
			if *timeFrame != "" {
				params["timeFrame"] = *timeFrame
			}
			s, err := svc.GenerateSentence(ctx, params, !*free,
				[]string{j.word}, j.vocab, lang.Lang(*langCode))
			if err != nil {
				rec.Error = err.Error()
			} else {
				rec.ThaiText = s.ThaiText
				rec.Translation = s.JapaneseTranslation
				rec.WordCount = len(s.WordBreakdown)
				rec.Context = s.Context
			}
			results[i] = rec
			fmt.Fprintf(os.Stderr, ".")
		}()
	}
	wg.Wait()
	fmt.Fprintln(os.Stderr)

	data, err := json.MarshalIndent(results, "", "  ")
	if err != nil {
		log.Fatal(err)
	}
	if *out == "" {
		fmt.Println(string(data))
		return
	}
	if err := os.WriteFile(*out, append(data, '\n'), 0o644); err != nil {
		log.Fatal(err)
	}

	var failed int
	for _, r := range results {
		if r.Error != "" {
			failed++
		}
	}
	fmt.Fprintf(os.Stderr, "%d 文を %s へ書いた（失敗 %d）\n",
		len(results)-failed, *out, failed)
}

// randomSubTheme は候補から 1 つ引くだけの SubThemeFinder。
type randomSubTheme struct{}

func (randomSubTheme) FindBestSubTheme(
	_ context.Context, _ string, subThemes []string,
) (string, error) {
	if len(subThemes) == 0 {
		return "", nil
	}
	return subThemes[rand.Intn(len(subThemes))], nil
}

func splitCSV(s string) []string {
	var out []string
	for _, part := range strings.Split(s, ",") {
		if p := strings.TrimSpace(part); p != "" {
			out = append(out, p)
		}
	}
	return out
}

func envOr(key, fallback string) string {
	if v := strings.TrimSpace(os.Getenv(key)); v != "" {
		return v
	}
	return fallback
}
