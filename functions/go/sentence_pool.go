package function

import (
	"context"
	"encoding/json"
	"log"
	"sort"

	"cloud.google.com/go/storage"

	"github.com/mnbst/thai-memo/functions/go/internal/lang"
	"github.com/mnbst/thai-memo/functions/go/internal/sentence"
	"github.com/mnbst/thai-memo/functions/go/internal/uvm"
)

// 例文プール（dailyBatch のステップ6、品質監査と同じ周回）の設定。
//
// 静的コーパスは語×テーマで1本しか持たない。同じ key_word が再選出された人には
// 同じ文が出るので、その穴を運用中の生成で埋める。judge を通った例文だけを
// corpus_pool_<lang>.json へ貯め、CorpusBank が静的コーパスと同じ索引に重ねる。
//
// 貯める対象は premium 仕様で LLM 生成されたものだけ。free の文は語彙帯が
// 別（FreeBank）で、バンク由来（from_cache=true）の文は既にコーパスにある。
const (
	// poolMaxEntries は1言語あたりの保持上限。超えたぶんは古い側から落とす。
	// 1本 1〜2KB なので、2万本でも数十MB。CorpusBank はこれを
	// 静的コーパス（15,864本）と一緒にインスタンスへ載せる。
	poolMaxEntries = 20000
)

// poolEntry はプールへ入れる例文1件と、その振り分け先。
type poolEntry struct {
	Lang     lang.Lang
	Sentence sentence.Sentence
}

// buildPoolEntry は保存済みの例文 doc をプールの1件へ変換する。
//
// 落とすもの:
//   - lang が無い（このフィールドを付ける前に保存された doc。訳文の言語が
//     決められないので、取り違えるくらいなら入れない）
//   - key_word が無い / key_word から外した語（uvm.IsExcludedTargetWord）
//   - 本文・訳文・word_breakdown のどれかが欠けている
func buildPoolEntry(data map[string]any) (poolEntry, bool) {
	l, ok := lang.Parse(stringField(data["lang"]))
	if !ok {
		return poolEntry{}, false
	}
	keyWord := stringField(data["key_word"])
	if keyWord == "" || uvm.IsExcludedTargetWord(keyWord) {
		return poolEntry{}, false
	}
	s, err := sentence.FromMap(data)
	if err != nil {
		return poolEntry{}, false
	}
	if s.ThaiText == "" || s.JapaneseTranslation == "" || len(s.WordBreakdown) == 0 {
		return poolEntry{}, false
	}
	// key_word は LLM 生成では空のまま保存されない（doc 側だけが持つ）ので、
	// バンクの項目と同じ形になるようここで載せ替える。
	s.KeyWord = keyWord
	// 出どころのティアはプールでは持たない。Pick した側が付け直す。
	s.GenerationTier = ""
	return poolEntry{Lang: l, Sentence: *s}, true
}

// writeSentencePool は受理された例文を言語ごとのプールへ追記する。
//
// 既存のプールを読んで、thai_text が重複しないものだけを末尾へ足して書き戻す。
// 書き手は dailyBatch だけ（1日1回・1インスタンス）なので、読んで書くだけで
// 競合しない。CorpusBank 側は起動時に読むので、反映は翌日になる。
func writeSentencePool(
	ctx context.Context, projectID string, entries []poolEntry, maxEntries int,
) error {
	if len(entries) == 0 {
		return nil
	}
	byLang := map[lang.Lang][]sentence.Sentence{}
	for _, e := range entries {
		byLang[e.Lang] = append(byLang[e.Lang], e.Sentence)
	}

	client, err := storage.NewClient(ctx)
	if err != nil {
		return err
	}
	defer client.Close()
	bucket := client.Bucket(projectID + "-uvm-data")

	langs := make([]lang.Lang, 0, len(byLang))
	for l := range byLang {
		langs = append(langs, l)
	}
	sort.Slice(langs, func(i, j int) bool { return langs[i] < langs[j] })

	for _, l := range langs {
		name := sentence.PoolObject(l)
		existing, err := sentence.ReadSentences(ctx, bucket, name)
		if err != nil {
			return err
		}
		merged, added := mergePool(existing, byLang[l], maxEntries)
		if added == 0 {
			log.Printf("sentencePool: lang=%s no new sentences (pool=%d)", l, len(merged))
			continue
		}
		data, err := json.Marshal(merged)
		if err != nil {
			return err
		}
		w := bucket.Object(name).NewWriter(ctx)
		w.ContentType = "application/json"
		if _, err := w.Write(data); err != nil {
			w.Close()
			return err
		}
		if err := w.Close(); err != nil {
			return err
		}
		log.Printf("sentencePool: lang=%s added=%d pool=%d", l, added, len(merged))
	}
	return nil
}

// mergePool は既存プールへ新しい例文を足す。
//
// thai_text が既にあるものは飛ばす（同じ文を2本持っても抽選が偏るだけ）。
// 上限を超えたら古い側（先頭）から落とす。古い文ほど、そのとき直した
// プロンプトより前の出来なので、落とす向きはこちらでよい。
func mergePool(existing, incoming []sentence.Sentence, maxEntries int) ([]sentence.Sentence, int) {
	seen := make(map[string]bool, len(existing))
	for _, s := range existing {
		seen[s.ThaiText] = true
	}
	merged := existing
	added := 0
	for _, s := range incoming {
		if seen[s.ThaiText] {
			continue
		}
		seen[s.ThaiText] = true
		merged = append(merged, s)
		added++
	}
	if len(merged) > maxEntries {
		merged = merged[len(merged)-maxEntries:]
	}
	return merged, added
}
