package uvm

import (
	"context"
	"log"
	"math"
	"strings"

	"cloud.google.com/go/firestore"
)

// AlphaExposure は例文露出時の P 微増率（uvm.py:ALPHA_EXPOSURE）。
const AlphaExposure = 0.10

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

// RegisterExposure は露出による P 微増を適用する（uvm.py:register_exposure:519）。
//
//   - 登録済み語: P を AlphaExposure 分、出現回数だけ微増
//   - 未登録語: targetWords に含まれる場合のみ P=NewWordP で新規作成
//
// words は重複を含んでよい（回数として数える）。
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

	batch := db.BulkWriter(ctx)
	wrote := 0
	for _, word := range order {
		docRef := uvmRef.Doc(word)
		snap, err := docRef.Get(ctx)
		if err == nil && snap.Exists() {
			// 露出では P を動かさない。例文に出たことは「見た」証拠であって
			// 「知っている」証拠ではない。ExposureP には上限が無いので、
			// 同じ語が 6 回出るだけで P>0.5 になり、クイズを 1 問も解かずに
			// EstimateVocab の knownMaxRank に昇格して語彙スコアを押し上げていた。
			// last_seen だけ更新する。
			if _, err := batch.Update(docRef, []firestore.Update{
				{Path: "last_seen", Value: now},
			}); err != nil {
				return err
			}
			wrote += counts[word]
		} else if targets[word] {
			// key_word として選出された未登録語は新規作成
			if _, err := batch.Set(docRef, map[string]any{
				"word":          word,
				"p":             NewWordP,
				"quiz_attempts": 0,
				"last_seen":     now,
				"last_result":   nil,
				// 露出は「見た」証拠であって採点ではない。等倍のクイズに
				// 答えるまで境界推定の母数に入れない（IsGradedResult）。
				"graded": false,
			}); err != nil {
				return err
			}
			wrote++
		}
	}

	// 書き込みが無くても End は呼ぶ（BulkWriter を放置しない）。
	batch.End()
	if wrote > 0 {
		log.Printf("register_exposure: uid=%s, updated %d word(s)", uid, wrote)
	}
	return nil
}
