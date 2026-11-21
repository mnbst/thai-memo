// Command tfshot は「時点が要らない」とラベルしたショットで、時点の行を外す効果を比べる実験。
//
//	A: 今の本番。語の時点の表から時点を付ける
//	B: 同じ語・ショット・関係・時点の抽選で、時点の行だけを外す
//
// 入力は {id, word} の配列（ショット ID と key_word）。両方を本番の judge にかけ、
// 合格率と、時点の語を無理に足した文の数（Decisions、参考値）を出す。
//
//	go run ./cmd/tfshot -in pairs.json -out out.json
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

	"github.com/mnbst/thai-memo/functions/go/internal/lang"
	"github.com/mnbst/thai-memo/functions/go/internal/llm"
	"github.com/mnbst/thai-memo/functions/go/internal/quality"
	"github.com/mnbst/thai-memo/functions/go/internal/secrets"
	"github.com/mnbst/thai-memo/functions/go/internal/sentence"
	"github.com/mnbst/thai-memo/functions/go/internal/themeshots"
)

type arm struct {
	TimeFrame string             `json:"time_frame,omitempty"`
	Sentence  *sentence.Sentence `json:"sentence,omitempty"`
	Err       string             `json:"error,omitempty"`
	Pass      *bool              `json:"pass,omitempty"`
	Hits      []string           `json:"hits,omitempty"`
	// Forced は時点の語を無理に足したか（Decisions の確率。参考値）。
	Forced *float64 `json:"forced,omitempty"`
}

type record struct {
	ID    string `json:"id"`
	Word  string `json:"word"`
	Topic string `json:"topic"`
	A     arm    `json:"with_time"`
	B     arm    `json:"no_time"`
}

func main() {
	in := flag.String("in", "", "{id, word} の JSON 配列")
	out := flag.String("out", "", "JSON の出力先")
	vocab := flag.Int("vocab", 800, "estimated_vocab")
	seed := flag.Int64("seed", 1, "抽選シード")
	conc := flag.Int("c", 8, "同時実行数")
	mood := flag.Bool("mood", false, "雰囲気の回（id 空・topic 指定）で、A=関係あり・B=関係なし を比べる（時点はどちらも外す）")
	flag.Parse()

	raw, err := os.ReadFile(*in)
	if err != nil {
		log.Fatal(err)
	}
	var recs []record
	if err := json.Unmarshal(raw, &recs); err != nil {
		log.Fatal(err)
	}
	topicOf := map[string]string{}
	for _, t := range sentence.Topics {
		for _, ids := range themeshots.SceneShots(t) {
			for _, id := range ids {
				topicOf[id] = t
			}
		}
	}
	for i := range recs {
		if recs[i].ID != "" {
			recs[i].Topic = topicOf[recs[i].ID]
		}
	}

	ctx := context.Background()
	key, err := secrets.Get(ctx, "gemini-api-key")
	if err != nil {
		log.Fatalf("gemini-api-key が要る: %v", err)
	}
	model := os.Getenv("GEMINI_MODEL")
	if model == "" {
		model = "gemini-3.1-flash-lite"
	}
	gen := &llm.Client{
		GeminiKey: key, Provider: "gemini", MaxTokens: 8192,
		GeminiModel: model, GeminiModelPremium: model,
	}
	svc := &sentence.Service{Gen: gen, Shots: &themeshots.Builder{}}
	resolver := &sentence.Resolver{Rand: rand.New(rand.NewSource(*seed))}

	// 抽選は A・B 共通（関係・時点を同じにして、違いを時点の行の有無だけにする）。
	resolved := make([]sentence.ResolvedParams, len(recs))
	for i, r := range recs {
		resolved[i] = resolver.Resolve(ctx, map[string]any{
			"topic": r.Topic, "medium": sentence.Media[0].Name,
			"sceneMatched": true, "shotID": r.ID,
		}, []string{r.Word}, *vocab)
	}
	fmt.Fprintf(os.Stderr, "n=%d vocab=%d model=%s\n", len(recs), *vocab, model)

	dec := &quality.Gemini{APIKey: key}
	j, err := quality.NewJudge(ctx)
	if err != nil {
		log.Fatalf("judge を作れない: %v", err)
	}
	parallel(len(recs)*2, *conc, func(k int) {
		r := &recs[k/2]
		a, rp := &r.A, resolved[k/2]
		if *mood {
			rp.TimeFrame = ""
		}
		if k%2 == 1 {
			a = &r.B
			rp.TimeFrame = ""
			if *mood {
				rp.RelationStatus, rp.RelationSpeaker = "", ""
			}
		}
		a.TimeFrame = rp.TimeFrame
		words := []string{r.Word}
		section := svc.SceneSection(&rp, words)
		prompt, rc := sentence.BuildPrompt(rp, words, *vocab, true, lang.JA, section)
		s, err := sentence.GenerateSingle(ctx, gen, sentence.Request{
			SystemPrompt: sentence.SystemPrompt(true, lang.JA), Prompt: prompt,
			IsPremium: true, TierLabel: "premium", TargetWords: words,
			ResolvedContext: rc, Lang: lang.JA,
		})
		if err != nil {
			a.Err = err.Error()
			fmt.Fprint(os.Stderr, "x")
			return
		}
		a.Sentence = s
		res, err := j.Review(ctx, []quality.Candidate{{
			SentenceID: fmt.Sprint(k), ThaiText: s.ThaiText, Pronunciation: s.Pronunciation,
			JapaneseTranslation: s.JapaneseTranslation, KeyWord: r.Word, Topic: r.Topic,
			Lang: lang.JA, Words: qualityWords(s.WordBreakdown),
		}})
		if err == nil {
			pass := len(res.Flagged) == 0 && len(res.Accepted) == 1
			a.Pass = &pass
			if len(res.Verdicts) > 0 {
				a.Hits = res.Verdicts[0].Hits
			}
		}
		if p, err := askForced(ctx, dec, s); err == nil {
			a.Forced = &p
		}
		fmt.Fprint(os.Stderr, ".")
	})
	fmt.Fprintln(os.Stderr)

	if *out != "" {
		b, _ := json.MarshalIndent(recs, "", " ")
		if err := os.WriteFile(*out, b, 0o644); err != nil {
			log.Fatal(err)
		}
		fmt.Fprintf(os.Stderr, "wrote %s\n", *out)
	}
	summarize(recs)
}

// askForced は、文の時点の語（さっき・明日・昨日・いつも 等）が文の目的に要らないのに足されているかの確率。
func askForced(ctx context.Context, g *quality.Gemini, s *sentence.Sentence) (float64, error) {
	input, _ := json.Marshal(map[string]string{
		"thai_text": s.ThaiText, "japanese_translation": s.JapaneseTranslation,
	})
	got, err := g.Ask(ctx, string(input), map[string]string{
		"forced": "`thai_text` に時を表す語句（เมื่อกี้、เพิ่ง、พรุ่งนี้、เมื่อวาน、ทุกวัน、ตอนนี้、เดี๋ยว 等）があり、" +
			"その語句が文の目的（依頼・質問・感想・あいさつ 等）に要らず、後から足したように不自然に付いている。" +
			"時を表す語句が無い文、または時を表す語句が文の意味に必要な文は当てはまらない。",
	})
	return got["forced"], err
}

func parallel(n, conc int, f func(int)) {
	sem := make(chan struct{}, conc)
	var wg sync.WaitGroup
	for i := 0; i < n; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			sem <- struct{}{}
			defer func() { <-sem }()
			f(i)
		}(i)
	}
	wg.Wait()
}

func summarize(recs []record) {
	for _, c := range []struct {
		name string
		get  func(*record) *arm
	}{{"A 時点あり", func(r *record) *arm { return &r.A }}, {"B 時点なし", func(r *record) *arm { return &r.B }}} {
		gen, judged, pass, forced, fn := 0, 0, 0, 0, 0
		hits := map[string]int{}
		for i := range recs {
			a := c.get(&recs[i])
			if a.Sentence == nil {
				continue
			}
			gen++
			if a.Pass != nil {
				judged++
				if *a.Pass {
					pass++
				}
			}
			for _, h := range a.Hits {
				hits[h]++
			}
			if a.Forced != nil {
				fn++
				if *a.Forced >= 0.5 {
					forced++
				}
			}
		}
		var hs []string
		for h, n := range hits {
			hs = append(hs, fmt.Sprintf("%s=%d", h, n))
		}
		sort.Strings(hs)
		fmt.Printf("%s: 生成 %d / 合格 %d/%d (%.0f%%) / 時点を無理に足した %d/%d\n  不合格の観点: %s\n",
			c.name, gen, pass, judged, 100*float64(pass)/float64(max(judged, 1)), forced, fn, strings.Join(hs, " "))
	}
}

func qualityWords(ws []sentence.Word) []quality.Word {
	out := make([]quality.Word, len(ws))
	for i, w := range ws {
		out[i] = quality.Word{Word: w.Word, Meaning: w.Meaning}
	}
	return out
}
