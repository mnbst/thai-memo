// Command vetwords は静的コーパスのターゲット語候補を1語ずつ判定し、
// 除外すべき語の提案を出す。
//
// 頻度リストは字幕由来で、トークナイザが切った断片・固有名詞の一部・
// 誤記が混ざる。これらは語そのものが語でないので、生成プロンプトを
// いくら直しても自然な例文にならない（cmd/pilot の実測で、差し戻しても
// 直らなかった12本のうち9本がこの型）。
//
//	GOOGLE_CLOUD_PROJECT=thai-memo-dev go run ./cmd/vetwords -out /tmp/vet.json
//
// 出力はあくまで提案。scripts/word_denylist.json への反映は人が見て決める。
package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"os"
	"sort"
	"strings"
	"sync"

	"github.com/mnbst/thai-memo/functions/go/internal/llm"
	"github.com/mnbst/thai-memo/functions/go/internal/secrets"
)

const systemPrompt = `あなたはタイ語の辞書編集者。語のリストを受け取り、タイ語学習アプリの
「例文のターゲット単語」として使えるかを1語ずつ判定する。

使えない語は次のどれか。当てはまるものだけ category を付ける。

fragment       単独では語にならない。音節・接頭辞・複合語の一部・単独で現れない拘束形態素
misspelling    誤記、口語の崩した綴り、チャット略記
proper_noun    人名・地名・商標・作品名、またはその一部（タイで一般名詞化した語は除く）
royal          王室用語（ราชาศัพท์）、王室・仏教儀礼に限って使う語
fantasy        神話・魔法・超常の語で、日常会話に出てこないもの
sexual         性行為・性器・性的な接触を指す語
crime_self_harm 犯罪・薬物・自傷・処刑を指す語
profanity      罵倒語・卑語

判定の基準。

- 日常会話で単独の語として使えるなら keep。硬い語・専門語でも、語として
  成立していて一般人が使うなら keep。
- 迷ったら keep。確信のあるものだけ除外する。
- タイ人が普通に使う口語・スラングは、崩した綴りでなければ keep。
- 語の一部かどうかは、その語だけで文中に置けるかで決める。

すべての index に1件ずつ結果を返す。keep のときは category と reason を空にする。`

type wordRank struct {
	Word string `json:"word"`
	Rank int    `json:"rank"`
}

type verdict struct {
	Rank     int    `json:"rank"`
	Word     string `json:"word"`
	Category string `json:"category"`
	Reason   string `json:"reason"`
}

func main() {
	vocab := flag.String("vocab", "../../scripts/corpus/vocab_words.json", "語とrankのリスト")
	deny := flag.String("deny", "../../scripts/word_denylist.json", "すでに除外済みの語")
	maxRank := flag.Int("max-rank", 5256, "この rank までを判定する")
	size := flag.Int("size", 40, "1回の呼び出しに詰める語数")
	conc := flag.Int("c", 8, "同時実行数")
	out := flag.String("out", "/tmp/vet.json", "提案の出力先")
	flag.Parse()

	words, err := loadWords(*vocab, *deny, *maxRank)
	if err != nil {
		log.Fatal(err)
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

	chunks := (len(words) + *size - 1) / *size
	fmt.Fprintf(os.Stderr, "判定 %d語 / %d回 model=%s\n", len(words), chunks, model)

	var mu sync.Mutex
	var drops []verdict
	sem := make(chan struct{}, *conc)
	var wg sync.WaitGroup
	for c := range chunks {
		wg.Add(1)
		go func(c int) {
			defer wg.Done()
			sem <- struct{}{}
			defer func() { <-sem }()

			batch := words[c**size : min((c+1)**size, len(words))]
			got, err := vet(ctx, gen, batch)
			if err != nil {
				log.Printf("判定に失敗 (chunk %d): %v", c, err)
				fmt.Fprint(os.Stderr, "x")
				return
			}
			mu.Lock()
			drops = append(drops, got...)
			mu.Unlock()
			fmt.Fprint(os.Stderr, ".")
		}(c)
	}
	wg.Wait()
	fmt.Fprintln(os.Stderr)

	sort.Slice(drops, func(i, j int) bool { return drops[i].Rank < drops[j].Rank })
	b, _ := json.MarshalIndent(drops, "", " ")
	if err := os.WriteFile(*out, b, 0o644); err != nil {
		log.Fatal(err)
	}
	report(drops, len(words), *out)
}

func vet(ctx context.Context, gen *llm.Client, batch []wordRank) ([]verdict, error) {
	var b strings.Builder
	b.WriteString("次の語を判定する。\n\n")
	for i, w := range batch {
		fmt.Fprintf(&b, "%d. %s\n", i, w.Word)
	}
	raw, err := gen.GenerateSentence(ctx, systemPrompt, b.String(), true, "vetwords", schema())
	if err != nil {
		return nil, err
	}
	items, _ := raw["results"].([]any)
	var out []verdict
	for _, it := range items {
		m, ok := it.(map[string]any)
		if !ok {
			continue
		}
		cat := strings.TrimSpace(str(m, "category"))
		if cat == "" || cat == "keep" {
			continue
		}
		idx, ok := m["index"].(float64)
		if !ok || int(idx) < 0 || int(idx) >= len(batch) {
			continue
		}
		w := batch[int(idx)]
		out = append(out, verdict{
			Rank: w.Rank, Word: w.Word, Category: cat, Reason: str(m, "reason"),
		})
	}
	return out, nil
}

func schema() map[string]any {
	return map[string]any{
		"type":                 "object",
		"additionalProperties": false,
		"properties": map[string]any{
			"results": map[string]any{
				"type": "array",
				"items": map[string]any{
					"type":                 "object",
					"additionalProperties": false,
					"properties": map[string]any{
						"index": map[string]any{"type": "integer"},
						"category": map[string]any{
							"type": "string",
							"description": "除外の理由。使える語なら空文字。" +
								"fragment / misspelling / proper_noun / royal / " +
								"fantasy / sexual / crime_self_harm / profanity",
						},
						"reason": map[string]any{
							"type":        "string",
							"description": "除外の根拠。日本語30文字以内。keep なら空文字。",
						},
					},
					"required": []any{"index", "category", "reason"},
				},
			},
		},
		"required": []any{"results"},
	}
}

// loadWords は rank 順の判定対象を返す。すでに除外済みの語は外す。
func loadWords(vocabPath, denyPath string, maxRank int) ([]wordRank, error) {
	var all []wordRank
	if err := readJSON(vocabPath, &all); err != nil {
		return nil, err
	}
	deny, err := loadDenylist(denyPath)
	if err != nil {
		return nil, err
	}
	var out []wordRank
	for _, w := range all {
		if w.Rank <= maxRank && !deny[w.Word] {
			out = append(out, w)
		}
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Rank < out[j].Rank })
	return out, nil
}

// loadDenylist は word_denylist.json を読む。"_" 始まりのキーは注記なので飛ばす。
func loadDenylist(path string) (map[string]bool, error) {
	var raw map[string]json.RawMessage
	if err := readJSON(path, &raw); err != nil {
		return nil, err
	}
	out := map[string]bool{}
	for k, v := range raw {
		if strings.HasPrefix(k, "_") {
			continue
		}
		var group struct {
			Words []string `json:"words"`
		}
		if err := json.Unmarshal(v, &group); err != nil {
			return nil, fmt.Errorf("%s: %w", k, err)
		}
		for _, w := range group.Words {
			out[w] = true
		}
	}
	return out, nil
}

func report(drops []verdict, total int, out string) {
	byCat := map[string]int{}
	for _, d := range drops {
		byCat[d.Category]++
	}
	cats := make([]string, 0, len(byCat))
	for c := range byCat {
		cats = append(cats, c)
	}
	sort.Slice(cats, func(i, j int) bool { return byCat[cats[i]] > byCat[cats[j]] })
	fmt.Printf("判定 %d語 / 除外提案 %d語 (%.1f%%)\n",
		total, len(drops), float64(len(drops))*100/float64(total))
	for _, c := range cats {
		fmt.Printf("  %-16s %d\n", c, byCat[c])
	}
	fmt.Printf("提案 %s\n", out)
}

func readJSON(path string, v any) error {
	raw, err := os.ReadFile(path)
	if err != nil {
		return err
	}
	return json.Unmarshal(raw, v)
}

func str(m map[string]any, key string) string {
	s, _ := m[key].(string)
	return s
}

func envOr(key, fallback string) string {
	if v := strings.TrimSpace(os.Getenv(key)); v != "" {
		return v
	}
	return fallback
}
