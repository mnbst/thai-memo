package main

// ネイティブ確認（プールに前からある文を表で見てもらう）。流れは internal/poolreview/native.go。
//
//	GCLOUD_PROJECT=thai-memo-prod go run ./cmd/poolreview sample -n 100 -out $S/native.csv -write
//	GCLOUD_PROJECT=thai-memo-prod go run ./cmd/poolreview native -in $S/filled.csv -needs $S/needs.json
//	GCLOUD_PROJECT=thai-memo-prod go run ./cmd/poolreview native -in $S/filled.csv -fix $S/fix.json -write

import (
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"log"
	"math/rand/v2"
	"os"
	"time"

	"cloud.google.com/go/firestore"
	"cloud.google.com/go/storage"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"

	"github.com/mnbst/thai-memo/functions/go/internal/lang"
	"github.com/mnbst/thai-memo/functions/go/internal/poolreview"
	"github.com/mnbst/thai-memo/functions/go/internal/sentence"
)

// runSample は未確認のプールの文から無作為に n 本選び、表を書き出す。
// -write で選んだ文を確認待ちへ StatusNative で入れる（次の回に同じ文を選ばない）。
func runSample(ctx context.Context, project string, args []string) error {
	fs := flag.NewFlagSet("sample", flag.ExitOnError)
	tier := fs.String("tier", "premium", "premium / free")
	langFlag := fs.String("lang", "ja", "ja / en")
	n := fs.Int("n", 100, "選ぶ本数")
	seed := fs.Uint64("seed", 0, "乱数の種（0 なら時刻）")
	out := fs.String("out", "", "書き出す CSV のパス")
	write := fs.Bool("write", false, "選んだ文を確認待ちへ入れる（既定は表だけ書く）")
	fs.Parse(args)
	if *out == "" {
		return errors.New("-out が必要")
	}
	l, ok := lang.Parse(*langFlag)
	if !ok {
		return fmt.Errorf("lang %q", *langFlag)
	}
	name := sentence.PoolObjectFor(*tier, l)

	gcs, err := storage.NewClient(ctx)
	if err != nil {
		return err
	}
	defer gcs.Close()
	pool, err := sentence.ReadSentences(ctx, gcs.Bucket(project+"-uvm-data"), name)
	if err != nil {
		return err
	}

	db, err := firestore.NewClient(ctx, project)
	if err != nil {
		return err
	}
	defer db.Close()
	col := db.Collection(poolreview.Collection)
	docs, err := col.Documents(ctx).GetAll()
	if err != nil {
		return err
	}
	// 確認待ちに記録のある文（どの状態でも）と、確認で直した後の本文は選ばない。
	seen := make(map[string]bool, len(docs))
	for _, d := range docs {
		seen[d.Ref.ID] = true
		if fx, ok := d.Data()["sentence_fixed"].(map[string]any); ok {
			if t, _ := fx["thai_text"].(string); t != "" {
				seen[poolreview.ID(*tier, l, t)] = true
			}
		}
	}
	var cands []int
	for i, s := range pool {
		if !seen[poolreview.ID(*tier, l, s.ThaiText)] {
			cands = append(cands, i)
		}
	}
	s := *seed
	if s == 0 {
		s = uint64(time.Now().UnixNano())
	}
	r := rand.New(rand.NewPCG(s, s))
	r.Shuffle(len(cands), func(i, j int) { cands[i], cands[j] = cands[j], cands[i] })
	if len(cands) > *n {
		cands = cands[:*n]
	}
	ids := make([]string, len(cands))
	picked := make([]sentence.Sentence, len(cands))
	for k, i := range cands {
		picked[k] = pool[i]
		ids[k] = poolreview.ID(*tier, l, pool[i].ThaiText)
	}

	f, err := os.Create(*out)
	if err != nil {
		return err
	}
	if err := poolreview.WriteNativeSheet(f, ids, picked); err != nil {
		f.Close()
		return err
	}
	if err := f.Close(); err != nil {
		return err
	}
	log.Printf("%s: 未確認 %d 本から %d 本 → %s (seed=%d)", name, countUnseen(pool, seen, *tier, l), len(picked), *out, s)
	if !*write {
		log.Print("確認待ちへは入れていない（-write で入れる）")
		return nil
	}
	now := time.Now()
	for k, ps := range picked {
		m, err := sentenceMap(ps)
		if err != nil {
			return err
		}
		_, err = col.Doc(ids[k]).Create(ctx, map[string]any{
			"thai_text": ps.ThaiText,
			"sentence":  m,
			"tier":      *tier,
			"lang":      string(l),
			"source":    poolreview.NativeSource(name),
			"status":    poolreview.StatusNative,
			"queued_at": now,
		})
		if err != nil && status.Code(err) != codes.AlreadyExists {
			return fmt.Errorf("%s: %w", ids[k], err)
		}
	}
	log.Printf("確認待ちへ %d 本（status=%s）", len(picked), poolreview.StatusNative)
	return nil
}

func countUnseen(pool []sentence.Sentence, seen map[string]bool, tier string, l lang.Lang) int {
	n := 0
	for _, s := range pool {
		if !seen[poolreview.ID(tier, l, s.ThaiText)] {
			n++
		}
	}
	return n
}

func sentenceMap(s sentence.Sentence) (map[string]any, error) {
	b, err := json.Marshal(s)
	if err != nil {
		return nil, err
	}
	var m map[string]any
	return m, json.Unmarshal(b, &m)
}

// need は FIX の行で、直しがまだ無いもの（-needs の出力）。Claude がコメントから直しを作る。
type need struct {
	ID       string         `json:"id"`
	Sentence map[string]any `json:"sentence"`
	Comment  string         `json:"comment"`
}

// runNative は記入済みの表をプールへ反映する。既定は dry run。
func runNative(ctx context.Context, project string, args []string) error {
	fs := flag.NewFlagSet("native", flag.ExitOnError)
	in := fs.String("in", "", "記入済みの CSV")
	fixPath := fs.String("fix", "", `FIX の行の直し {id: {"japanese_translation":…} 等。タイ語を変えたら pronunciation・word_breakdown も}`)
	needsPath := fs.String("needs", "", "直しがまだ無い FIX の行を書き出す JSON のパス")
	write := fs.Bool("write", false, "書く（既定は dry run）")
	fs.Parse(args)

	f, err := os.Open(*in)
	if err != nil {
		return err
	}
	rows, err := poolreview.ReadNativeSheet(f)
	f.Close()
	if err != nil {
		return err
	}
	extras := map[string]map[string]any{}
	if *fixPath != "" {
		raw, err := os.ReadFile(*fixPath)
		if err != nil {
			return err
		}
		if err := json.Unmarshal(raw, &extras); err != nil {
			return err
		}
	}

	db, err := firestore.NewClient(ctx, project)
	if err != nil {
		return err
	}
	defer db.Close()
	col := db.Collection(poolreview.Collection)

	type mark struct {
		snap    *firestore.DocumentSnapshot
		status  string
		fixed   map[string]any
		comment string
	}
	var marks []mark
	var needs []need
	edits := map[string]*poolreview.PoolEdit{}
	edit := func(name string) *poolreview.PoolEdit {
		if edits[name] == nil {
			edits[name] = &poolreview.PoolEdit{
				Replace: map[string]sentence.Sentence{}, Remove: map[string]bool{},
			}
		}
		return edits[name]
	}
	counts := map[string]int{}
	for _, row := range rows {
		snap, err := col.Doc(row.ID).Get(ctx)
		if err != nil {
			return fmt.Errorf("%s: %w", row.ID, err)
		}
		var it item
		if err := snap.DataTo(&it); err != nil {
			return fmt.Errorf("%s: %w", row.ID, err)
		}
		if st, _ := snap.Data()["status"].(string); st != poolreview.StatusNative {
			log.Printf("skip %s: status=%s", row.ID, st)
			continue
		}
		l, ok := lang.Parse(it.Lang)
		if !ok {
			return fmt.Errorf("%s: lang %q", row.ID, it.Lang)
		}
		raw, _ := json.Marshal(it.Sentence)
		var orig sentence.Sentence
		if err := json.Unmarshal(raw, &orig); err != nil {
			return fmt.Errorf("%s: %w", row.ID, err)
		}
		name := sentence.PoolObjectFor(it.Tier, l)
		counts[row.Verdict]++
		switch row.Verdict {
		case poolreview.VerdictOK:
			marks = append(marks, mark{snap: snap, status: poolreview.StatusApproved, comment: row.Comment})
		case poolreview.VerdictNG:
			edit(name).Remove[orig.ThaiText] = true
			marks = append(marks, mark{snap: snap, status: poolreview.StatusRejected, comment: row.Comment})
		case poolreview.VerdictFix:
			extra := extras[row.ID]
			if extra == nil {
				needs = append(needs, need{ID: row.ID, Sentence: it.Sentence, Comment: row.Comment})
				continue
			}
			fixed, err := poolreview.FixedSentence(orig, extra)
			if err != nil {
				return fmt.Errorf("%s: %w", row.ID, err)
			}
			if _, err := sentence.NormalizePOS(&fixed, poolreview.PoolLabels(it.Tier, l)); err != nil {
				return fmt.Errorf("%s: %w", row.ID, err)
			}
			m, err := sentenceMap(fixed)
			if err != nil {
				return err
			}
			edit(name).Replace[orig.ThaiText] = fixed
			marks = append(marks, mark{snap: snap, status: poolreview.StatusApproved, fixed: m, comment: row.Comment})
		}
	}
	log.Printf("OK=%d FIX=%d NG=%d（うち直し待ち %d）",
		counts[poolreview.VerdictOK], counts[poolreview.VerdictFix], counts[poolreview.VerdictNG], len(needs))
	if len(needs) > 0 {
		if *needsPath != "" {
			b, _ := json.MarshalIndent(needs, "", " ")
			if err := os.WriteFile(*needsPath, b, 0o644); err != nil {
				return err
			}
			log.Printf("直しが要る %d 行 → %s", len(needs), *needsPath)
		}
		if *write {
			return fmt.Errorf("FIX の %d 行の直しが無い（-needs で書き出し、-fix で渡す）", len(needs))
		}
	}
	if !*write {
		log.Print("dry run（-write で書く）")
		return nil
	}

	gcs, err := storage.NewClient(ctx)
	if err != nil {
		return err
	}
	defer gcs.Close()
	bucket := gcs.Bucket(project + "-uvm-data")
	now := time.Now()
	// プールを先に直す。状態を書く前に落ちても、流し直せば同じ結果になる
	// （外した文・置き換えた元の文はもう無いので、二度目は何もしない）。
	for name, e := range edits {
		rep, rem, miss, err := poolreview.EditPool(ctx, bucket, name, *e, now)
		if err != nil {
			return fmt.Errorf("%s: %w", name, err)
		}
		log.Printf("pool %s replaced=%d removed=%d missing=%d", name, rep, rem, miss)
	}
	for _, m := range marks {
		ups := []firestore.Update{
			{Path: "status", Value: m.status},
			{Path: "reviewed_at", Value: now},
			{Path: "reviewer", Value: "native"},
		}
		if m.fixed != nil {
			ups = append(ups, firestore.Update{Path: "sentence_fixed", Value: m.fixed})
		}
		if m.comment != "" {
			ups = append(ups, firestore.Update{Path: "native_comment", Value: m.comment})
		}
		if _, err := m.snap.Ref.Update(ctx, ups, firestore.LastUpdateTime(m.snap.UpdateTime)); err != nil {
			return fmt.Errorf("%s: %w", m.snap.Ref.ID, err)
		}
	}
	log.Printf("確認済みにした %d 本", len(marks))
	return nil
}

// runSheet は記入を待っている文（status=native）の表を書き出し直す（表をなくした・列を変えたとき）。
func runSheet(ctx context.Context, project string, args []string) error {
	fs := flag.NewFlagSet("sheet", flag.ExitOnError)
	out := fs.String("out", "", "書き出す CSV のパス")
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
		Where("status", "==", poolreview.StatusNative).Documents(ctx).GetAll()
	if err != nil {
		return err
	}
	ids := make([]string, len(docs))
	ss := make([]sentence.Sentence, len(docs))
	for i, d := range docs {
		var it item
		if err := d.DataTo(&it); err != nil {
			return fmt.Errorf("%s: %w", d.Ref.ID, err)
		}
		raw, _ := json.Marshal(it.Sentence)
		if err := json.Unmarshal(raw, &ss[i]); err != nil {
			return fmt.Errorf("%s: %w", d.Ref.ID, err)
		}
		ids[i] = d.Ref.ID
	}
	f, err := os.Create(*out)
	if err != nil {
		return err
	}
	if err := poolreview.WriteNativeSheet(f, ids, ss); err != nil {
		f.Close()
		return err
	}
	log.Printf("記入待ち %d 本 → %s", len(ids), *out)
	return f.Close()
}
