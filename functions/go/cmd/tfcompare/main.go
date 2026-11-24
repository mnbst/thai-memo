// Command tfcompare は「話している時点」の決め方を比べる実験。
//
//	A（random）: 今の本番。語の表（time_frames.json）で絞った候補から一様に引く
//	B（decide）: 語＋参考例文（ショット）を Gemini Decisions に渡し、時点ごとの確率で重みづけて引く
//
// 語ごとにテーマとショットを1つ決め、A と B で同じ語・テーマ・ショットから生成する
// （媒体は対面の会話に固定。解説文では時点を外すため）。両方を本番の judge にかけ、
// 合格率・時点の分布・文に時点が出ているか（Decisions、参考値）を出す。
//
//	go run ./cmd/tfcompare -n 100 -out /tmp/tf.json
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

const rankPath = "../../scripts/corpus/freq_rank_top10000.json"

// bands は cmd/sample と同じランク帯。
var bands = [][2]int{{1, 300}, {301, 500}, {501, 1500}, {1501, 3000}, {3001, 5000}}

// fitThreshold は time_frames.json の絞り込み（timeFrameFitThreshold）と同じ。
const fitThreshold = 0.5

type arm struct {
	TimeFrame string             `json:"time_frame"`
	Probs     []float64          `json:"probs,omitempty"`
	Sentence  *sentence.Sentence `json:"sentence,omitempty"`
	Err       string             `json:"error,omitempty"`
	Pass      *bool              `json:"pass,omitempty"`
	Hits      []string           `json:"hits,omitempty"`
	// Shown は文が TimeFrame のことを言っているか（Decisions の確率。参考値）。
	Shown *float64 `json:"shown,omitempty"`
}

type record struct {
	Rank   int    `json:"key_word_rank"`
	Word   string `json:"key_word"`
	Topic  string `json:"topic"`
	ShotID string `json:"shot_id"`
	Shot   string `json:"shot"`
	A      arm    `json:"random"`
	B      arm    `json:"decide"`
}

func main() {
	n := flag.Int("n", 100, "語の数（A・B で各1文）")
	vocab := flag.Int("vocab", 800, "estimated_vocab")
	seed := flag.Int64("seed", 1, "語・テーマ・ショット・時点の抽選シード")
	conc := flag.Int("c", 5, "同時実行数")
	out := flag.String("out", "", "JSON の出力先")
	flag.Parse()

	ctx := context.Background()
	key, err := secrets.Get(ctx, "gemini-api-key")
	if err != nil {
		log.Fatalf("gemini-api-key が要る: %v", err)
	}
	model := os.Getenv("GEMINI_MODEL")
	if model == "" {
		model = "gemini-3.1-flash-lite"
	}
	dec := &quality.Gemini{APIKey: key}
	shots := &themeshots.Builder{Rand: rand.New(rand.NewSource(*seed))}
	svc := &sentence.Service{
		Gen: &llm.Client{
			GeminiKey: key, Provider: "gemini", MaxTokens: 8192,
			GeminiModel: model, GeminiModelPremium: model,
		},
		Resolver: &sentence.Resolver{},
		Shots:    shots,
	}

	words, err := pickWords(rankPath, *n, *seed)
	if err != nil {
		log.Fatal(err)
	}
	var topics []string
	for i, t := range sentence.Topics {
		if i != 15 && len(themeshots.SceneShots(t)) > 0 {
			topics = append(topics, t)
		}
	}
	rng := rand.New(rand.NewSource(*seed))
	recs := make([]record, len(words))
	for i, w := range words {
		t := topics[i%len(topics)]
		id := shots.PickShot(t, []string{w.Word})
		sec := shots.ShotSection(t, id, sentence.Media[0].Name)
		cands := sentence.TimeFrameCandidates([]string{w.Word})
		recs[i] = record{
			Rank: w.Rank, Word: w.Word, Topic: t, ShotID: id,
			Shot: strings.TrimSpace(sec.Context),
			A:    arm{TimeFrame: cands[rng.Intn(len(cands))]},
		}
	}
	fmt.Fprintf(os.Stderr, "n=%d vocab=%d model=%s topics=%d\n", len(recs), *vocab, model, len(topics))

	// B の時点を Decisions で決める。
	parallel(len(recs), *conc, func(i int) {
		r := &recs[i]
		probs, err := askFrames(ctx, dec, r)
		if err != nil {
			r.B.Err = "decide: " + err.Error()
			return
		}
		r.B.Probs = probs
		r.B.TimeFrame = weightedPick(probs, rand.New(rand.NewSource(*seed+int64(i))))
	})
	fmt.Fprintln(os.Stderr, "decide done")

	// A・B を生成する。
	parallel(len(recs)*2, *conc, func(k int) {
		r := &recs[k/2]
		a := &r.A
		if k%2 == 1 {
			a = &r.B
		}
		if a.Err != "" {
			return
		}
		params := map[string]any{
			"topic": r.Topic, "timeFrame": a.TimeFrame,
			"medium": sentence.Media[0].Name, "sceneMatched": true, "shotID": r.ShotID,
		}
		s, err := svc.GenerateSentence(ctx, params, true, []string{r.Word}, *vocab, lang.JA)
		if err != nil {
			a.Err = err.Error()
			fmt.Fprint(os.Stderr, "x")
			return
		}
		a.Sentence = s
		fmt.Fprint(os.Stderr, ".")
	})
	fmt.Fprintln(os.Stderr)

	// 判定と、文に時点が出ているか。
	j, err := quality.NewJudge(ctx)
	if err != nil {
		log.Fatalf("judge を作れない: %v", err)
	}
	parallel(len(recs)*2, *conc, func(k int) {
		r := &recs[k/2]
		a := &r.A
		if k%2 == 1 {
			a = &r.B
		}
		if a.Sentence == nil {
			return
		}
		s := a.Sentence
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
		if p, err := askShown(ctx, dec, s, a.TimeFrame); err == nil {
			a.Shown = &p
		}
	})

	if *out != "" {
		b, _ := json.MarshalIndent(recs, "", " ")
		if err := os.WriteFile(*out, b, 0o644); err != nil {
			log.Fatal(err)
		}
		fmt.Fprintf(os.Stderr, "wrote %s\n", *out)
	}
	summarize(recs)
}

// askFrames は語と参考例文から、各時点の文が自然に作れるかの確率を TimeFrames の順で返す。
func askFrames(ctx context.Context, g *quality.Gemini, r *record) ([]float64, error) {
	input, _ := json.Marshal(map[string]string{
		"key_word": r.Word, "topic": sentence.TopicLabel(r.Topic), "shot": r.Shot,
	})
	qs := map[string]string{}
	for i, f := range sentence.TimeFrames {
		qs[fmt.Sprint("tf", i)] = "`shot` の場面で、`key_word` を字義どおり使ったタイ語の話し言葉の1文を作る。" +
			"その1文を「" + f + "」を述べる文にしても、場面と `key_word` の意味に無理なく合う。"
	}
	got, err := g.Ask(ctx, string(input), qs)
	if err != nil {
		return nil, err
	}
	probs := make([]float64, len(sentence.TimeFrames))
	for i := range probs {
		probs[i] = got[fmt.Sprint("tf", i)]
	}
	return probs, nil
}

// askShown は文が frame のことを述べているかの確率。
func askShown(ctx context.Context, g *quality.Gemini, s *sentence.Sentence, frame string) (float64, error) {
	input, _ := json.Marshal(map[string]string{
		"thai_text": s.ThaiText, "japanese_translation": s.JapaneseTranslation,
	})
	got, err := g.Ask(ctx, string(input), map[string]string{
		"shown": "`thai_text` は「" + frame + "」を述べる文になっている。",
	})
	return got["shown"], err
}

// weightedPick は閾値以上（届かなければ最大）の時点から、確率の重みで1つ引く。
func weightedPick(probs []float64, rng *rand.Rand) string {
	best := 0
	for i, p := range probs {
		if p > probs[best] {
			best = i
		}
	}
	total := 0.0
	w := make([]float64, len(probs))
	for i, p := range probs {
		if p >= fitThreshold || i == best {
			w[i] = p
			total += p
		}
	}
	x := rng.Float64() * total
	for i, v := range w {
		if v == 0 {
			continue
		}
		if x < v {
			return sentence.TimeFrames[i]
		}
		x -= v
	}
	return sentence.TimeFrames[best]
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
	type stat struct {
		gen, judged, pass, shownN int
		shown                     float64
		frames                    map[string]int
		hits                      map[string]int
	}
	sum := func(get func(*record) *arm) stat {
		st := stat{frames: map[string]int{}, hits: map[string]int{}}
		for i := range recs {
			a := get(&recs[i])
			if a.Sentence == nil {
				continue
			}
			st.gen++
			st.frames[a.TimeFrame]++
			if a.Pass != nil {
				st.judged++
				if *a.Pass {
					st.pass++
				}
			}
			for _, h := range a.Hits {
				st.hits[h]++
			}
			if a.Shown != nil {
				st.shownN++
				if *a.Shown >= 0.5 {
					st.shown++
				}
			}
		}
		return st
	}
	for _, c := range []struct {
		name string
		get  func(*record) *arm
	}{{"A random", func(r *record) *arm { return &r.A }}, {"B decide", func(r *record) *arm { return &r.B }}} {
		st := sum(c.get)
		fmt.Printf("%s: 生成 %d / 合格 %d/%d (%.0f%%) / 時点が文に出た %.0f/%d\n",
			c.name, st.gen, st.pass, st.judged, pct(st.pass, st.judged), st.shown, st.shownN)
		for _, f := range sentence.TimeFrames {
			fmt.Printf("  %-12s %d\n", f, st.frames[f])
		}
		var hs []string
		for h, n := range st.hits {
			hs = append(hs, fmt.Sprintf("%s=%d", h, n))
		}
		sort.Strings(hs)
		fmt.Printf("  不合格の観点: %s\n", strings.Join(hs, " "))
	}
	same := 0
	for _, r := range recs {
		if r.A.TimeFrame == r.B.TimeFrame {
			same++
		}
	}
	fmt.Printf("A と B で時点が同じ語: %d/%d\n", same, len(recs))
}

func pct(a, b int) float64 {
	if b == 0 {
		return 0
	}
	return 100 * float64(a) / float64(b)
}

type wordRank struct {
	Word string
	Rank int
}

// pickWords は cmd/sample と同じく各帯から均等に語を引く。
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

func qualityWords(ws []sentence.Word) []quality.Word {
	out := make([]quality.Word, len(ws))
	for i, w := range ws {
		out[i] = quality.Word{Word: w.Word, Meaning: w.Meaning}
	}
	return out
}
