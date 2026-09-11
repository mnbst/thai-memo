// Command gencorpus は静的コーパスを全量生成する。
//
// 入力は cmd/corpus のマニフェスト（1行1文）、出力は1行1件の JSONL。
// 経路は cmd/pilot と同じで、規模と中断復帰だけが違う。
//
//	go run ./cmd/corpus -out /tmp/manifest.jsonl
//	GOOGLE_CLOUD_PROJECT=thai-memo-dev go run ./cmd/gencorpus \
//	  -in /tmp/manifest.jsonl -out /tmp/corpus_ja.jsonl -c 10
//
// ブロック（既定200件）単位で 生成 → 判定 → 差し戻し → 再判定 まで通し、
// 終わるごとに追記する。同じ -out を指して再実行すると、書けている
// (key_word, topic) を飛ばして続きから流す。
//
// 出力の status
//
//	ok       一発で判定を通った
//	repaired 差し戻し1回で通った（sentence は作り直したほう）
//	rejected 2回とも通らなかった（sentence は1回目、notes に指摘）
//	error    生成が返らなかった
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
	Rank           int     `json:"key_word_rank"`
	Word           string  `json:"key_word"`
	Topic          string  `json:"topic"`
	TopicSim       float64 `json:"topic_sim"`
	SubTheme       string  `json:"sub_theme"`
	SubThemeWeight float64 `json:"sub_theme_weight"`
	LengthHint     string  `json:"length_hint"`
	KnownRank      int     `json:"known_rank_max"`
}

// key は (語, テーマ) の組。マニフェストではこの組が1行に1つしかないので、
// 中断復帰の突き合わせに使える。
func (r row) key() string { return r.Word + "\x00" + r.Topic }

type record struct {
	row
	// TargetWord は row.Word の控え。埋め込みの key_word は
	// Sentence 側の同名フィールドとぶつかって JSON から落ちる。
	TargetWord string             `json:"target_word"`
	Status     string             `json:"status"`
	Err        string             `json:"error,omitempty"`
	Notes      []string           `json:"notes,omitempty"`
	Retried    *sentence.Sentence `json:"retried,omitempty"`
	*sentence.Sentence
}

func main() {
	in := flag.String("in", "/tmp/manifest.jsonl", "cmd/corpus のマニフェスト")
	out := flag.String("out", "/tmp/corpus_ja.jsonl", "JSONL の出力先（追記）")
	langCode := flag.String("lang", "ja", "訳文の言語（ja / en）")
	conc := flag.Int("c", 10, "同時実行数")
	block := flag.Int("block", 200, "追記するまとまりの件数")
	limit := flag.Int("limit", 0, "先頭 N 件だけ流す（0 は全部）")
	maxRank := flag.Int("max-rank", 0, "この頻度ランクまでで切る（0 は全部）")
	redo := flag.Bool("redo-rejected", false, "判定を通らなかった行をもう一度流す")
	flag.Parse()

	rows, err := loadRows(*in)
	if err != nil {
		log.Fatal(err)
	}
	done, err := loadDone(*out, *redo)
	if err != nil {
		log.Fatal(err)
	}
	var todo []row
	for _, r := range rows {
		if *maxRank > 0 && r.Rank > *maxRank {
			continue
		}
		if !done[r.key()] {
			todo = append(todo, r)
		}
	}
	if *limit > 0 && *limit < len(todo) {
		todo = todo[:*limit]
	}
	fmt.Fprintf(os.Stderr, "マニフェスト %d件 / 済み %d件 / これから %d件\n",
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
	svc := &sentence.Service{
		Gen: &llm.Client{
			GeminiKey: key, Provider: "gemini", MaxTokens: 8192,
			GeminiModel: model, GeminiModelPremium: model,
		},
		Resolver: &sentence.Resolver{},
		Drama:    &bldrama.Builder{},
	}
	l := lang.Lang(*langCode)

	f, err := os.OpenFile(*out, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0o644)
	if err != nil {
		log.Fatal(err)
	}
	defer f.Close()

	start := time.Now()
	var tot totals
	for lo := 0; lo < len(todo); lo += *block {
		hi := min(lo+*block, len(todo))
		recs := runBlock(ctx, svc, todo[lo:hi], l, *conc)
		if err := appendJSONL(f, recs); err != nil {
			log.Fatal(err)
		}
		tot.add(recs)
		tot.progress(lo+len(recs), len(todo), start)
	}
	tot.report(time.Since(start))
}

// runBlock は1まとまりを 生成 → 判定 → 差し戻し → 再判定 まで通す。
func runBlock(
	ctx context.Context, svc *sentence.Service, rows []row, l lang.Lang, conc int,
) []record {
	recs := make([]record, len(rows))
	parallel(len(rows), conc, func(i int) {
		recs[i] = record{row: rows[i], TargetWord: rows[i].Word, Status: "ok"}
		s, err := generate(ctx, svc, rows[i], l, nil)
		if err != nil {
			recs[i].Status, recs[i].Err = "error", err.Error()
			return
		}
		recs[i].Sentence = s
	})

	for i, notes := range judge(ctx, svc, recs, func(r *record) *sentence.Sentence { return r.Sentence }, conc) {
		recs[i].Notes = notes
		recs[i].Status = "rejected"
	}

	var retryIdx []int
	for i := range recs {
		if recs[i].Status == "rejected" {
			retryIdx = append(retryIdx, i)
		}
	}
	parallel(len(retryIdx), conc, func(k int) {
		i := retryIdx[k]
		s, err := generate(ctx, svc, recs[i].row, l, recs[i].Notes)
		if err != nil {
			return
		}
		recs[i].Retried = s
	})

	second := judge(ctx, svc, recs, func(r *record) *sentence.Sentence { return r.Retried }, conc)
	for i := range recs {
		if recs[i].Retried != nil && len(second[i]) == 0 {
			recs[i].Status = "repaired"
		}
	}
	return recs
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
	// 時点と関係だけ抽選させる。サブテーマと長さはマニフェストの値で上書きする。
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
	req := sentence.Request{
		SystemPrompt:    sentence.SystemPrompt(true, l),
		Prompt:          prompt,
		IsPremium:       true,
		TierLabel:       "premium",
		TargetWords:     words,
		ResolvedContext: rc,
		Lang:            l,
	}
	s, err := sentence.GenerateSingle(ctx, svc.Gen, req)
	if err == nil || !strings.Contains(err.Error(), "target words missing") {
		return s, err
	}

	// 頻度表には มีปัญหา のような連語も入っている。分かち書きは มี と ปัญหา に
	// 割るので、word_breakdown に1項目として出ることがなく検証を必ず落とす。
	// 配信では作り直して別の語に逃がせばいいが、コーパスは語が決まっているので
	// 逃げ場がない。検証を外して作り、文の中に連語として出ていれば採る。
	req.TargetWords = nil
	s, err = sentence.GenerateSingle(ctx, svc.Gen, req)
	if err != nil {
		return nil, err
	}
	if !strings.Contains(strip(s.ThaiText), strip(r.Word)) {
		return nil, fmt.Errorf("LLM_API_ERROR: target word missing in text: %s", r.Word)
	}
	return s, nil
}

// strip は連語の照合用に空白を落とす。分かち書きの位置が違っても、
// 連語が文字の並びとして出ていれば同じ語として扱う。
func strip(s string) string { return strings.ReplaceAll(s, " ", "") }

// judge は pick で取り出した文をまとめて判定し、index ごとの指摘を返す。
// 指摘が空なら合格、pick が nil を返した index は結果に入らない。
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
	return notes
}

type totals struct{ ok, repaired, rejected, failed int }

func (t *totals) add(recs []record) {
	for _, r := range recs {
		switch r.Status {
		case "ok":
			t.ok++
		case "repaired":
			t.repaired++
		case "rejected":
			t.rejected++
		default:
			t.failed++
		}
	}
}

func (t *totals) progress(done, total int, start time.Time) {
	el := time.Since(start)
	eta := time.Duration(float64(el) / float64(done) * float64(total-done))
	fmt.Fprintf(os.Stderr, "%d/%d  合格 %.0f%%（一発 %d + 差し戻し %d）"+
		" 不合格 %d 失敗 %d  経過 %s 残り約 %s\n",
		done, total, pct(t.ok+t.repaired, done), t.ok, t.repaired,
		t.rejected, t.failed, el.Round(time.Minute), eta.Round(time.Minute))
}

func (t *totals) report(elapsed time.Duration) {
	n := t.ok + t.repaired + t.rejected + t.failed
	fmt.Printf("\n生成 %d本  %s\n", n, elapsed.Round(time.Second))
	fmt.Printf("一発合格   %d (%.1f%%)\n", t.ok, pct(t.ok, n))
	fmt.Printf("差し戻し成功 %d (%.1f%%)\n", t.repaired, pct(t.repaired, n))
	fmt.Printf("不合格     %d (%.1f%%)\n", t.rejected, pct(t.rejected, n))
	fmt.Printf("生成失敗   %d\n", t.failed)
}

func loadRows(path string) ([]row, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()
	var all []row
	sc := bufio.NewScanner(f)
	sc.Buffer(make([]byte, 1<<20), 1<<20)
	for sc.Scan() {
		if strings.TrimSpace(sc.Text()) == "" {
			continue
		}
		var r row
		if err := json.Unmarshal(sc.Bytes(), &r); err != nil {
			return nil, err
		}
		all = append(all, r)
	}
	return all, sc.Err()
}

// loadDone は書けている行の (語, テーマ) を集める。壊れた末尾行と生成に
// 失敗した行は入れない（中断すると最後の1行が切れることがある。どちらも
// もう一度生成される。重複して書けた行は詰め込み時に後勝ちで潰れる）。
func loadDone(path string, redo bool) (map[string]bool, error) {
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
		var r struct {
			Word   string `json:"target_word"`
			Topic  string `json:"topic"`
			Status string `json:"status"`
		}
		if json.Unmarshal(sc.Bytes(), &r) != nil || r.Word == "" {
			continue
		}
		// 生成に失敗した行は済みにしない。再実行でもう一度流す。
		if r.Status == "error" {
			continue
		}
		// -redo-rejected では不合格も済みにしない。2回で直らなかった文も、
		// 場面と時点を引き直せば通ることがある（語そのものが無理なら何度でも落ちる）。
		if redo && r.Status == "rejected" {
			continue
		}
		done[r.Word+"\x00"+r.Topic] = true
	}
	return done, sc.Err()
}

func appendJSONL(f *os.File, recs []record) error {
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

func pct(a, b int) float64 {
	if b == 0 {
		return 0
	}
	return float64(a) * 100 / float64(b)
}

func envOr(key, fallback string) string {
	if v := strings.TrimSpace(os.Getenv(key)); v != "" {
		return v
	}
	return fallback
}
