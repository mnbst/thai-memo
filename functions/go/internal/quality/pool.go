package quality

import (
	"context"
	"slices"

	"github.com/mnbst/thai-memo/functions/go/internal/lang"
)

// Aspects に足す観点。生成直後の判定（ReviewAll）で Aspects と一緒に聞く。
//
// 場面として言わない文と、意味がずれた訳を落とす。どちらも文法・共起の誤りでは
// ないので Aspects では拾えない（prod プールの目視で欠陥と決めた 20本のうち、
// Aspects で落ちたのは 3本）。
//
// 2026-10-19 から表示とプールを同じ基準にしたので、誤検出はその文がセットから
// 外れることになるが、悪い文を拾う方を優先して検出側の閾値のまま使う。
//
// 2026-10-04 の実測（situation 0.35 / tmean 0.4、どちらか超えたら不合格）:
//
//	prod プール目視 40本（欠陥20・正常20）  検出 7/20・誤検出 0/20（2回とも同じ）
//	judge_eval.json 137本（欠陥60・正常77） 検出 26/60・誤検出 9/77
//	prod プール ja 372本                    不合格 25本（目視で欠陥 約12・境界 約7・誤検出 約6）
//
// judge_eval の誤検出は王室・僧侶用語の正しい文（改まった文を「普段言わない」と
// 取る）が多い。0.4 / 0.45 にすると judge_eval の誤検出 5/77・プールの不合格 8本まで
// 下がるが、検出も 16/60 に落ちる。
//
// 時を表す語どうしの矛盾（AUC 0.49）・必要な語の抜け（検出 2/60）・決まった
// 言い回しからのずれ（誤検出 22/77）も測ったが、どれも使えなかった。
//
// 2026-10-06 に prod プールの目視ラベル 91本で測って見送ったもの:
//
//	人名入りの文         検出はできる（prod プール ja 412本で 6/6・他の不合格 0）が、
//	                     人名入りの文は許容する方針にしたので入れない（静的コーパスにも約180本ある）
//	あいさつ＋別の用件   挨拶のあとに用件を続けるのはタイ語で自然。judge_eval の正常も落とす
//	時を表す語の矛盾     欠陥 0.21〜0.22・正常 0.18 で、Jev の揺れの中
//	訳の日本語の不自然さ judge_eval の誤検出 11/77・prod プールの不合格 46本
//	key_word のための無理な言い方  正常が 0.58 まで立つ
var PoolAspects = []Aspect{
	{ID: "situation", Label: "場面として言わない文", Threshold: situationThreshold,
		Question: "`thai_text` は、タイ語の母語話者が実際の場面で口にすることがほとんど無い文か（聞き手が今していることを聞き手本人に説明する、言う必要のない当たり前のことを述べる、場面に合わない時を表す語を足している 等）"},
	// 英訳では測っていないので日本語訳にだけ聞く。
	// 2026-11-21 に Gemini で、主体の取り違えと「〜したばかり」等の時の意味の抜けを例に足した
	// （ja 評価セット 欠陥 44→46/60・誤検出 3→2/80、prod 不合格82本 本物 18→22/39・誤検出 6/43 のまま）。
	// 「括弧の補足・場面に合わせた補いは当てはまらない」を足すと誤検出は減るが検出も 18→15 に落ちた。
	// 2026-11-26 に、言っていない持ち主の補い・役職の言い換えを足した（×ไอ้กัปตันนั่น→あいつのパイロット 0.50→0.89。
	// ja 評価セット 欠陥 50/61 のまま・誤検出 2→3/80、prod プール200件で 1→3）。
	// 文全体が usage_scenarios の場面に合うかを別に聞く問いは、同じ文が 0.27 で効かなかった。
	{ID: "tmean", Label: "訳の意味のずれ", Threshold: tmeanThreshold, Langs: jaOnly,
		Question: "`japanese_translation` を読んだ日本語話者が受け取る意味が、`thai_text` の意味と食い違うか（推量を意図として訳す、話し手・聞き手・動作の主体を取り違える、指す物や範囲を取り違える、「〜したばかり」「もう」などの時の意味を落とす・変える、原文に無い評価を足す、日本語として不自然で意味が変わる 等）。`thai_text` が言っていない持ち主（あいつの・彼の・私の 等）を訳が補ったもの、人の役職・職業を別の役職・職業に言い換えたものも食い違いに含む"},
	// tmean の英訳版。2026-11-20 に prod プール en の評価セット（欠陥54：Codex に1か所ずらさせた50＋
	// 確認で見つけた4、正常98）で測った。Jev 0.5 で欠陥 42/54・正常の誤検出 2/98（AUC 0.95）、
	// Luna は 0.7 で 36/54・4/98（AUC 0.88）。今の en プール 524本で 0.5 超は 13本。
	// 機能語の意味の抜け（เดี๋ยว・แล้ว・กัน 等）は 1/6 しか拾わない。
	// 2026-11-21 から Gemini に聞く（作り直した評価セット 欠陥55・正常145 で AUC Gemini 0.95・Jev 0.92。gemini.go）。
	// 同日、主語・持ち主を第三者に決めて補う訳を食い違いに含め、呼びかけの省略を外した
	// （同じ評価セットで欠陥 40→45/55・誤検出 7→4/145）。
	{ID: "en_mean", Label: "英訳の意味のずれ", Threshold: enMeanThreshold, Langs: []lang.Lang{lang.EN},
		Question: "`japanese_translation`（英訳）を読んだ英語話者が受け取る意味が、`thai_text` の意味と食い違う（時制、推量・義務の強さ、否定、依頼・勧誘・質問の区別、動作の主体、指す人や物を取り違える、原文に無い語や評価を足す 等）。`thai_text` が主語や持ち主を言っていないのに、英訳が he・she・his・they など第三者に決めて補ったものは食い違いに含む。呼びかけの語を訳さない・言い換えたものは当てはまらない"},
}

const (
	situationThreshold = 0.35
	tmeanThreshold     = 0.4
	enMeanThreshold    = 0.5
)

// ReviewAll は batch を Aspects と PoolAspects の両方で判定する。
// 生成直後の1回きりの判定で、表示とプールの共通の基準。
func (j *Judge) ReviewAll(ctx context.Context, batch []Candidate) (Result, error) {
	return j.review(ctx, batch, slices.Concat(Aspects, PoolAspects))
}

// ReviewPool は batch を PoolAspects だけで判定する。Review と同じく、
// 呼び出しに失敗した文は Flagged にも Accepted にも入れない。
func (j *Judge) ReviewPool(ctx context.Context, batch []Candidate) (Result, error) {
	return j.review(ctx, batch, PoolAspects)
}
