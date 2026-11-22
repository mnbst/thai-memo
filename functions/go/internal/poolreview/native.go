package poolreview

// プールに前からある文（確認待ちを通っていない文）を、ネイティブに表（CSV）で
// 確認してもらい、その結果でプールを直す。
//
//	sample: 未確認の文から無作為に選び、確認待ちへ StatusNative で入れて、表を書き出す
//	native: 記入済みの表を読み、OK は残す・FIX はその場で置き換える・NG はプールから外す
//
// ネイティブが書くのは判定とコメントだけ。FIX の直し方はコメントに書いてもらい、
// Claude がそれを直した文（-fix の JSON）にする。
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

// NativeSource はネイティブ確認に出したプールの文の source（"pool/corpus_pool_ja.json"）。
func NativeSource(poolName string) string { return "pool/" + poolName }

// 表の列。ネイティブが書くのは判定とコメントだけ。
const (
	colID = iota
	colKeyWord
	colThai
	colTrans
	colScene
	colVerdict
	colComment
	numCols
)

var nativeHeader = []string{
	"id",
	"学習語 คำศัพท์",
	"タイ語 ภาษาไทย",
	"訳 คำแปล",
	"場面 สถานการณ์",
	"判定 ผลตรวจ (OK/NG/FIX)",
	"コメント・直し方 หมายเหตุ/วิธีแก้",
}

// 判定の値。
const (
	VerdictOK  = "OK"
	VerdictNG  = "NG"
	VerdictFix = "FIX"
)

// WriteNativeSheet は確認してもらう文の表を書く。ids と ss は同じ並び。
// Excel で文字化けしないよう、先頭に BOM を付ける。
func WriteNativeSheet(w io.Writer, ids []string, ss []sentence.Sentence) error {
	if _, err := io.WriteString(w, "\ufeff"); err != nil {
		return err
	}
	cw := csv.NewWriter(w)
	if err := cw.Write(nativeHeader); err != nil {
		return err
	}
	for i, s := range ss {
		row := make([]string, numCols)
		row[colID] = ids[i]
		row[colKeyWord] = s.KeyWord
		row[colThai] = s.ThaiText
		row[colTrans] = s.JapaneseTranslation
		row[colScene] = contextString(s.Context, "usage_scenarios")
		if err := cw.Write(row); err != nil {
			return err
		}
	}
	cw.Flush()
	return cw.Error()
}

func contextString(c map[string]any, key string) string {
	v, _ := c[key].(string)
	return v
}

// NativeRow は記入済みの表の1行（判定の付いた行だけ）。
type NativeRow struct {
	ID      string
	Verdict string
	Comment string
}

// ReadNativeSheet は記入済みの表を読む。判定もコメントも空の行は飛ばす（次の回へ残す）。
// 判定が空でコメントだけある行はエラーにする（OK の補足か直し方か分からない）。
func ReadNativeSheet(r io.Reader) ([]NativeRow, error) {
	cr := csv.NewReader(r)
	cr.FieldsPerRecord = -1
	recs, err := cr.ReadAll()
	if err != nil {
		return nil, err
	}
	if len(recs) == 0 {
		return nil, errors.New("表が空")
	}
	var out []NativeRow
	for i, rec := range recs[1:] {
		line := i + 2
		get := func(c int) string {
			if c < len(rec) {
				return strings.TrimSpace(rec[c])
			}
			return ""
		}
		row := NativeRow{
			ID:      strings.TrimPrefix(get(colID), "\ufeff"),
			Verdict: strings.ToUpper(get(colVerdict)),
			Comment: get(colComment),
		}
		if row.ID == "" {
			continue
		}
		switch row.Verdict {
		case "":
			if row.Comment == "" {
				continue
			}
			return nil, fmt.Errorf("%d行目: コメントがあるのに判定が空", line)
		case VerdictOK, VerdictNG:
		case VerdictFix:
			if row.Comment == "" {
				return nil, fmt.Errorf("%d行目: FIX なのに直し方（コメント）が空", line)
			}
		default:
			return nil, fmt.Errorf("%d行目: 判定 %q は OK / NG / FIX のどれでもない", line, row.Verdict)
		}
		out = append(out, row)
	}
	return out, nil
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
