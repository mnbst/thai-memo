package uvm

import (
	"context"
	"math"
	"strings"

	"cloud.google.com/go/firestore"
)

// AlphaExposure は例文露出時の P 微増率（uvm.py:ALPHA_EXPOSURE）。
// 旧則 ExposureP 専用で、本番の露出には使わない。
const AlphaExposure = 0.10

// KeyWordExposureStep は登録済みの語を key_word として出すたびに P へ足す幅。
//
// 既出例文の出し直し（ReusableWords）は P の小さい順に語を選ぶ。出した語を
// 上げておくと、スコアが動かず帯が止まっていても同じ語が続かない。
// 0.0005 では P の段（誤答 0.15・未回答 0.4・正解 0.5〜）をまたぐのに
// 200〜500 回かかり、いちばん下の段の数語だけが出続けた。0.01 なら
// 0.15→0.4 が 25 回、0.4→0.5 が 10 回。
//
// 語彙スコアは 0.0005 と変わらない（TestAdaptiveBand、基準 0.42 固定）。
// 分かっている副作用:
//   - 未回答の語（0.4）は 1 回で最小の基準 0.41（SummaryCutoff）に届く。
//     窓の 21 語すべてが出し直されればクイズなしでスコアが進む
//   - 未回答のまま 10 回ほどで LearnedP(0.5) を超える
//   - 誤答した語（0.15）は 15 回で weakPThreshold(0.3) に届き、正解しない
//     ままでまとめクイズの苦手枠から外れる
//
// key_word 以外の語には足さない（基本語は毎文のように出るので、旧則と
// 同じくクイズを解かずにスコアが上がる）。
const KeyWordExposureStep = 0.01

// SentenceWords は例文の word_breakdown から全単語を重複なしで返す
// （uvm.py:get_sentence_words:493）。
//
// Python は dict でない要素を飛ばし、word を str() して strip する。
// Go 側の word は文字列型なので変換は要らない。
func SentenceWords(words []string) []string {
	seen := map[string]bool{}
	var out []string
	for _, w := range words {
		w = strings.TrimSpace(w)
		if w != "" && !seen[w] {
			seen[w] = true
			out = append(out, w)
		}
	}
	return out
}

// ExposedWords は例文内に実際に出現したターゲット語を語ごとに1回だけ返す
// （uvm.py:get_exposed_words:507）。
func ExposedWords(sentenceWords, targetWords []string) []string {
	if len(targetWords) == 0 {
		return nil
	}
	targets := map[string]bool{}
	for _, t := range targetWords {
		targets[t] = true
	}
	var out []string
	for _, w := range SentenceWords(sentenceWords) {
		if targets[w] {
			out = append(out, w)
		}
	}
	return out
}

// ExposureP は同じ語が count 回出たときの P の更新後の値。
//
// 露出で P を動かすのをやめたため、現在 RegisterExposure からは呼ばれない。
// Python 版との一致を確認する golden テストのために残している。
// 1 回ごとに p += ALPHA_EXPOSURE * (1 - p) を適用し、最後にクリップする。
func ExposureP(oldP float64, count int) float64 {
	p := oldP
	for range count {
		p = p + AlphaExposure*(1-p)
	}
	return math.Max(PMin, math.Min(PMax, p))
}

// RegisterExposure は例文に出た語の露出を記録する（uvm.py:register_exposure:519）。
//
// targetWords に含まれる語（key_word）だけを扱う。それ以外の語は何も書かない。
//
//   - 登録済み語: last_seen を更新し、P を KeyWordExposureStep 足す
//   - 未登録語: P=NewWordP（=prior）で新規作成
//
// last_seen は語彙一覧の差分取得（getVocabProgress）と、旧アプリの語選び
// （selectUnknown）が使う。
//
// words は重複を含んでよい（1 語 1 回として扱う）。
func RegisterExposure(
	ctx context.Context, db *firestore.Client, uid string,
	words []string, targetWords []string,
) error {
	now := nowSeconds()
	uvmRef := db.Collection("users").Doc(uid).Collection("uvm")
	targets := map[string]bool{}
	for _, t := range targetWords {
		targets[t] = true
	}

	// Counter(words) は初出順。Go の map は順序が不定なので出現順を保つ。
	counts := map[string]int{}
	var order []string
	for _, w := range words {
		if _, ok := counts[w]; !ok {
			order = append(order, w)
		}
		counts[w]++
	}

	refs := make([]*firestore.DocumentRef, len(order))
	for i, word := range order {
		refs[i] = uvmRef.Doc(word)
	}
	snaps, err := db.GetAll(ctx, refs)
	if err != nil {
		return err
	}

	batch := db.BulkWriter(ctx)
	for i, word := range order {
		docRef := refs[i]
		if !targets[word] {
			continue
		}
		if snaps[i].Exists() {
			// 例文に出たことは「見た」証拠であって「知っている」証拠ではない。
			// 旧則（ExposureP）は同じ語が 6 回出るだけで P>0.5 になり、クイズを
			// 1 問も解かずに語彙スコアを押し上げていた。足すのは並び順のぶんだけ。
			updates := []firestore.Update{{Path: "last_seen", Value: now}}
			// P=0 の doc は未出の扱い（reusableOrder）なので動かさない。
			if p := numField(snaps[i].Data()["p"]); p > 0 {
				updates = append(updates, firestore.Update{Path: "p", Value: KeyWordExposureP(p)})
			}
			if _, err := batch.Update(docRef, updates); err != nil {
				return err
			}
		} else {
			// key_word として選出された未登録語は新規作成
			if _, err := batch.Set(docRef, map[string]any{
				"word":          word,
				"p":             NewWordP,
				"quiz_attempts": 0,
				"last_seen":     now,
				"last_result":   nil,
				// 露出は「見た」証拠であって採点ではない。クイズに答えて
				// evidence が付くまで境界推定の母数に入れない。
				"evidence": 0.0,
				"graded":   false,
			}); err != nil {
				return err
			}
		}
	}

	// 書き込みが無くても End は呼ぶ（BulkWriter を放置しない）。
	batch.End()
	return nil
}

// KeyWordExposureP は登録済みの語を key_word として 1 回出したあとの P。
func KeyWordExposureP(p float64) float64 {
	return math.Min(PMax, p+KeyWordExposureStep)
}

// numField は Firestore の数値を float64 にする（整数は int64 で返る）。
func numField(v any) float64 {
	switch n := v.(type) {
	case float64:
		return n
	case int64:
		return float64(n)
	}
	return 0
}
