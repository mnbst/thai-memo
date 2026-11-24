package main

// ネイティブ確認（プールに前からある文を表で見てもらう）。流れは internal/poolreview/native.go。
// 表はスプレッドシート（-sheet <ID>、回ごとにタブ）か CSV（-out / -in）で受け渡す。
//
//	GCLOUD_PROJECT=thai-memo-prod go run ./cmd/poolreview sample -cands 300 -out $S/cands.json
//	（Codex が cands.json を判定 → $S/judged.json）
//	GCLOUD_PROJECT=thai-memo-prod go run ./cmd/poolreview sample -in $S/cands.json -judged $S/judged.json -n 100 -sheet <ID> -write
//	GCLOUD_PROJECT=thai-memo-prod go run ./cmd/poolreview native -sheet <ID> -tab native_<日付> -needs $S/needs.json
//	GCLOUD_PROJECT=thai-memo-prod go run ./cmd/poolreview native -sheet <ID> -tab native_<日付> -fix $S/fix.json -write

import (
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"log"
	"math/rand/v2"
	"os"
	"sort"
	"time"

	"cloud.google.com/go/firestore"
	"cloud.google.com/go/storage"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"

	"github.com/mnbst/thai-memo/functions/go/internal/lang"
	"github.com/mnbst/thai-memo/functions/go/internal/poolreview"
	"github.com/mnbst/thai-memo/functions/go/internal/sentence"
)

// candFile は sample -cands の出力（Codex に判定させる候補）。
type candFile struct {
	Tier  string `json:"tier"`
	Lang  string `json:"lang"`
	Items []struct {
		ID       string            `json:"id"`
		Sentence sentence.Sentence `json:"sentence"`
	} `json:"items"`
}

// runSample は表を作る。2段:
//
//	-cands N -out cands.json: 未確認の文から無作為に N 本を候補として書き出す（Firestore には書かない）
//	-in cands.json -judged judged.json: Codex の判定を付け、前の回に載せなかった候補（screened）と合わせて表を書く。
//	  -write で載せた文を StatusNative、載せなかった今回の候補を StatusScreened で確認待ちへ入れる
func runSample(ctx context.Context, project string, args []string) error {
	fs := flag.NewFlagSet("sample", flag.ExitOnError)
	tier := fs.String("tier", "premium", "premium / free（-cands のとき）")
	langFlag := fs.String("lang", "ja", "ja / en（-cands のとき）")
	cands := fs.Int("cands", 0, "候補の本数（候補を書き出す段）")
	in := fs.String("in", "", "候補の JSON（-cands の出力）")
	judgedPath := fs.String("judged", "", `Codex の判定 {"results":[{id,verdict,reason,fix}]}`)
	n := fs.Int("n", 100, "表に載せる本数")
	share := fs.Float64("share", 0.7, "Codex が直したほうがよいとした文の割合（残りは Codex が OK とした文）")
	seed := fs.Uint64("seed", 0, "乱数の種（0 なら時刻）")
	out := fs.String("out", "", "書き出す JSON（-cands）か CSV のパス")
	sheetID := fs.String("sheet", "", "表を書き込むスプレッドシートの ID（CSV の -out の代わり）")
	tab := fs.String("tab", "native_"+time.Now().Format("20060102"), "-sheet に足すタブ名")
	write := fs.Bool("write", false, "確認待ちへ入れる（既定は表だけ書く）")
	fs.Parse(args)

	s := *seed
	if s == 0 {
		s = uint64(time.Now().UnixNano())
	}
	r := rand.New(rand.NewPCG(s, s))
	db, err := firestore.NewClient(ctx, project)
	if err != nil {
		return err
	}
	defer db.Close()
	col := db.Collection(poolreview.Collection)

	if *cands > 0 {
		if *out == "" {
			return errors.New("-cands には -out が必要")
		}
		return writeCands(ctx, project, col, *tier, *langFlag, *cands, *out, r, s)
	}
	if *in == "" || *judgedPath == "" {
		return errors.New("-cands N -out か、-in と -judged が必要")
	}
	if (*out == "") == (*sheetID == "") {
		return errors.New("-out か -sheet のどちらか1つが必要")
	}

	var cf candFile
	raw, err := os.ReadFile(*in)
	if err != nil {
		return err
	}
	if err := json.Unmarshal(raw, &cf); err != nil {
		return err
	}
	l, ok := lang.Parse(cf.Lang)
	if !ok {
		return fmt.Errorf("lang %q", cf.Lang)
	}
	name := sentence.PoolObjectFor(cf.Tier, l)
	judged, err := poolreview.ReadJudged(*judgedPath)
	if err != nil {
		return err
	}

	// 表の候補: 前の回に載せなかった文（古い順）→ 今回の候補。
	type entry struct {
		s      sentence.Sentence
		j      poolreview.Judged
		screen *firestore.DocumentSnapshot // 前の回からの候補なら doc
	}
	entries := map[string]*entry{}
	var order []string
	screened, err := col.Where("status", "==", poolreview.StatusScreened).Documents(ctx).GetAll()
	if err != nil {
		return err
	}
	sort.Slice(screened, func(i, j int) bool { return screened[i].CreateTime.Before(screened[j].CreateTime) })
	for _, d := range screened {
		var it item
		if err := d.DataTo(&it); err != nil {
			return fmt.Errorf("%s: %w", d.Ref.ID, err)
		}
		if it.Tier != cf.Tier || it.Lang != cf.Lang {
			continue
		}
		var ss sentence.Sentence
		b, _ := json.Marshal(it.Sentence)
		if err := json.Unmarshal(b, &ss); err != nil {
			return fmt.Errorf("%s: %w", d.Ref.ID, err)
		}
		j := codexOf(d)
		j.ID = d.Ref.ID
		entries[d.Ref.ID] = &entry{s: ss, j: j, screen: d}
		order = append(order, d.Ref.ID)
	}
	missing := 0
	for _, c := range cf.Items {
		j, ok := judged[c.ID]
		if !ok {
			missing++
			continue
		}
		if entries[c.ID] != nil {
			continue
		}
		entries[c.ID] = &entry{s: c.Sentence, j: j}
		order = append(order, c.ID)
	}
	if missing > 0 {
		log.Printf("判定の無い候補 %d 本は飛ばす（次の回の候補に戻る）", missing)
	}

	var flagged, okIDs []string
	for _, id := range order {
		e := entries[id]
		if isFlagged(e.s, e.j) {
			flagged = append(flagged, id)
		} else {
			okIDs = append(okIDs, id)
		}
	}
	picked, slot := poolreview.PickNative(flagged, okIDs, *n, *share, r)
	items := make([]poolreview.NativeItem, len(picked))
	for k, id := range picked {
		e := entries[id]
		items[k] = poolreview.NativeItem{ID: id, Sentence: e.s,
			Proposal: poolreview.ProposalText(e.s, e.j.Verdict, e.j.Reason, e.j.Fix)}
	}
	dest, err := writeTable(ctx, *out, *sheetID, *tab, items)
	if err != nil {
		return err
	}
	nf := 0
	for _, v := range slot {
		if v == poolreview.SlotFlagged {
			nf++
		}
	}
	log.Printf("%s: 候補 %d 本（Codex の指摘 %d・OK %d）から %d 本（指摘 %d・OK %d）→ %s (seed=%d)",
		name, len(order), len(flagged), len(okIDs), len(picked), nf, len(picked)-nf, dest, s)
	if !*write {
		log.Print("確認待ちへは入れていない（-write で入れる）")
		return nil
	}

	now := time.Now()
	nNative, nScreened := 0, 0
	for _, id := range order {
		e := entries[id]
		st := poolreview.StatusScreened
		if slot[id] != "" {
			st = poolreview.StatusNative
		}
		if e.screen != nil {
			if st == poolreview.StatusScreened {
				continue // 前の回からの候補のまま
			}
			if _, err := e.screen.Ref.Update(ctx, []firestore.Update{
				{Path: "status", Value: st}, {Path: "native_slot", Value: slot[id]}, {Path: "queued_at", Value: now},
			}, firestore.LastUpdateTime(e.screen.UpdateTime)); err != nil {
				return fmt.Errorf("%s: %w", id, err)
			}
			nNative++
			continue
		}
		m, err := sentenceMap(e.s)
		if err != nil {
			return err
		}
		doc := map[string]any{
			"thai_text":     e.s.ThaiText,
			"sentence":      m,
			"tier":          cf.Tier,
			"lang":          cf.Lang,
			"source":        poolreview.NativeSource(name),
			"status":        st,
			"queued_at":     now,
			"codex_verdict": e.j.Verdict,
			"codex_reason":  e.j.Reason,
		}
		if len(e.j.Fix) > 0 {
			doc["codex_fix"] = e.j.Fix
		}
		if slot[id] != "" {
			doc["native_slot"] = slot[id]
		}
		if _, err := col.Doc(id).Create(ctx, doc); err != nil {
			if status.Code(err) == codes.AlreadyExists {
				continue
			}
			return fmt.Errorf("%s: %w", id, err)
		}
		if st == poolreview.StatusNative {
			nNative++
		} else {
			nScreened++
		}
	}
	log.Printf("確認待ちへ 表 %d 本（status=%s）・次の回の候補 %d 本（status=%s）",
		nNative, poolreview.StatusNative, nScreened, poolreview.StatusScreened)
	return nil
}

// writeCands は未確認の文から無作為に n 本を候補として書き出す。
func writeCands(ctx context.Context, project string, col *firestore.CollectionRef, tier, langFlag string, n int, out string, r *rand.Rand, seed uint64) error {
	l, ok := lang.Parse(langFlag)
	if !ok {
		return fmt.Errorf("lang %q", langFlag)
	}
	name := sentence.PoolObjectFor(tier, l)
	gcs, err := storage.NewClient(ctx)
	if err != nil {
		return err
	}
	defer gcs.Close()
	pool, err := sentence.ReadSentences(ctx, gcs.Bucket(project+"-uvm-data"), name)
	if err != nil {
		return err
	}
	docs, err := col.Documents(ctx).GetAll()
	if err != nil {
		return err
	}
	// 確認待ちに記録のある文（どの状態でも。screened も）と、確認で直した後の本文は選ばない。
	seen := make(map[string]bool, len(docs))
	for _, d := range docs {
		seen[d.Ref.ID] = true
		if fx, ok := d.Data()["sentence_fixed"].(map[string]any); ok {
			if t, _ := fx["thai_text"].(string); t != "" {
				seen[poolreview.ID(tier, l, t)] = true
			}
		}
	}
	var idx []int
	for i, s := range pool {
		if !seen[poolreview.ID(tier, l, s.ThaiText)] {
			idx = append(idx, i)
		}
	}
	unseen := len(idx)
	r.Shuffle(len(idx), func(i, j int) { idx[i], idx[j] = idx[j], idx[i] })
	if len(idx) > n {
		idx = idx[:n]
	}
	cf := candFile{Tier: tier, Lang: string(l)}
	for _, i := range idx {
		cf.Items = append(cf.Items, struct {
			ID       string            `json:"id"`
			Sentence sentence.Sentence `json:"sentence"`
		}{poolreview.ID(tier, l, pool[i].ThaiText), pool[i]})
	}
	b, err := json.MarshalIndent(cf, "", " ")
	if err != nil {
		return err
	}
	if err := os.WriteFile(out, b, 0o644); err != nil {
		return err
	}
	log.Printf("%s: 未確認 %d 本から候補 %d 本 → %s (seed=%d)", name, unseen, len(cf.Items), out, seed)
	return nil
}

// isFlagged は Codex が直したほうがよいとした文か（NG か、タイ語・訳を変える FIX）。
func isFlagged(s sentence.Sentence, j poolreview.Judged) bool {
	switch j.Verdict {
	case poolreview.VerdictNG:
		return true
	case poolreview.VerdictFix:
		return poolreview.SurfaceChanged(s, j.Fix)
	}
	return false
}

// codexOf は確認待ちの doc に残した Codex の判定を読む。
func codexOf(d *firestore.DocumentSnapshot) poolreview.Judged {
	m := d.Data()
	j := poolreview.Judged{}
	j.Verdict, _ = m["codex_verdict"].(string)
	j.Reason, _ = m["codex_reason"].(string)
	j.Fix, _ = m["codex_fix"].(map[string]any)
	return j
}

func sentenceMap(s sentence.Sentence) (map[string]any, error) {
	b, err := json.Marshal(s)
	if err != nil {
		return nil, err
	}
	var m map[string]any
	return m, json.Unmarshal(b, &m)
}

// need は FIX の行で、直しがまだ無いもの（-needs の出力）。Claude が直したタイ語かコメントから直しを作る。
type need struct {
	ID        string         `json:"id"`
	Sentence  map[string]any `json:"sentence"`
	FixedThai string         `json:"fixed_thai,omitempty"`
	Comment   string         `json:"comment"`
}

// runNative は記入済みの表をプールへ反映する。既定は dry run。
func runNative(ctx context.Context, project string, args []string) error {
	fs := flag.NewFlagSet("native", flag.ExitOnError)
	in := fs.String("in", "", "記入済みの CSV")
	sheetID := fs.String("sheet", "", "記入済みのスプレッドシートの ID（-in の代わり）")
	tab := fs.String("tab", "", "-sheet で読むタブ名")
	fixPath := fs.String("fix", "", `FIX の行の直し {id: {"japanese_translation":…} 等。タイ語を変えたら pronunciation・word_breakdown も}`)
	needsPath := fs.String("needs", "", "直しがまだ無い FIX の行を書き出す JSON のパス")
	write := fs.Bool("write", false, "書く（既定は dry run）")
	fs.Parse(args)

	rows, err := readTable(ctx, *in, *sheetID, *tab)
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
		verdict string
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
	bySlot := map[string]map[string]int{} // 枠 → ネイティブの判定 → 本数（Codex との一致を見る）
	autoFixed := 0
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
		cx := codexOf(snap)
		counts[row.Verdict]++
		slotName, _ := snap.Data()["native_slot"].(string)
		if slotName == "" {
			slotName = "（無作為）"
		}
		if bySlot[slotName] == nil {
			bySlot[slotName] = map[string]int{}
		}
		bySlot[slotName][row.Verdict]++

		// replace は直した文でプールを置き換え、確認済みにする。
		replace := func(fix map[string]any) error {
			fixed, err := poolreview.FixedSentence(orig, fix)
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
			marks = append(marks, mark{snap: snap, status: poolreview.StatusApproved, verdict: row.Verdict, fixed: m, comment: row.Comment})
			return nil
		}
		reject := func() {
			edit(name).Remove[orig.ThaiText] = true
			marks = append(marks, mark{snap: snap, status: poolreview.StatusRejected, verdict: row.Verdict, comment: row.Comment})
		}

		switch row.Verdict {
		case poolreview.VerdictOK:
			// ネイティブに見せていない単語分解だけの直しは、Codex の直しを当てる。
			if cx.Verdict == poolreview.VerdictFix && len(cx.Fix) > 0 && !poolreview.SurfaceChanged(orig, cx.Fix) {
				if err := replace(cx.Fix); err != nil {
					return err
				}
				autoFixed++
				continue
			}
			marks = append(marks, mark{snap: snap, status: poolreview.StatusApproved, verdict: row.Verdict, comment: row.Comment})
		case poolreview.VerdictNG:
			reject()
		case poolreview.VerdictProposal:
			switch {
			case cx.Verdict == poolreview.VerdictNG:
				reject()
			case cx.Verdict == poolreview.VerdictFix && poolreview.SurfaceChanged(orig, cx.Fix):
				if err := replace(cx.Fix); err != nil {
					return err
				}
			default:
				return fmt.Errorf("%s: 案でOK なのに直し案が無い（Codex: %q）", row.ID, cx.Verdict)
			}
		case poolreview.VerdictFix:
			extra := extras[row.ID]
			if extra == nil {
				needs = append(needs, need{ID: row.ID, Sentence: it.Sentence, FixedThai: row.FixedThai, Comment: row.Comment})
				continue
			}
			if err := replace(extra); err != nil {
				return err
			}
		}
	}
	log.Printf("OK=%d 案でOK=%d FIX=%d NG=%d（うち直し待ち %d・OK で分解だけ直す %d）",
		counts[poolreview.VerdictOK], counts[poolreview.VerdictProposal], counts[poolreview.VerdictFix],
		counts[poolreview.VerdictNG], len(needs), autoFixed)
	for _, s := range []string{poolreview.SlotFlagged, poolreview.SlotOK, "（無作為）"} {
		if c := bySlot[s]; c != nil {
			log.Printf("  枠 %s: OK=%d 案でOK=%d FIX=%d NG=%d", s,
				c[poolreview.VerdictOK], c[poolreview.VerdictProposal], c[poolreview.VerdictFix], c[poolreview.VerdictNG])
		}
	}
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
			{Path: "native_verdict", Value: m.verdict},
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
	sheetID := fs.String("sheet", "", "書き込むスプレッドシートの ID（-out の代わり）")
	tab := fs.String("tab", "native_"+time.Now().Format("20060102_1504"), "-sheet に足すタブ名")
	fs.Parse(args)
	if (*out == "") == (*sheetID == "") {
		return errors.New("-out か -sheet のどちらか1つが必要")
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
	items := make([]poolreview.NativeItem, len(docs))
	for i, d := range docs {
		var it item
		if err := d.DataTo(&it); err != nil {
			return fmt.Errorf("%s: %w", d.Ref.ID, err)
		}
		var ss sentence.Sentence
		raw, _ := json.Marshal(it.Sentence)
		if err := json.Unmarshal(raw, &ss); err != nil {
			return fmt.Errorf("%s: %w", d.Ref.ID, err)
		}
		cx := codexOf(d)
		items[i] = poolreview.NativeItem{ID: d.Ref.ID, Sentence: ss,
			Proposal: poolreview.ProposalText(ss, cx.Verdict, cx.Reason, cx.Fix)}
	}
	dest, err := writeTable(ctx, *out, *sheetID, *tab, items)
	if err != nil {
		return err
	}
	log.Printf("記入待ち %d 本 → %s", len(items), dest)
	return nil
}

// writeTable は表を CSV（out）かスプレッドシートの新しいタブ（sheetID・tab）へ書き、書いた先を返す。
func writeTable(ctx context.Context, out, sheetID, tab string, items []poolreview.NativeItem) (string, error) {
	if sheetID != "" {
		g, err := poolreview.NewGSheet(ctx, sheetID)
		if err != nil {
			return "", err
		}
		if err := g.AddTab(ctx, tab, poolreview.NativeTable(items)); err != nil {
			return "", err
		}
		return fmt.Sprintf("%s（タブ %s）", g.URL(), tab), nil
	}
	f, err := os.Create(out)
	if err != nil {
		return "", err
	}
	if err := poolreview.WriteNativeSheet(f, items); err != nil {
		f.Close()
		return "", err
	}
	return out, f.Close()
}

// readTable は記入済みの表を CSV（in）かスプレッドシートのタブ（sheetID・tab）から読む。
func readTable(ctx context.Context, in, sheetID, tab string) ([]poolreview.NativeRow, error) {
	if sheetID != "" {
		if tab == "" {
			return nil, errors.New("-sheet には -tab が必要")
		}
		g, err := poolreview.NewGSheet(ctx, sheetID)
		if err != nil {
			return nil, err
		}
		t, err := g.ReadTab(ctx, tab)
		if err != nil {
			return nil, err
		}
		return poolreview.ParseNativeTable(t)
	}
	if in == "" {
		return nil, errors.New("-in か -sheet が必要")
	}
	f, err := os.Open(in)
	if err != nil {
		return nil, err
	}
	defer f.Close()
	return poolreview.ReadNativeSheet(f)
}
