// Package poolreview は例文プールの確認待ち（Firestore の pool_review）と、
// OK を付けた文を本番プール（GCS）へ足す処理。
//
// dailyBatch が judge を通った文を確認待ちへ入れ（pool_review.go）、人が
// pool-review スキルで OK / NG を付け、cmd/poolreview が本番プールへ移す。
// 設計は docs/design_listening_playback.md「プールへの追加」。
package poolreview

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"strings"

	"cloud.google.com/go/storage"

	"github.com/mnbst/thai-memo/functions/go/internal/lang"
	"github.com/mnbst/thai-memo/functions/go/internal/sentence"
)

// Collection は確認待ちの Firestore コレクション。1文1 doc。
const Collection = "pool_review"

// 確認待ちの状態。確認済み（approved / rejected）も消さずに残し、
// 同じ文がまた生成されても確認待ちへ戻さない。
const (
	StatusPending  = "pending"
	StatusApproved = "approved"
	StatusRejected = "rejected"
)

// ID は確認待ちの doc ID。同じプールへ同じ文を二重に入れない。
// プールはティア×言語ごとに別なので、同じタイ語でも振り分け先が違えば別の文として扱う
// （訳が違うので、それぞれ確認する）。
func ID(tier string, l lang.Lang, thaiText string) string {
	sum := sha256.Sum256([]byte(tier + "|" + string(l) + "|" + thaiText))
	return hex.EncodeToString(sum[:])
}

// MergePool は既存プールへ新しい例文を足す。
//
// thai_text が既にあるものは飛ばす（同じ文を2本持っても抽選が偏るだけ）。
//
// 本数の上限は持たない。同じ人には既出の文を出さないので、在庫が多いほど
// よく使う人が LLM 生成に落ちるまでが延びる（以前は2万本で古い側から
// 落としていた）。1本 1〜2KB で、CorpusBank がインスタンスへ全部載せるので、
// 増えたら関数のメモリ（generateThaiSentence 等は 2Gi）と起動時間を見る。
func MergePool(existing, incoming []sentence.Sentence) ([]sentence.Sentence, int) {
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
	return merged, added
}

// ApplyFix は確認待ちの文 orig に人の修正 fix を重ねる。
//
// fix は sentence と同じ形の一部（thai_text・pronunciation・japanese_translation・
// word_breakdown 等）で、書いたキーだけを丸ごと差し替える（word_breakdown は配列ごと）。
// 直した結果は CheckFixed を通らなければ返さない。
func ApplyFix(orig, fix map[string]any) (sentence.Sentence, error) {
	merged := make(map[string]any, len(orig)+len(fix))
	for k, v := range orig {
		merged[k] = v
	}
	for k, v := range fix {
		merged[k] = v
	}
	b, err := json.Marshal(merged)
	if err != nil {
		return sentence.Sentence{}, err
	}
	var s sentence.Sentence
	if err := json.Unmarshal(b, &s); err != nil {
		return sentence.Sentence{}, err
	}
	return s, CheckFixed(s)
}

// PoolLabels はプールに書く品詞ラベルの言語。プールは言語によらず日本語のラベルで持ち、
// free_pool_en だけ英語（corpusbank.go の localizeBanked、cmd/poolretag の -labels）。
func PoolLabels(tier string, l lang.Lang) lang.Lang {
	if tier == "free" && l == lang.EN {
		return lang.EN
	}
	return lang.JA
}

// CheckFixed は手で直した文がプールの1件として崩れていないかを見る。
// 語の分解をつなげると本文になること、key_word が本文にあること。
func CheckFixed(s sentence.Sentence) error {
	if s.ThaiText == "" || s.Pronunciation == "" || s.JapaneseTranslation == "" {
		return errors.New("thai_text・pronunciation・訳のどれかが空")
	}
	var b strings.Builder
	for _, w := range s.WordBreakdown {
		b.WriteString(w.Word)
	}
	if sentence.StripSpaces(b.String()) != sentence.StripSpaces(s.ThaiText) {
		return fmt.Errorf("word_breakdown をつなげても thai_text にならない: %q", b.String())
	}
	if s.KeyWord != "" && !strings.Contains(s.ThaiText, s.KeyWord) {
		return fmt.Errorf("key_word %q が thai_text にない", s.KeyWord)
	}
	return nil
}

// AppendPool は本番プール name へ incoming を足して書き戻す。足した本数を返す。
//
// 読んだ版（generation）から変わっていないときだけ書く。間に別の処理（poolrecheck 等）が
// 書いていたら失敗を返すので、流し直せばよい（その時点の内容に足し直す）。
func AppendPool(
	ctx context.Context, bucket *storage.BucketHandle, name string, incoming []sentence.Sentence,
) (int, error) {
	obj := bucket.Object(name)
	var existing []sentence.Sentence
	cond := storage.Conditions{DoesNotExist: true}
	attrs, err := obj.Attrs(ctx)
	switch {
	case errors.Is(err, storage.ErrObjectNotExist):
	case err != nil:
		return 0, fmt.Errorf("%s を読めない: %w", name, err)
	default:
		r, err := obj.Generation(attrs.Generation).NewReader(ctx)
		if err != nil {
			return 0, fmt.Errorf("%s を読めない: %w", name, err)
		}
		err = json.NewDecoder(r).Decode(&existing)
		r.Close()
		if err != nil {
			return 0, fmt.Errorf("%s の JSON 解析に失敗: %w", name, err)
		}
		cond = storage.Conditions{GenerationMatch: attrs.Generation}
	}
	merged, added := MergePool(existing, incoming)
	if added == 0 {
		return 0, nil
	}
	data, err := json.Marshal(merged)
	if err != nil {
		return 0, err
	}
	w := obj.If(cond).NewWriter(ctx)
	w.ContentType = "application/json"
	if _, err := w.Write(data); err != nil {
		w.Close()
		return 0, err
	}
	return added, w.Close()
}
