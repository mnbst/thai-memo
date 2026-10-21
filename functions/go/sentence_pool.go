package function

import (
	"github.com/mnbst/thai-memo/functions/go/internal/lang"
	"github.com/mnbst/thai-memo/functions/go/internal/sentence"
	"github.com/mnbst/thai-memo/functions/go/internal/uvm"
)

// 例文プール（dailyBatch のステップ6で確認待ちへ入れ、OK の文だけを
// cmd/poolreview が足す。internal/poolreview）の1件の組み立て。
//
// 静的コーパス・free バンクは語×テーマで1本しか持たない。同じ key_word が
// 再選出された人には同じ文が出るので、その穴を運用中の生成で埋める。judge を
// 通り、人が OK した例文だけをティアごとのプールへ貯める。
//
//	premium  corpus_pool_<lang>.json  CorpusBank が静的コーパスと同じ索引に重ねる
//	free     free_pool_<lang>.json    FreeBank が free バンクに重ねる
//
// ティアで分けるのは、free と premium で語彙帯とプロンプトが違うため。
// 混ぜると free に語彙帯の外の文が出る。ファイルが別なので洗い直し
// （cmd/poolrecheck -tier）もティアごとにできる。
// バンク由来（from_cache=true）の文は既にバンクにあるので貯めない。

// poolEntry はプールへ入れる例文1件と、その振り分け先。
type poolEntry struct {
	// Tier は generation_tier の値（premium / free）。書き出すプールを決める。
	Tier     string
	Lang     lang.Lang
	Sentence sentence.Sentence
}

// buildPoolEntry は保存済みの例文 doc をプールの1件へ変換する。
//
// 落とすもの:
//   - generation_tier が premium / free のどちらでもない
//   - lang が無い（このフィールドを付ける前に保存された doc。訳文の言語が
//     決められないので、取り違えるくらいなら入れない）
//   - key_word が無い / key_word から外した語（uvm.IsExcludedTargetWord）
//   - 本文・訳文・word_breakdown のどれかが欠けている
func buildPoolEntry(data map[string]any) (poolEntry, bool) {
	tier, ok := poolTier(data)
	if !ok {
		return poolEntry{}, false
	}
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
	return poolEntry{Tier: tier, Lang: l, Sentence: *s}, true
}

// poolTier は doc の generation_tier を返す。プールを持つティアでなければ false。
func poolTier(data map[string]any) (string, bool) {
	switch tier := stringField(data["generation_tier"]); tier {
	case sentence.GenerationTier(true), sentence.GenerationTier(false):
		return tier, true
	}
	return "", false
}
