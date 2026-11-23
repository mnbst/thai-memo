package poolreview

// プールに前からある文（確認待ちを通っていない文）を、ネイティブに表（Google スプレッドシートか CSV）で
// 確認してもらい、その結果でプールを直す。
//
//	sample: 未確認の文から候補を選び、Codex の判定（直し案）を付けて、Codex が直したほうがよいとした文を
//	        多めに（既定7割）、Codex が OK とした文を残りに載せた表を書く。載せた文は StatusNative、
//	        載せなかった文は StatusScreened で確認待ちへ入れる（次の回の候補）
//	native: 記入済みの表を読み、OK は残す・案でOK と FIX はその場で置き換える・NG はプールから外す
//
// ネイティブが書くのは判定・直したタイ語・コメントだけ。案でOK は Codex の直し（codex_fix）をそのまま使う。
// FIX は直したタイ語（かコメントの直し方）から、Claude が直した文（-fix の JSON）を作る。
// Codex が OK とした枠は、Codex の見逃しを測るため（native_slot に枠を残す）。
//
// 確認待ちへ入れるのは、同じ文を別の回に選ばないためと、表の id から元の文を引くため。
// StatusNative の文は pool-review（Codex）の一覧には出ない。

import (
	"context"
	"encoding/csv"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"strings"
	"time"

	"cloud.google.com/go/storage"

	"github.com/mnbst/thai-memo/functions/go/internal/sentence"
)

// StatusNative はネイティブ確認の表に載せて、記入を待っている文。
const StatusNative = "native"

// StatusScreened は Codex が先に判定したが、まだ表に載せていない文（次の回以降の候補）。
// codex_verdict・codex_reason・codex_fix を持つ。
const StatusScreened = "screened"

// NativeSource はネイティブ確認に出したプールの文の source（"pool/corpus_pool_ja.json"）。
func NativeSource(poolName string) string { return "pool/" + poolName }

// 表の列。ネイティブが書くのは判定・直したタイ語・コメントだけ。
const (
	colID = iota
	colKeyWord
	colThai
	colTrans
	colScene
	colProposal
	colVerdict
	colFixedThai
	colComment
	numCols
)

var nativeHeader = []string{
	"id",
	"学習語 คำศัพท์",
	"タイ語 ภาษาไทย",
	"訳 คำแปล",
	"場面 สถานการณ์",
	"直し案 ข้อเสนอแก้ไข",
	"判定 ผลตรวจ",
	"直したタイ語 ประโยคที่แก้",
	"コメント หมายเหตุ",
}

// 判定の値。VerdictProposal は直し案（Codex）のとおりに直す。
const (
	VerdictOK       = "OK"
	VerdictProposal = "案でOK"
	VerdictFix      = "FIX"
	VerdictNG       = "NG"
)

// Verdicts は判定のプルダウンの並び。
var Verdicts = []string{VerdictOK, VerdictProposal, VerdictFix, VerdictNG}

// NativeItem は表の1行に載せる文。Proposal は直し案の欄（ProposalText）。
type NativeItem struct {
	ID       string
	Sentence sentence.Sentence
	Proposal string
}

// NativeTable は確認してもらう文の表（見出し行つき）を作る。
func NativeTable(items []NativeItem) [][]string {
	t := [][]string{nativeHeader}
	for _, it := range items {
		row := make([]string, numCols)
		row[colID] = it.ID
		row[colKeyWord] = it.Sentence.KeyWord
		row[colThai] = it.Sentence.ThaiText
		row[colTrans] = it.Sentence.JapaneseTranslation
		row[colScene] = contextString(it.Sentence.Context, "usage_scenarios")
		row[colProposal] = it.Proposal
		t = append(t, row)
	}
	return t
}

// WriteNativeSheet は確認してもらう文の表を CSV で書く。
// Excel で文字化けしないよう、先頭に BOM を付ける。
func WriteNativeSheet(w io.Writer, items []NativeItem) error {
	if _, err := io.WriteString(w, "\ufeff"); err != nil {
		return err
	}
	cw := csv.NewWriter(w)
	if err := cw.WriteAll(NativeTable(items)); err != nil {
		return err
	}
	return cw.Error()
}

// ProposalText は Codex の判定を直し案の欄の文にする。表に出るのはタイ語と訳の変化だけ
// （単語分解だけの直しはネイティブに見せない。SurfaceChanged が false）。
func ProposalText(orig sentence.Sentence, verdict, reason string, fix map[string]any) string {
	switch verdict {
	case VerdictNG:
		return "NG 推奨: " + reason
	case VerdictFix:
		if !SurfaceChanged(orig, fix) {
			return ""
		}
		var b strings.Builder
		if t, ok := fix["thai_text"].(string); ok && t != orig.ThaiText {
			b.WriteString(t + "\n")
		}
		if tr, ok := fix["japanese_translation"].(string); ok && tr != orig.JapaneseTranslation {
			b.WriteString("訳: " + tr + "\n")
		}
		b.WriteString("理由: " + reason)
		return b.String()
	}
	return ""
}

// SurfaceChanged は直しがタイ語か訳を変えるか（単語分解・発音だけの直しは false）。
func SurfaceChanged(orig sentence.Sentence, fix map[string]any) bool {
	if t, ok := fix["thai_text"].(string); ok && sentence.StripSpaces(t) != sentence.StripSpaces(orig.ThaiText) {
		return true
	}
	if tr, ok := fix["japanese_translation"].(string); ok && tr != orig.JapaneseTranslation {
		return true
	}
	return false
}

func contextString(c map[string]any, key string) string {
	v, _ := c[key].(string)
	return v
}

// NativeRow は記入済みの表の1行（判定の付いた行だけ）。
type NativeRow struct {
	ID        string
	Verdict   string
	FixedThai string // FIX でネイティブが書いた直したタイ語（空ならコメントに直し方）
	Comment   string
}

// ReadNativeSheet は記入済みの表（CSV）を読む。行の扱いは ParseNativeTable。
func ReadNativeSheet(r io.Reader) ([]NativeRow, error) {
	cr := csv.NewReader(r)
	cr.FieldsPerRecord = -1
	recs, err := cr.ReadAll()
	if err != nil {
		return nil, err
	}
	return ParseNativeTable(recs)
}

// ParseNativeTable は記入済みの表（見出し行つき）を読む。列は見出しの先頭の語で探す
// （直し案の列が無い前の形の表も読める）。判定もコメントも空の行は飛ばす（次の回へ残す）。
// 判定が空でコメントだけある行はエラーにする（OK の補足か直し方か分からない）。
func ParseNativeTable(recs [][]string) ([]NativeRow, error) {
	if len(recs) == 0 {
		return nil, errors.New("表が空")
	}
	cols := map[string]int{"id": -1, "判定": -1, "直したタイ語": -1, "コメント": -1}
	for c, h := range recs[0] {
		h = strings.TrimSpace(strings.TrimPrefix(h, "\ufeff"))
		for k := range cols {
			if cols[k] < 0 && strings.HasPrefix(h, k) {
				cols[k] = c
			}
		}
	}
	for _, k := range []string{"id", "判定", "コメント"} {
		if cols[k] < 0 {
			return nil, fmt.Errorf("見出しに %q の列が無い", k)
		}
	}
	var out []NativeRow
	for i, rec := range recs[1:] {
		line := i + 2
		get := func(k string) string {
			c := cols[k]
			if c >= 0 && c < len(rec) {
				return strings.TrimSpace(rec[c])
			}
			return ""
		}
		row := NativeRow{
			ID:        get("id"),
			Verdict:   normalizeVerdict(get("判定")),
			FixedThai: get("直したタイ語"),
			Comment:   get("コメント"),
		}
		if row.ID == "" {
			continue
		}
		switch row.Verdict {
		case "":
			if row.Comment == "" && row.FixedThai == "" {
				continue
			}
			return nil, fmt.Errorf("%d行目: コメントか直したタイ語があるのに判定が空", line)
		case VerdictOK, VerdictNG, VerdictProposal:
		case VerdictFix:
			if row.Comment == "" && row.FixedThai == "" {
				return nil, fmt.Errorf("%d行目: FIX なのに直したタイ語もコメントも空", line)
			}
		default:
			return nil, fmt.Errorf("%d行目: 判定 %q は %s のどれでもない", line, row.Verdict, strings.Join(Verdicts, " / "))
		}
		out = append(out, row)
	}
	return out, nil
}

func normalizeVerdict(v string) string {
	if strings.EqualFold(v, VerdictProposal) {
		return VerdictProposal
	}
	return strings.ToUpper(v)
}

// FixedSentence は FIX の行の直した文を作る。fix は Claude がコメントから作った直し
// （sentence と同じ形の一部。書いたキーだけ差し替える）。
// タイ語を書き換えるなら、pronunciation と word_breakdown も作り直して入れる。
func FixedSentence(orig sentence.Sentence, fix map[string]any) (sentence.Sentence, error) {
	if len(fix) == 0 {
		return sentence.Sentence{}, errors.New("直し（-fix）が無い")
	}
	if t, ok := fix["thai_text"].(string); ok &&
		sentence.StripSpaces(t) != sentence.StripSpaces(orig.ThaiText) {
		if _, ok := fix["pronunciation"]; !ok {
			return sentence.Sentence{}, errors.New("タイ語を書き換えたのに pronunciation が無い")
		}
		if _, ok := fix["word_breakdown"]; !ok {
			return sentence.Sentence{}, errors.New("タイ語を書き換えたのに word_breakdown が無い")
		}
	}
	b, err := json.Marshal(orig)
	if err != nil {
		return sentence.Sentence{}, err
	}
	var m map[string]any
	if err := json.Unmarshal(b, &m); err != nil {
		return sentence.Sentence{}, err
	}
	return ApplyFix(m, fix)
}

// PoolEdit はプール1本への直し。Replace の元の本文 → 直した文、Remove の本文は外す。
type PoolEdit struct {
	Replace map[string]sentence.Sentence
	Remove  map[string]bool
}

// ApplyPoolEdit は既存のプールに直しを当てる。並びは変えない。
// 直した本文が別の文として既にあれば、元の文を外すだけにする（同じ文を2本持たない）。
// 見つからなかった本文の数も返す（先に外されていた等）。
func ApplyPoolEdit(pool []sentence.Sentence, e PoolEdit) (out []sentence.Sentence, replaced, removed, missing int) {
	exists := make(map[string]bool, len(pool))
	for _, s := range pool {
		exists[s.ThaiText] = true
	}
	found := map[string]bool{}
	out = make([]sentence.Sentence, 0, len(pool))
	for _, s := range pool {
		if e.Remove[s.ThaiText] {
			found[s.ThaiText] = true
			removed++
			continue
		}
		if fixed, ok := e.Replace[s.ThaiText]; ok {
			found[s.ThaiText] = true
			if fixed.ThaiText != s.ThaiText && exists[fixed.ThaiText] {
				removed++
				continue
			}
			out = append(out, fixed)
			replaced++
			continue
		}
		out = append(out, s)
	}
	for t := range e.Remove {
		if !found[t] {
			missing++
		}
	}
	for t := range e.Replace {
		if !found[t] {
			missing++
		}
	}
	return out, replaced, removed, missing
}

// EditPool は本番プール name に直しを当てて書き戻す。書く前に name.bak-<時刻>-native へ写しを取る。
// 読んだ版（generation）から変わっていないときだけ書く（AppendPool と同じ）。
func EditPool(
	ctx context.Context, bucket *storage.BucketHandle, name string, e PoolEdit, now time.Time,
) (replaced, removed, missing int, err error) {
	obj := bucket.Object(name)
	attrs, err := obj.Attrs(ctx)
	if err != nil {
		return 0, 0, 0, fmt.Errorf("%s を読めない: %w", name, err)
	}
	r, err := obj.Generation(attrs.Generation).NewReader(ctx)
	if err != nil {
		return 0, 0, 0, fmt.Errorf("%s を読めない: %w", name, err)
	}
	var pool []sentence.Sentence
	err = json.NewDecoder(r).Decode(&pool)
	r.Close()
	if err != nil {
		return 0, 0, 0, fmt.Errorf("%s の JSON 解析に失敗: %w", name, err)
	}
	out, replaced, removed, missing := ApplyPoolEdit(pool, e)
	if replaced == 0 && removed == 0 {
		return 0, 0, missing, nil
	}
	bak := bucket.Object(name + ".bak-" + now.Format("20060102-150405") + "-native")
	if _, err := bak.CopierFrom(obj.Generation(attrs.Generation)).Run(ctx); err != nil {
		return 0, 0, 0, fmt.Errorf("%s の写しを取れない: %w", name, err)
	}
	data, err := json.Marshal(out)
	if err != nil {
		return 0, 0, 0, err
	}
	w := obj.If(storage.Conditions{GenerationMatch: attrs.Generation}).NewWriter(ctx)
	w.ContentType = "application/json"
	if _, err := w.Write(data); err != nil {
		w.Close()
		return 0, 0, 0, err
	}
	return replaced, removed, missing, w.Close()
}
