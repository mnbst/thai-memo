// Command poolreview は例文プールの確認待ち（Firestore の pool_review）を扱う。
// pool-review スキルから使う。設計は docs/design_listening_playback.md「プールへの追加」。
//
//	list   確認待ち（pending）を JSON で書き出す。Artifact ページの元データ
//	apply  OK / NG の結果を反映する。OK は本番プールへ足し、NG は rejected
//
// apply は既定で dry run。-write で書く。
// お手本の音声は先に作らない。再生されたときに getSentenceAudio が作る（2026-10-21）。
//
//	GCLOUD_PROJECT=thai-memo-dev go run ./cmd/poolreview list -out /tmp/pending.json
//	GCLOUD_PROJECT=thai-memo-dev go run ./cmd/poolreview apply -in /tmp/decisions.json -write
//
// decisions.json は {"ok": [doc ID...], "ng": [doc ID...], "fix": {doc ID: {...}}}。
// fix は OK の文の直し（sentence と同じ形の一部。書いたキーだけ差し替える）。
// 直した文をプールへ入れ、元の文は sentence に、直した文は sentence_fixed に残す。
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
	"time"

	"cloud.google.com/go/firestore"
	"cloud.google.com/go/storage"

	"github.com/mnbst/thai-memo/functions/go/internal/lang"
	"github.com/mnbst/thai-memo/functions/go/internal/poolreview"
	"github.com/mnbst/thai-memo/functions/go/internal/sentence"
)

func main() {
	if len(os.Args) < 2 {
		log.Fatal("usage: poolreview list|apply [flags]")
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
		OK  []string                  `json:"ok"`
		NG  []string                  `json:"ng"`
		Fix map[string]map[string]any `json:"fix"`
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
	for id := range dec.Fix {
		if !okSet[id] {
			return fmt.Errorf("%s は fix があるのに OK にない", id)
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
	fixed := map[string]map[string]any{}
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
		s, err := poolreview.ApplyFix(it.Sentence, dec.Fix[id])
		if err != nil {
			return fmt.Errorf("%s: %w", id, err)
		}
		if dec.Fix[id] != nil {
			// Sentence は json タグしか持たないので、Firestore へは JSON の形の map で書く。
			b, _ := json.Marshal(s)
			var m map[string]any
			if err := json.Unmarshal(b, &m); err != nil {
				return fmt.Errorf("%s: %w", id, err)
			}
			fixed[snap.Ref.ID] = m
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
	log.Printf("fixed: %d", len(fixed))
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

	// プールへ足してから状態を書く。途中で落ちても OK の文は pending のまま残り、
	// やり直せば重複なく足される（MergePool が thai_text で重複を飛ばす）。
	for name, ss := range byPool {
		added, err := poolreview.AppendPool(ctx, poolBucket, name, ss)
		if err != nil {
			return fmt.Errorf("%s: %w", name, err)
		}
		log.Printf("pool %s added=%d", name, added)
	}
	// 読んだときから変わっていない doc だけを書き換える（並行して流した apply と食い違わない）。
	now := time.Now()
	mark := func(snaps []*firestore.DocumentSnapshot, st string) error {
		for _, snap := range snaps {
			ups := []firestore.Update{
				{Path: "status", Value: st},
				{Path: "reviewed_at", Value: now},
			}
			if s, ok := fixed[snap.Ref.ID]; ok {
				ups = append(ups, firestore.Update{Path: "sentence_fixed", Value: s})
			}
			if _, err := snap.Ref.Update(ctx, ups, firestore.LastUpdateTime(snap.UpdateTime)); err != nil {
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
