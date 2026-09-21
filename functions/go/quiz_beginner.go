package function

import (
	"context"
	"log"
	"math/rand"
	"time"

	"cloud.google.com/go/firestore"

	"github.com/mnbst/thai-memo/functions/go/internal/lang"
	"github.com/mnbst/thai-memo/functions/go/internal/quizgen"
)

// 入門用の出題形式をまとめクイズに差し込む層。
//
// key_word は変えない。変えるのは「その語で何を問うか」だけなので、
// 形式を足すときはここに1行足して Convert を書く。

// beginnerQuizMaxVocab は入門用の形式を出す語彙スコアの上限。
//
// 語彙スコアが高い人は今の形式で自力で進められているので触らない。
// 本番 207 人の分布では 100 未満が 197 人（95%）、50〜200 のどこで切っても
// 対象は3ポイントしか動かないので、100 という数字自体に意味は無い。
//
// **記録と出題を同じ条件で囲うこと。** 記録だけを 100 未満に限ると、
// 100 を超えた人の部品 P が二度と更新されず、弱いと判定された部品が
// 永久にその形式を呼び続ける（抜け出す条件が存在しないループになる）。
const beginnerQuizMaxVocab = 100

// 入門用に回す問題数に上限は置かない。始めたばかりの人には5問とも
// 入門用でよく、語が通過するにつれて自然に従来の形式へ戻っていく
// （beginnerPassedField を参照）。実際の上限は出題可能な語のほうで、
// 単音節として引ける語は freq_rank 上位100語で52%、上位300語で38%。

// beginnerPassedField は uvm doc に持つ通過フラグ（形式名 -> 通過）。
//
// **一度立ったら下ろさない片方向のフラグにすること。** 回答のたびに
// 上下する量で出題形式を決めると、形式が振動する（正解 → 易しい形式 →
// 正解 → …）。通過した語は入門用から抜けるだけ、が唯一の遷移。
const beginnerPassedField = "beginner_passed"

// beginnerFormat は入門用の出題形式1つ。
type beginnerFormat struct {
	// Format はクライアントとの能力交渉に使う名前。
	Format string
	// Convert は生成元をその形式に変える。変えられなければ ok=false。
	Convert func(source quizSeedSource, l lang.Lang, rnd *rand.Rand) (quizSeedSource, bool)
}

// beginnerFormats は入門用の形式。増やすときはここに足す。
var beginnerFormats = []beginnerFormat{
	{Format: quizgen.FormatSpellingChoice, Convert: toSpellingSource},
}

// beginnerQuizEnabled は入門用の形式を出す対象ユーザーか。
//
// 見るのは vocab_test_vocab（語彙テストの測定値）で、estimated_vocab では
// ない。推定値は回答のたびに動くので、それで形式を切り替えると
// 「回答 → 推定 → 出題 → 回答」の自己参照になる（generate_quiz.go の
// quizKeyWordFilter に同じ事故の記録がある）。未受験（0）は対象に含める。
func beginnerQuizEnabled(userData map[string]any) bool {
	return intOf(userData["vocab_test_vocab"]) < beginnerQuizMaxVocab
}

// applyBeginnerFormats はまとめクイズの問題を入門用の形式へ差し替える。
// 差し替えた問題数を返す。
//
// passed は語ごとの通過済み形式（beginnerPassedWords）。一度正解した語は
// その形式に戻さず、従来の穴埋めへ進ませる。
func applyBeginnerFormats(
	sources []quizSeedSource, supported []string, l lang.Lang,
	passed map[string]map[string]bool,
) int {
	available := make([]beginnerFormat, 0, len(beginnerFormats))
	for _, f := range beginnerFormats {
		if supportsQuizFormat(supported, f.Format) {
			available = append(available, f)
		}
	}
	if len(available) == 0 {
		return 0
	}

	// ダミーは毎回変える。決め打ちの種で選ぶと同じ語に同じ誤りが
	// 繰り返し出て、誤ったほうを覚えてしまう。
	rnd := rand.New(rand.NewSource(time.Now().UnixNano()))

	applied := 0
	for _, i := range rnd.Perm(len(sources)) {
		for _, j := range rnd.Perm(len(available)) {
			if passed[sources[i].Seed.KeyWord][available[j].Format] {
				continue
			}
			converted, ok := available[j].Convert(sources[i], l, rnd)
			if !ok {
				continue
			}
			sources[i] = converted
			applied++
			break
		}
	}
	return applied
}

// beginnerPassedWords は語ごとの通過済み形式を uvm doc から読む。
//
// 読めなかった語は「未通過」に倒す（入門用のまま出る）。ここで失敗して
// 通過済みを取りこぼしても、同じ語をもう一度やさしい形式で出すだけで
// 害は無い。
func beginnerPassedWords(
	ctx context.Context, db *firestore.Client, uid string, words []string,
) map[string]map[string]bool {
	if len(words) == 0 {
		return nil
	}
	uvmRef := db.Collection("users").Doc(uid).Collection("uvm")
	refs := make([]*firestore.DocumentRef, 0, len(words))
	seen := map[string]bool{}
	for _, word := range words {
		if word == "" || seen[word] {
			continue
		}
		seen[word] = true
		refs = append(refs, uvmRef.Doc(word))
	}
	snaps, err := db.GetAll(ctx, refs)
	if err != nil {
		log.Printf("beginner_passed_words_unavailable uid=%s error=%v", uid, err)
		return nil
	}

	out := map[string]map[string]bool{}
	for _, snap := range snaps {
		if snap == nil || !snap.Exists() {
			continue
		}
		raw, ok := snap.Data()[beginnerPassedField].(map[string]any)
		if !ok {
			continue
		}
		formats := map[string]bool{}
		for format, value := range raw {
			if done, ok := value.(bool); ok && done {
				formats[format] = true
			}
		}
		if len(formats) > 0 {
			out[snap.Ref.ID] = formats
		}
	}
	return out
}

// markBeginnerPassed は入門用の形式で正解した語に通過フラグを立てる。
func markBeginnerPassed(
	ctx context.Context, db *firestore.Client, uid string, passed map[string][]string,
) {
	if len(passed) == 0 {
		return
	}
	uvmRef := db.Collection("users").Doc(uid).Collection("uvm")
	writer := db.BulkWriter(ctx)
	for word, formats := range passed {
		flags := make(map[string]any, len(formats))
		for _, format := range formats {
			flags[format] = true
		}
		// MergeAll なので他の項目（p など）には触らない。
		if _, err := writer.Set(uvmRef.Doc(word),
			map[string]any{beginnerPassedField: flags}, firestore.MergeAll); err != nil {
			log.Printf("beginner_passed_mark_failed uid=%s word=%s error=%v", uid, word, err)
			return
		}
	}
	writer.End()
}
