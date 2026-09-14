// Command burst は毎日例文の5本セット配信で増える LLM 同時実行を実測する。
//
// 配信バッチ（deliverDailySentence）は dailySentenceConcurrency 人を並行処理し、
// 5本セット化するとその1人あたりが 5 本の生成を持つ。本番と同じ Service で
// 「users 人 × per 本」を同時に叩き、1本ごとの所要・1人あたりの所要（並列なら
// その人の最大値）・全体の所要・失敗の内訳を出す。
//
//	GEMINI_API_KEY=... go run ./cmd/burst -users 5 -per 5
//	go run ./cmd/burst -users 5 -per 1   # 現行（1本配信）のベースライン
//
// -serial を付けると1人の中を直列にする（並列にしない場合の1人あたり所要）。
package main

import (
	"context"
	"flag"
	"fmt"
	"log"
	"math/rand"
	"os"
	"sort"
	"strings"
	"sync"
	"time"

	"github.com/mnbst/thai-memo/functions/go/internal/lang"
	"github.com/mnbst/thai-memo/functions/go/internal/llm"
	"github.com/mnbst/thai-memo/functions/go/internal/secrets"
	"github.com/mnbst/thai-memo/functions/go/internal/sentence"
)

// probeWords は配信で選ばれうる帯の語。UVM を引かないので固定で持つ。
var probeWords = []string{"ลอง", "แต่ว่า", "เพราะ", "ต้อง", "ยัง", "เคย", "กำลัง", "น่าจะ"}

type call struct {
	user int
	dur  time.Duration
	err  error
}

func main() {
	users := flag.Int("users", 5, "同時に処理するユーザー数（dailySentenceConcurrency 相当）")
	per := flag.Int("per", 5, "1ユーザーあたりの生成本数（DailyBatchSize 相当）")
	serial := flag.Bool("serial", false, "1ユーザー内を直列に生成する")
	vocab := flag.Int("vocab", 800, "estimated_vocab")
	langCode := flag.String("lang", "ja", "訳文の言語（ja / en）")
	flag.Parse()

	ctx := context.Background()
	key, err := secrets.Get(ctx, "gemini-api-key")
	if err != nil {
		log.Fatalf("GEMINI_API_KEY か gemini-api-key が要る: %v", err)
	}
	svc := &sentence.Service{
		Gen: &llm.Client{
			GeminiKey:          key,
			Provider:           "gemini",
			MaxTokens:          8192,
			GeminiModel:        envOr("GEMINI_MODEL", "gemini-3.1-flash-lite"),
			GeminiModelPremium: envOr("GEMINI_MODEL_PREMIUM", "gemini-3.1-flash-lite"),
		},
		Resolver: &sentence.Resolver{SubThemes: randomSubTheme{}},
	}

	fmt.Fprintf(os.Stderr, "users=%d per=%d serial=%v 同時LLM=%d\n",
		*users, *per, *serial, concurrentCalls(*users, *per, *serial))

	results := make(chan call, (*users)*(*per))
	userDur := make([]time.Duration, *users)
	var wg sync.WaitGroup
	start := time.Now()
	for u := range *users {
		wg.Add(1)
		go func(u int) {
			defer wg.Done()
			uStart := time.Now()
			if *serial {
				for i := range *per {
					results <- generate(ctx, svc, u, i, *vocab, *langCode)
				}
			} else {
				var inner sync.WaitGroup
				for i := range *per {
					inner.Add(1)
					go func(i int) {
						defer inner.Done()
						results <- generate(ctx, svc, u, i, *vocab, *langCode)
					}(i)
				}
				inner.Wait()
			}
			userDur[u] = time.Since(uStart)
		}(u)
	}
	wg.Wait()
	total := time.Since(start)
	close(results)

	var durs []time.Duration
	errCount := map[string]int{}
	for r := range results {
		durs = append(durs, r.dur)
		if r.err != nil {
			errCount[classify(r.err)]++
		}
	}
	report(durs, userDur, total, errCount)
}

func generate(
	ctx context.Context, svc *sentence.Service, u, i, vocab int, langCode string,
) call {
	word := probeWords[(u*7+i)%len(probeWords)]
	t := time.Now()
	_, err := svc.GenerateSentence(ctx, map[string]any{}, true,
		[]string{word}, vocab, lang.Lang(langCode))
	if err != nil {
		fmt.Fprint(os.Stderr, "x")
	} else {
		fmt.Fprint(os.Stderr, ".")
	}
	return call{user: u, dur: time.Since(t), err: err}
}

func concurrentCalls(users, per int, serial bool) int {
	if serial {
		return users
	}
	return users * per
}

// classify は失敗を数える単位に落とす。レート制限（429）だけは分けて見たい。
func classify(err error) string {
	s := err.Error()
	switch {
	case strings.Contains(s, "429"), strings.Contains(strings.ToLower(s), "quota"),
		strings.Contains(strings.ToLower(s), "rate"):
		return "429/rate"
	case strings.Contains(s, "500"), strings.Contains(s, "503"):
		return "5xx"
	case strings.Contains(strings.ToLower(s), "deadline"),
		strings.Contains(strings.ToLower(s), "timeout"):
		return "timeout"
	}
	return "other: " + truncate(s, 80)
}

func report(
	durs []time.Duration, userDur []time.Duration,
	total time.Duration, errCount map[string]int,
) {
	sort.Slice(durs, func(i, j int) bool { return durs[i] < durs[j] })
	sort.Slice(userDur, func(i, j int) bool { return userDur[i] < userDur[j] })
	fmt.Println()
	fmt.Printf("1本あたり  n=%d  median=%s  p90=%s  max=%s\n",
		len(durs), pick(durs, 50), pick(durs, 90), pick(durs, 100))
	fmt.Printf("1ユーザー  median=%s  max=%s\n", pick(userDur, 50), pick(userDur, 100))
	fmt.Printf("全体       %s（配信バッチ1周ぶん。関数タイムアウトは 120s）\n", total.Round(time.Millisecond))
	if len(errCount) == 0 {
		fmt.Println("失敗       なし")
		return
	}
	fmt.Println("失敗")
	for k, v := range errCount {
		fmt.Printf("  %-12s %d\n", k, v)
	}
}

func pick(d []time.Duration, pct int) time.Duration {
	if len(d) == 0 {
		return 0
	}
	i := len(d) * pct / 100
	if i >= len(d) {
		i = len(d) - 1
	}
	return d[i].Round(time.Millisecond)
}

func truncate(s string, n int) string {
	if len(s) <= n {
		return s
	}
	return s[:n]
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

func envOr(key, fallback string) string {
	if v := strings.TrimSpace(os.Getenv(key)); v != "" {
		return v
	}
	return fallback
}
