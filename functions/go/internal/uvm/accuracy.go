package uvm

import (
	"context"
	"strings"

	"cloud.google.com/go/firestore"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

// まとめクイズの直近の正答率で、スコアの基準（窓の平均 P）を変える。
//
// 正答率が高い人は境界が前にあるのに証拠が追いつかず下振れし、低い人は
// まぐれ当たりで上振れする。直近 SummaryRecentSize 問の正答率で基準を
// 4 段に分ける（acccutoffsim_test.go の TestAccuracyCutoff）。d90 誤差の例
// （世界 推測0.45/slip0.10、現行 0.45 → 4 段）:
//
//	上級・伸びる 未受験  −360 → −215
//	中級・伸びる 未受験   −36 →   +4
//	中級・詰まる 受験    +120 → +115
//
// 1 回目から効かせる（20 問に満たないうちは解いた問数で出す）。10 問
// たまるまで待つ案と誤差はほぼ同じで、最後の 1 回（5 問）だけを見る案は
// まぐれの全問正解で基準が下がり、詰まる人の上振れが増えた。

// SummaryRecentField はユーザーdocに持つ直近の正誤（"1"=正解 "0"=不正解、
// 古い順）。クライアントに書かせると基準を下げられるので Firestore Rules で塞ぐ。
const SummaryRecentField = "summary_recent"

// SummaryRecentSize は正答率に使う直近の問数。
const SummaryRecentSize = 20

// summaryCutoffTiers は正答率の下限と基準（高い順）。どれにも当たらない
// （正答率 60% 未満）なら summaryLowCutoff。基準は UnknownWordP(0.4) より
// 上に置くこと。下回ると証拠の無い rank が「知っている」側に数えられる。
var summaryCutoffTiers = []struct{ minAcc, cutoff float64 }{
	{0.90, 0.41},
	{0.80, 0.42},
	{0.60, VocabCutoffP},
}

const summaryLowCutoff = 0.49

// AppendSummaryRecent は直近の正誤にまとめクイズの回答を足し、
// SummaryRecentSize 問に切る。ヒントを使った回答は不正解として数える
// （外すと迷った問題が抜けて正答率が高く出る）。
func AppendSummaryRecent(recent string, results []Result) string {
	var b strings.Builder
	b.WriteString(recent)
	for _, r := range results {
		if r.IsCorrect && r.HintLevel == 0 {
			b.WriteByte('1')
		} else {
			b.WriteByte('0')
		}
	}
	s := b.String()
	if len(s) > SummaryRecentSize {
		s = s[len(s)-SummaryRecentSize:]
	}
	return s
}

// SummaryCutoff はユーザーdocの直近の正誤からスコアの基準を返す。
// 記録が無ければ VocabCutoffP。
func SummaryCutoff(userData map[string]any) float64 {
	recent, _ := userData[SummaryRecentField].(string)
	if recent == "" {
		return VocabCutoffP
	}
	acc := float64(strings.Count(recent, "1")) / float64(len(recent))
	for _, t := range summaryCutoffTiers {
		if acc >= t.minAcc {
			return t.cutoff
		}
	}
	return summaryLowCutoff
}

// RecordSummaryResults はまとめクイズの回答をユーザーdocの直近の正誤に足す。
// 確認クイズ（quiz_type=="learning"）は答えが見えているので数えない。
// スコアの再計算（BatchUpdate 内の SyncEstimatedVocab）より前に呼ぶと、
// その回答から基準に効く。
func RecordSummaryResults(
	ctx context.Context,
	db *firestore.Client,
	uid string,
	quizType string,
	results []Result,
) error {
	if quizType == "learning" || len(results) == 0 {
		return nil
	}
	userRef := db.Collection("users").Doc(uid)
	return db.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		recent := ""
		snap, err := tx.Get(userRef)
		switch {
		case status.Code(err) == codes.NotFound:
		case err != nil:
			return err
		default:
			recent, _ = snap.Data()[SummaryRecentField].(string)
		}
		return tx.Set(userRef, map[string]any{
			SummaryRecentField: AppendSummaryRecent(recent, results),
		}, firestore.MergeAll)
	})
}
