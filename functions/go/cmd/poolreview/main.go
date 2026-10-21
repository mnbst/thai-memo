// Command poolreview は例文プールの確認待ち（Firestore の pool_review）を扱う。
// pool-review スキルから使う。設計は docs/design_listening_playback.md「プールへの追加」。
//
//	list   確認待ち（pending）を JSON で書き出す。Artifact ページの元データ
//	apply  OK / NG の結果を反映する。OK は本番プールへ足し、お手本の音声を作る。NG は rejected
//	audio  本番プールの全文のお手本の音声を作る（最初に1回だけ。既にあるものは作らない）
//
// apply と audio は既定で dry run。-write で書く。
// 音声を先に作るのは prod だけ（dev・tester は再生時に callable が作る分だけ）。
// Cloud TTS は1分あたりの呼び出し数に割り当てがあるので、audio は -rpm で均し、
// 超えたら待ってやり直す。
//
//	GCLOUD_PROJECT=thai-memo-dev go run ./cmd/poolreview list -out /tmp/pending.json
//	GCLOUD_PROJECT=thai-memo-dev go run ./cmd/poolreview apply -in /tmp/decisions.json -write
//	GCLOUD_PROJECT=thai-memo-prod go run ./cmd/poolreview audio -lang ja -tier premium -write
//
// decisions.json は {"ok": [doc ID...], "ng": [doc ID...]}。
package main

import (
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"log"
	"os"
	"sort"
	"sync"
	"sync/atomic"
	"time"

	"cloud.google.com/go/firestore"
	"cloud.google.com/go/storage"
	"google.golang.org/api/googleapi"
	texttospeech "google.golang.org/api/texttospeech/v1"

	"github.com/mnbst/thai-memo/functions/go/internal/lang"
	"github.com/mnbst/thai-memo/functions/go/internal/poolreview"
	"github.com/mnbst/thai-memo/functions/go/internal/sentence"
	"github.com/mnbst/thai-memo/functions/go/internal/ttsaudio"
)

// prodProject は音声を先に作る唯一の環境。
const prodProject = "thai-memo-prod"

func main() {
	if len(os.Args) < 2 {
		log.Fatal("usage: poolreview list|apply|audio [flags]")
	}
	project := os.Getenv("GCLOUD_PROJECT")
	if project == "" {
		log.Fatal("GCLOUD_PROJECT が未設定")
	}
	ctx := context.Background()
	cmd, args := os.Args[1], os.Args[2:]
	var err error
	switch cmd {
	case "list":
		err = runList(ctx, project, args)
	case "apply":
		err = runApply(ctx, project, args)
	case "audio":
		err = runAudio(ctx, project, args)
	default:
		err = fmt.Errorf("不明なサブコマンド %q", cmd)
	}
	if err != nil {
		log.Fatal(err)
	}
}

// item は確認待ちの1件（list の出力）。
type item struct {
	ID       string         `json:"id" firestore:"-"`
	Tier     string         `json:"tier" firestore:"tier"`
	Lang     string         `json:"lang" firestore:"lang"`
	Source   string         `json:"source" firestore:"source"`
	QueuedAt time.Time      `json:"queued_at" firestore:"queued_at"`
	Quality  map[string]any `json:"quality,omitempty" firestore:"quality"`
	Sentence map[string]any `json:"sentence" firestore:"sentence"`
}

func runList(ctx context.Context, project string, args []string) error {
	fs := flag.NewFlagSet("list", flag.ExitOnError)
	out := fs.String("out", "", "書き出す JSON のパス")
	fs.Parse(args)
	if *out == "" {
		return errors.New("-out が必要")
	}
	db, err := firestore.NewClient(ctx, project)
	if err != nil {
		return err
	}
	defer db.Close()
	docs, err := db.Collection(poolreview.Collection).
		Where("status", "==", poolreview.StatusPending).Documents(ctx).GetAll()
	if err != nil {
		return err
	}
	items := make([]item, 0, len(docs))
	for _, d := range docs {
		var it item
		if err := d.DataTo(&it); err != nil {
			return fmt.Errorf("%s: %w", d.Ref.ID, err)
		}
		it.ID = d.Ref.ID
		items = append(items, it)
	}
	sort.Slice(items, func(i, j int) bool { return items[i].QueuedAt.Before(items[j].QueuedAt) })
	data, err := json.MarshalIndent(items, "", " ")
	if err != nil {
		return err
	}
	log.Printf("pending=%d → %s", len(items), *out)
	return os.WriteFile(*out, data, 0o644)
}

func runApply(ctx context.Context, project string, args []string) error {
	fs := flag.NewFlagSet("apply", flag.ExitOnError)
	in := fs.String("in", "", `{"ok": [...], "ng": [...]} の JSON`)
	write := fs.Bool("write", false, "書く（既定は dry run）")
	fs.Parse(args)
	raw, err := os.ReadFile(*in)
	if err != nil {
		return err
	}
	var dec struct {
		OK []string `json:"ok"`
		NG []string `json:"ng"`
	}
	if err := json.Unmarshal(raw, &dec); err != nil {
		return err
	}
	okSet := map[string]bool{}
	for _, id := range dec.OK {
		okSet[id] = true
	}
	for _, id := range dec.NG {
		if okSet[id] {
			return fmt.Errorf("%s が OK と NG の両方にある", id)
		}
	}

	db, err := firestore.NewClient(ctx, project)
	if err != nil {
		return err
	}
	defer db.Close()
	col := db.Collection(poolreview.Collection)

	// 確認待ちのものだけを読む。確認済み（古い結果の流し直し）は飛ばす。
	pending := func(id string) (*firestore.DocumentSnapshot, error) {
		snap, err := col.Doc(id).Get(ctx)
		if err != nil {
			return nil, fmt.Errorf("%s: %w", id, err)
		}
		if st, _ := snap.Data()["status"].(string); st != poolreview.StatusPending {
			log.Printf("skip %s: status=%s", id, st)
			return nil, nil
		}
		return snap, nil
	}

	// OK の文をプールごとに束ねる。
	byPool := map[string][]sentence.Sentence{}
	var okSnaps, ngSnaps []*firestore.DocumentSnapshot
	for _, id := range dec.OK {
		snap, err := pending(id)
		if err != nil {
			return err
		}
		if snap == nil {
			continue
		}
		var it item
		if err := snap.DataTo(&it); err != nil {
			return fmt.Errorf("%s: %w", id, err)
		}
		l, ok := lang.Parse(it.Lang)
		if !ok {
			return fmt.Errorf("%s: lang %q", id, it.Lang)
		}
		b, _ := json.Marshal(it.Sentence)
		var s sentence.Sentence
		if err := json.Unmarshal(b, &s); err != nil {
			return fmt.Errorf("%s: %w", id, err)
		}
		name := sentence.PoolObjectFor(it.Tier, l)
		byPool[name] = append(byPool[name], s)
		okSnaps = append(okSnaps, snap)
	}
	for _, id := range dec.NG {
		snap, err := pending(id)
		if err != nil {
			return err
		}
		if snap != nil {
			ngSnaps = append(ngSnaps, snap)
		}
	}
	for name, ss := range byPool {
		log.Printf("ok: %s +%d", name, len(ss))
	}
	log.Printf("ng: %d", len(ngSnaps))
	if !*write {
		log.Print("dry run（-write で書く）")
		return nil
	}

	gcs, err := storage.NewClient(ctx)
	if err != nil {
		return err
	}
	defer gcs.Close()
	poolBucket := gcs.Bucket(project + "-uvm-data")
	var (
		store ttsaudio.Store
		synth ttsaudio.Synthesizer
	)
	if project == prodProject {
		if store, synth, err = audioDeps(ctx, gcs, project); err != nil {
			return err
		}
	}

	// プールへ足してから状態を書く。途中で落ちても OK の文は pending のまま残り、
	// やり直せば重複なく足される（MergePool が thai_text で重複を飛ばす）。
	for name, ss := range byPool {
		added, err := poolreview.AppendPool(ctx, poolBucket, name, ss)
		if err != nil {
			return fmt.Errorf("%s: %w", name, err)
		}
		log.Printf("pool %s added=%d", name, added)
		// 音声は失敗してもプールの追加は止めない。再生時に callable が埋める。
		if synth == nil {
			continue
		}
		for _, s := range ss {
			res, err := ttsaudio.Ensure(ctx, store, synth, audioInput(s))
			if err == nil {
				err = res.StoreErr
			}
			if err != nil {
				log.Printf("audio failed %q: %v", s.ThaiText, err)
			}
		}
	}
	// 読んだときから変わっていない doc だけを書き換える（並行して流した apply と食い違わない）。
	now := time.Now()
	mark := func(snaps []*firestore.DocumentSnapshot, st string) error {
		for _, snap := range snaps {
			if _, err := snap.Ref.Update(ctx, []firestore.Update{
				{Path: "status", Value: st},
				{Path: "reviewed_at", Value: now},
			}, firestore.LastUpdateTime(snap.UpdateTime)); err != nil {
				return fmt.Errorf("%s: %w", snap.Ref.ID, err)
			}
		}
		return nil
	}
	if err := mark(okSnaps, poolreview.StatusApproved); err != nil {
		return err
	}
	if err := mark(ngSnaps, poolreview.StatusRejected); err != nil {
		return err
	}
	log.Printf("approved=%d rejected=%d", len(okSnaps), len(ngSnaps))
	return nil
}

func runAudio(ctx context.Context, project string, args []string) error {
	fs := flag.NewFlagSet("audio", flag.ExitOnError)
	langCode := fs.String("lang", "ja", "プールの言語（ja / en）")
	tier := fs.String("tier", "premium", "プールのティア（premium / free）")
	conc := fs.Int("c", 4, "同時実行数")
	rpm := fs.Int("rpm", 100, "1分あたりの Cloud TTS 呼び出しの上限（プロジェクトの割り当てより下に置く）")
	write := fs.Bool("write", false, "作る（既定は件数と文字数だけ出す）")
	fs.Parse(args)
	l, ok := lang.Parse(*langCode)
	if !ok {
		return fmt.Errorf("-lang %q", *langCode)
	}
	gcs, err := storage.NewClient(ctx)
	if err != nil {
		return err
	}
	defer gcs.Close()
	name := sentence.PoolObjectFor(*tier, l)
	pool, err := sentence.ReadSentences(ctx, gcs.Bucket(project+"-uvm-data"), name)
	if err != nil {
		return err
	}
	chars := 0
	for _, s := range pool {
		chars += len([]rune(ttsaudio.Normalize(s.ThaiText)))
	}
	log.Printf("%s: %d文・%d文字", name, len(pool), chars)
	if !*write {
		log.Print("dry run（-write で作る）")
		return nil
	}
	if project != prodProject {
		return fmt.Errorf("音声を先に作るのは %s だけ", prodProject)
	}
	store, synth, err := audioDeps(ctx, gcs, project)
	if err != nil {
		return err
	}
	synth = &paced{inner: synth, tick: time.NewTicker(time.Minute / time.Duration(*rpm))}

	var created, existed, failed atomic.Int64
	jobs := make(chan sentence.Sentence)
	var wg sync.WaitGroup
	for range *conc {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for s := range jobs {
				res, err := ttsaudio.Ensure(ctx, store, synth, audioInput(s))
				if err == nil {
					err = res.StoreErr
				}
				switch {
				case err != nil:
					failed.Add(1)
					log.Printf("failed %q: %v", s.ThaiText, err)
				case res.Created:
					created.Add(1)
				default:
					existed.Add(1)
				}
				if n := created.Load() + existed.Load() + failed.Load(); n%500 == 0 {
					log.Printf("%d/%d", n, len(pool))
				}
			}
		}()
	}
	for _, s := range pool {
		jobs <- s
	}
	close(jobs)
	wg.Wait()
	log.Printf("created=%d existed=%d failed=%d", created.Load(), existed.Load(), failed.Load())
	return nil
}

func audioDeps(ctx context.Context, gcs *storage.Client, project string) (ttsaudio.Store, ttsaudio.Synthesizer, error) {
	svc, err := texttospeech.NewService(ctx)
	if err != nil {
		return nil, nil, err
	}
	return ttsaudio.GCSStore{Bucket: gcs.Bucket(ttsaudio.BucketName(project))},
		retrying{ttsaudio.CloudSynthesizer{Service: svc}}, nil
}

// paced は Cloud TTS の呼び出しを一定間隔に均す（1分あたりの割り当てに当てない）。
// GCS に既にあって作らない文は待たない。
type paced struct {
	inner ttsaudio.Synthesizer
	tick  *time.Ticker
}

func (p *paced) Synthesize(ctx context.Context, voice, text string) ([]byte, error) {
	<-p.tick.C
	return p.inner.Synthesize(ctx, voice, text)
}

// retrying は割り当て超過（429）のとき待ってやり直す。
type retrying struct{ inner ttsaudio.Synthesizer }

func (r retrying) Synthesize(ctx context.Context, voice, text string) ([]byte, error) {
	for attempt := 0; ; attempt++ {
		data, err := r.inner.Synthesize(ctx, voice, text)
		var gerr *googleapi.Error
		if err == nil || !errors.As(err, &gerr) || gerr.Code != 429 || attempt == 5 {
			return data, err
		}
		time.Sleep(time.Duration(1<<attempt) * 5 * time.Second)
	}
}

func audioInput(s sentence.Sentence) ttsaudio.Input {
	topic, _ := s.Context["topic"].(string)
	words := make([]ttsaudio.Word, len(s.WordBreakdown))
	for i, w := range s.WordBreakdown {
		words[i] = ttsaudio.Word{Word: w.Word, Meaning: w.Meaning, GrammaticalRole: w.GrammaticalRole}
	}
	return ttsaudio.Input{ThaiText: s.ThaiText, Topic: topic, Words: words}
}
