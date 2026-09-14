// Command corpus は静的コーパスの生成マニフェストを作る。
//
// (語, テーマ, サブテーマ) の組を、本番と同じ選出ロジックで確定させる。
// テーマ選出は uvm.TopicMatchThreshold / TopicMatchTopK、サブテーマ選出は
// embeddings.FindBestSubTheme をそのまま呼ぶので、アプリが今出している
// 組み合わせの範囲から外れない。
//
//	go run ./cmd/corpus -dir ../../scripts/corpus -out /tmp/manifest.jsonl
package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"math/rand"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"github.com/mnbst/thai-memo/functions/go/internal/embeddings"
	"github.com/mnbst/thai-memo/functions/go/internal/sentence"
	"github.com/mnbst/thai-memo/functions/go/internal/uvm"
)

// lengthBands は rank -> 長さヒント。ランクが下がるほど文を長くする。
// 現行の estimated_vocab 連動（prompts_data.go の introLengthHints）は
// ユーザーごとの値なので静的コーパスでは使えず、rank に置き換える。
var lengthBands = []struct {
	MaxRank int
	Hint    string
	// KnownRank はターゲット語以外に使ってよい語の rank 上限。
	// 静的コーパスでは難易度をユーザーに合わせられないので、ここが効く。
	KnownRank int
}{
	{MaxRank: 500, Hint: "4〜6単語", KnownRank: 800},
	{MaxRank: 1500, Hint: "6〜8単語", KnownRank: 2000},
	{MaxRank: 3000, Hint: "8〜11単語", KnownRank: 3500},
	{MaxRank: 5000, Hint: "11〜14単語", KnownRank: 6000},
}

// item はマニフェスト1行。1行が例文1本に対応する。
type item struct {
	Rank int    `json:"key_word_rank"`
	Word string `json:"key_word"`
	// Topic が空文字になることはない。閾値未達の語は全テーマを候補にする。
	Topic string `json:"topic"`
	// TopicSim はテーマとの生のコサイン類似度。重みとして持つ。
	TopicSim float64 `json:"topic_sim"`
	// TopicGated は閾値未達で全テーマに開いた語。テーマ依存が弱い印。
	TopicGated bool    `json:"topic_unmatched,omitempty"`
	SubTheme   string  `json:"sub_theme,omitempty"`
	SubWeight  float64 `json:"sub_theme_weight,omitempty"`
	LengthHint string  `json:"length_hint"`
	KnownRank  int     `json:"known_rank_max"`
}

func main() {
	dir := flag.String("dir", "../../scripts/corpus", "embedding データのディレクトリ")
	out := flag.String("out", "", "JSONL の出力先。空なら統計のみ")
	maxRank := flag.Int("max-rank", 5000, "対象にする rank の上限")
	seed := flag.Int64("seed", 1, "サブテーマ抽選のシード")
	labels := flag.String("labels", "", "テーマ／サブテーマのラベルを JSON で書き出して終了")
	// scripts/corpus/ は .gitignore 対象（生成物置き場）なので、
	// 手で保守する除外リストはその外に置く。
	denylist := flag.String("denylist", "../../scripts/word_denylist.json",
		"除外語リスト（JSON）")
	// 除外語のぶんを rank の続きから補充して語数を保つのが既定。
	// 帯ごとの文数はこの語数を前提に見積もってある。
	backfill := flag.Bool("backfill", true, "除外したぶんを rank の続きから補充して語数を保つ")
	flag.Parse()

	if *labels != "" {
		if err := dumpLabels(*labels); err != nil {
			log.Fatal(err)
		}
		fmt.Fprintf(os.Stderr, "wrote %s\n", *labels)
		return
	}

	store, topicEmbs, subEmbs, words, err := loadStore(*dir, *seed)
	if err != nil {
		log.Fatal(err)
	}
	deny, denyReason, err := loadDenylist(*denylist)
	if err != nil {
		log.Fatal(err)
	}
	ctx := context.Background()

	// 除外語を飛ばすと語数が減る。-backfill なら rank の続きから埋めて
	// 語数を保つ（帯ごとの文数の設計を崩さないため）。
	limit := *maxRank
	if *backfill {
		limit = backfillLimit(words, deny, *maxRank)
	}

	var items []item
	var unmatched int
	dropped := map[string]int{}
	for _, w := range words {
		if w.Rank < 1 || w.Rank > limit {
			continue
		}
		if deny[w.Word] {
			dropped[denyReason[w.Word]]++
			continue
		}
		wordEmb := store.Embedding(w.Word)
		if wordEmb == nil {
			log.Printf("embedding が無い: %s (r%d)", w.Word, w.Rank)
			continue
		}
		picked, gated := pickTopics(wordEmb, topicEmbs)
		if gated {
			unmatched++
		}
		hint, known := lengthFor(w.Rank)
		for _, p := range picked {
			it := item{
				Rank: w.Rank, Word: w.Word, Topic: p.topic, TopicSim: p.sim,
				TopicGated: gated, LengthHint: hint, KnownRank: known,
			}
			sub, weight, err := pickSubTheme(ctx, store, subEmbs, w.Word, p.topic)
			if err != nil {
				log.Fatalf("サブテーマ選出に失敗 %s/%s: %v", w.Word, p.topic, err)
			}
			it.SubTheme, it.SubWeight = sub, weight
			items = append(items, it)
		}
	}

	if *out != "" {
		if err := writeJSONL(*out, items); err != nil {
			log.Fatal(err)
		}
		fmt.Fprintf(os.Stderr, "wrote %s\n", *out)
	}
	report(items, unmatched, limit)
	if len(dropped) > 0 {
		fmt.Printf("\n除外語（rank<=%d）\n", limit)
		for _, k := range sortedCounts(dropped) {
			fmt.Printf("  %-16s %d語\n", k, dropped[k])
		}
	}
}

type topicPick struct {
	topic string
	sim   float64
}

// pickTopics は本番の FindBestTopic と同じ基準でテーマを残す。
//
// 違いは最後だけ。FindBestTopic は残った候補から1つ引くが、コーパスでは
// 残った候補すべてを採る（ユーザーごとの抽選を、全通り持つことで置き換える）。
// 並び順とトップ K の切り方は本番に合わせてある。
func pickTopics(wordEmb []float32, topicEmbs map[string][]float32) ([]topicPick, bool) {
	var scored []topicPick
	for _, t := range sentence.Topics {
		emb, ok := topicEmbs[t]
		if !ok {
			continue
		}
		scored = append(scored, topicPick{t, embeddings.CosineSimilarity(wordEmb, emb)})
	}
	// FindBestTopic と同じ並び（類似度の降順、同点はテーマ文字列の降順）。
	sort.SliceStable(scored, func(a, b int) bool {
		if scored[a].sim != scored[b].sim {
			return scored[a].sim > scored[b].sim
		}
		return scored[a].topic > scored[b].topic
	})

	var passed []topicPick
	for _, e := range scored {
		if e.sim >= uvm.TopicMatchThreshold {
			passed = append(passed, e)
		}
	}
	if len(passed) == 0 {
		// 閾値未達。本番は topic="" にして LLM に候補から選ばせるので、
		// コーパスでは全テーマを候補として持つ。
		return scored, true
	}
	if uvm.TopicMatchTopK < len(passed) {
		passed = passed[:uvm.TopicMatchTopK]
	}
	return passed, false
}

// pickSubTheme は本番の FindBestSubTheme をそのまま呼び、
// 選ばれたサブテーマの重み（min-max 正規化 + 下駄 0.1）を併せて返す。
func pickSubTheme(
	ctx context.Context, store *embeddings.Store,
	subEmbs map[string][]float32, word, topic string,
) (string, float64, error) {
	subs := sentence.SubThemesFor(topic)
	if len(subs) == 0 {
		return "", 0, nil
	}
	chosen, err := store.FindBestSubTheme(ctx, word, subs)
	if err != nil || chosen == "" {
		return chosen, 0, err
	}

	wordEmb := store.Embedding(word)
	var sims []float64
	var items []string
	for _, st := range subs {
		emb, ok := subEmbs[st]
		if !ok {
			continue
		}
		sims = append(sims, embeddings.CosineSimilarity(wordEmb, emb))
		items = append(items, st)
	}
	weights, ok := embeddings.PickWeights(sims)
	if !ok {
		return chosen, 0, nil
	}
	for i, st := range items {
		if st == chosen {
			return chosen, weights[i], nil
		}
	}
	return chosen, 0, nil
}

func lengthFor(rank int) (string, int) {
	for _, b := range lengthBands {
		if rank <= b.MaxRank {
			return b.Hint, b.KnownRank
		}
	}
	last := lengthBands[len(lengthBands)-1]
	return last.Hint, last.KnownRank
}

func loadStore(dir string, seed int64) (
	*embeddings.Store, map[string][]float32, map[string][]float32,
	[]embeddings.Word, error,
) {
	npy, err := os.ReadFile(filepath.Join(dir, "vocab_embeddings.npy"))
	if err != nil {
		return nil, nil, nil, nil, err
	}
	var words []embeddings.Word
	if err := readJSON(filepath.Join(dir, "vocab_words.json"), &words); err != nil {
		return nil, nil, nil, nil, err
	}
	topicEmbs := map[string][]float32{}
	if err := readJSON(filepath.Join(dir, "topic_embeddings.json"), &topicEmbs); err != nil {
		return nil, nil, nil, nil, err
	}
	subEmbs := map[string][]float32{}
	if err := readJSON(filepath.Join(dir, "sub_theme_embeddings.json"), &subEmbs); err != nil {
		return nil, nil, nil, nil, err
	}

	store := &embeddings.Store{Rand: rand.New(rand.NewSource(seed))}
	if err := store.LoadFromBytes(npy, words); err != nil {
		return nil, nil, nil, nil, err
	}
	store.SetNamedEmbeddings(topicEmbs, subEmbs, nil)
	sort.Slice(words, func(a, b int) bool { return words[a].Rank < words[b].Rank })
	return store, topicEmbs, subEmbs, words, nil
}

func readJSON(path string, v any) error {
	raw, err := os.ReadFile(path)
	if err != nil {
		return err
	}
	return json.Unmarshal(raw, v)
}

func writeJSONL(path string, items []item) error {
	f, err := os.Create(path)
	if err != nil {
		return err
	}
	defer f.Close()
	enc := json.NewEncoder(f)
	for _, it := range items {
		if err := enc.Encode(it); err != nil {
			return err
		}
	}
	return nil
}

func report(items []item, unmatched, maxRank int) {
	bands := [][2]int{{1, 300}, {301, 500}, {501, 1500}, {1501, 3000}, {3001, 5000}}
	// -backfill で rank 上限が伸びるぶんは最終帯に入れる。
	if last := &bands[len(bands)-1]; maxRank > last[1] {
		last[1] = maxRank
	}
	wordsIn := map[int]map[string]bool{}
	count := map[int]int{}
	noSub := 0
	for _, it := range items {
		if it.SubTheme == "" {
			noSub++
		}
		for bi, b := range bands {
			if it.Rank >= b[0] && it.Rank <= b[1] {
				count[bi]++
				if wordsIn[bi] == nil {
					wordsIn[bi] = map[string]bool{}
				}
				wordsIn[bi][it.Word] = true
				break
			}
		}
	}
	fmt.Printf("%10s %6s %7s %10s\n", "帯", "語", "文", "テーマ/語")
	total := 0
	for bi, b := range bands {
		if b[0] > maxRank {
			break
		}
		n, w := count[bi], len(wordsIn[bi])
		total += n
		per := 0.
		if w > 0 {
			per = float64(n) / float64(w)
		}
		fmt.Printf("%4d-%-5d %6d %7d %10.2f\n", b[0], b[1], w, n, per)
	}
	fmt.Printf("%10s %6s %7d\n", "計", "", total)
	fmt.Printf("\n閾値未達（全テーマに開いた語） %d\nサブテーマ無し %d\n", unmatched, noSub)
}

// dumpLabels はテーマとサブテーマのラベルを書き出す。
//
// embedding を作り直す側（scripts/build_theme_embeddings.py）が、
// prompts_data.go を正本として読めるようにするためのもの。
// ラベルを手で写すと、今回のように Go 側だけ改名されて
// embedding が古いラベルのまま残る。
func dumpLabels(path string) error {
	out := struct {
		Topics    []string            `json:"topics"`
		SubThemes map[string][]string `json:"sub_themes"`
	}{
		Topics:    append([]string(nil), sentence.Topics...),
		SubThemes: map[string][]string{},
	}
	for _, t := range sentence.Topics {
		if subs := sentence.SubThemesFor(t); len(subs) > 0 {
			out.SubThemes[t] = subs
		}
	}
	b, err := json.MarshalIndent(out, "", " ")
	if err != nil {
		return err
	}
	return os.WriteFile(path, append(b, '\n'), 0o644)
}

// loadDenylist は除外語リストを読む。語 -> 分類 も返す（内訳を出すため）。
func loadDenylist(path string) (map[string]bool, map[string]string, error) {
	raw, err := os.ReadFile(path)
	if err != nil {
		if os.IsNotExist(err) {
			return map[string]bool{}, map[string]string{}, nil
		}
		return nil, nil, err
	}
	// "_comment" のような注記が同じ階層に混ざるので、先に生で受ける。
	var doc map[string]json.RawMessage
	if err := json.Unmarshal(raw, &doc); err != nil {
		return nil, nil, err
	}
	deny := map[string]bool{}
	reason := map[string]string{}
	for category, rawCat := range doc {
		if strings.HasPrefix(category, "_") {
			continue
		}
		var v struct {
			Words []string `json:"words"`
		}
		if err := json.Unmarshal(rawCat, &v); err != nil {
			return nil, nil, fmt.Errorf("%s: %w", category, err)
		}
		for _, w := range v.Words {
			deny[w] = true
			if _, ok := reason[w]; !ok {
				reason[w] = category
			}
		}
	}
	return deny, reason, nil
}

// backfillLimit は除外語を飛ばしても maxRank 件の語が残る rank 上限を返す。
func backfillLimit(words []embeddings.Word, deny map[string]bool, maxRank int) int {
	kept := 0
	for _, w := range words {
		if w.Rank < 1 || deny[w.Word] {
			continue
		}
		kept++
		if kept == maxRank {
			return w.Rank
		}
	}
	return maxRank
}

func sortedCounts(m map[string]int) []string {
	out := make([]string, 0, len(m))
	for k := range m {
		out = append(out, k)
	}
	sort.Slice(out, func(a, b int) bool {
		if m[out[a]] != m[out[b]] {
			return m[out[a]] > m[out[b]]
		}
		return out[a] < out[b]
	})
	return out
}
