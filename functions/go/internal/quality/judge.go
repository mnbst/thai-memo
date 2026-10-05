// Package quality は生成済み例文の品質監査（judge）を担う。
//
// 生成経路には入れない。dailyBatch が前日ぶんの premium 例文を後追いで読み、
// 不自然と判定されたものだけを sentence_flags コレクションへ残す。
// 目的はユーザーへの表示ではなく、prompts_data.go を直す根拠を貯めること。
//
// 判定は TypeSafe の Jev（System One モデル）に観点ごとの Noul（はい/いいえの
// 確率）で聞く。1文につき1リクエストで、観点は並列に評価される。理由文は
// 書かせない。どの観点が閾値を超えたかがそのまま理由になる。
//
// 2026-09-25 の実測（prod 監査で目視確定した欠陥20件＋正常21件、2回ずつ）:
//
//	gpt-5-mini（理由文つき一括判定）  検出 7〜10/20・誤検出 1〜2/21・$0.00055/文
//	Jev 観点6問・閾値0.4                 検出 11〜12/20・誤検出 0/21・$0.00005/文
//
// ただし prod の前日ぶん245本にかけると閾値0.4では日本語訳 27%・英訳 57% が
// 不合格になった（目視の問題率は約10%）。正解セットが明らかな欠陥に偏っていて
// 誤検出が見えていなかった。そこで次の2点を変えた（正解セットの検出は 11/20 の
// まま、prod の不合格は日本語訳 14%・英訳 11% に下がる）:
//
//   - trans_add（訳の加筆・欠落）だけ閾値を 0.6 に上げる。「最近」の補いや
//     過去形など細かい揺れで 0.4〜0.6 に立つものが大半だった
//   - 英訳の文には訳の観点（trans_add / trans_wrong）を聞かない。当時の英訳は
//     直訳・時制なしを仕様にしており、加筆・誤訳の問いと噛み合わなかった。
//     2026-10-04 に英訳も自然な訳へ戻したので、英訳に聞くかは測り直して決める
//     Jev 生成ルール50本をそのまま         AUC 0.72。出力形式のルールが正常文でも
//     0.66〜0.76 で立ち、判定に使えない
//
// 生成ルールは「作り方」の指示で、出来上がった文の判定基準にはならない。
// 観点は判定用に書いた6問に限る。ラベルは単独・非盲検で n=41、閾値も同じ
// データで選んでいるので、prod の flagged 率で見直すこと。
package quality

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"sort"
	"strings"
	"time"

	"cloud.google.com/go/firestore"

	"github.com/mnbst/thai-memo/functions/go/internal/lang"
	"github.com/mnbst/thai-memo/functions/go/internal/secrets"
)

// Candidate は監査にかける例文 1 件。users/{uid}/sentences の doc から作る。
type Candidate struct {
	UID                 string
	SentenceID          string
	ThaiText            string
	Pronunciation       string
	JapaneseTranslation string
	KeyWord             string
	Topic               string
	Emotion             string
	GenerationTier      string
	// Lang は訳文の言語。英語なら訳の観点を聞かない。
	Lang      lang.Lang
	CreatedAt time.Time
}

// Verdict は不合格と判定した 1 件。
type Verdict struct {
	Index int
	// Reason は閾値を超えた観点のラベルを確率の高い順に並べたもの。
	Reason string
	// Scores は全観点の確率（観点 ID → はいの確率）。閾値の見直しに使う。
	Scores map[string]float64
	// Hits は閾値を超えた観点の ID（確率の高い順）。
	Hits []string
}

// RetryNotes は差し戻しプロンプト（sentence.BuildRetryConstraint）へ渡す指摘。
//
// Jev は箇所を名指ししないので、引っかかった観点の問い（Note があればそちら）を渡す。
// 前回の文は載せない（BuildRetryConstraint のコメント参照）。
func (v Verdict) RetryNotes() []string {
	notes := make([]string, 0, len(v.Hits))
	for _, id := range v.Hits {
		for _, a := range Aspects {
			if a.ID == id {
				text := a.Note
				if text == "" {
					text = strings.ReplaceAll(a.Question, "`", "")
				}
				notes = append(notes, "「"+a.Label+"」に問題があると判定された（"+text+"）")
			}
		}
	}
	return notes
}

// Aspect は判定の観点 1 つ。
type Aspect struct {
	ID       string
	Label    string
	Question string
	// Threshold を超えたら不合格。
	Threshold float64
	// JAOnly は日本語訳の文にだけ聞く観点。
	JAOnly bool
	// Note は差し戻しプロンプトへ渡す指摘。空なら Question を使う。
	// Question にタイ語の語を並べた観点は必ず持たせる。プロンプト中のタイ語は
	// ×の文脈でも生成側に写される（prompt-effect-ledger §3）。
	Note string
	// Check があればコードで判定する観点（Jev には送らない）。真なら不合格。
	// 文字種・記号のように確実に判定できるものは Jev に聞かない。
	Check func(Candidate) bool
	// Trigger があれば、真の文にだけ聞く（語ごとの用法の観点。rules.go）。
	Trigger func(Candidate) bool
}

// aspectPreamble は全観点の先頭に付ける state の説明。
// 観点は並列に評価され互いを見ないので、各問が単独で意味を持つようにする。
const aspectPreamble = "`thai_text` はタイ語学習用の例文、`japanese_translation` はその訳（日本語または英語）、`key_word` は学ばせたい語。"

// Aspects は判定の観点。文言は測ったものから変えない（変えたら測り直す）。
// 観点別 AUC（2026-09-25 正解セット）は collocation 0.94 / grammar 0.90 /
// coherence 0.89 / trans_wrong 0.94 / keyword 0.95。
//
// trans_drop と register は prod で見逃した2件（王室用語の誤り、เพื่อให้ の目的が
// 訳から抜ける）を受けて足した（2026-09-25）。罠30件（誤り15・正15）で:
//
//	register    王室・僧侶用語の誤り 7/7 検出、正しい文 ≤0.33。抽象的な問い（敬語の
//	            高さ）では 0/7 で、語を名指ししないと Jev は王室用語を見分けない
//	trans_drop  訳の欠落 6/7 検出（ต้อง だけ 0.33〜0.41）、正しい文 ≤0.16
//
// 正解セットの検出は 11→13/20・誤検出 0 のまま。prod 前日245本の不合格は
// 29→32本。trans_drop は 0.3 だと自然な訳が 0.34〜0.41 で11本立つので 0.45。
//
// register_mix（2026-09-26）はプールに入った ×คำแนะนำของมึงยอดเยี่ยมมาก を受けて
// 足した。gpt-5-mini の旧 judge でも 0/4 で拾えなかったクラス。罠18件で:
//
//	誤っている語を名指し  誤り 8/8（≥0.90）・正しい文 0/10（≤0.20）・prod 3/245（3本とも本物）
//	正しい語も名指し      同じ罠で同等だが prod で境界の誤検出が +3
//	タイ語の例なし        正しい文 5/10 を不合格にする。使えない
var Aspects = append([]Aspect{
	{ID: "collocation", Label: "共起", Threshold: Threshold,
		Question: "`thai_text` の中に、タイ語母語話者が使わない語の組み合わせ（動詞と目的語、名詞と修飾語、副詞の係り先）があるか"},
	{ID: "grammar", Label: "文法", Threshold: Threshold,
		Question: "`thai_text` に文法の誤り（語の重複、類別詞の誤用、語順の誤り）があるか"},
	{ID: "coherence", Label: "意味・接続", Threshold: coherenceThreshold,
		Question: "`thai_text` をタイ語の母語話者が読んだとき、何を言いたい文なのかが分からない、または前半と後半が別々の話になっているか（あいさつ・前置きと無関係な用件をつなげる、比喩や理由が成り立たない、時を表す語と述語が噛み合わない等）"},
	{ID: "conjunction", Label: "接続語の論理", Threshold: conjunctionThreshold,
		Question: "`thai_text` の接続語（เพราะ、เลย、ก็เลย、ดังนั้น、แต่、แม้ว่า、ถึง 等）が、前後の内容の関係と合っていないか。理由・結果の接続語でつないだのに後ろが前の理由・結果として成り立たない（本来は逆接でつなぐべき）もの、逆接の接続語でつないだのに前後が対立していないものを含む",
		Note:     "thai_text の接続語が前後の関係と合っていなかった（理由の接続語でつないだが、中身は逆接の関係だった等）。前後の関係に合う接続語を使う"},
	{ID: "register", Label: "王室・僧侶用語", Threshold: Threshold,
		Question: "`thai_text` で王族（พระองค์、พระราชา、พระราชินี 等）や僧侶（พระ、หลวงพ่อ 等）の動作・所有・発言を、一般の人向けの語（กิน、นอน、มา、พูด、ให้、ทราบ 等）で表しているか。王族には王室用語（เสด็จ、เสวย、ตรัส、ทรงทราบ 等）、僧侶には僧侶用語（ฉัน、จำวัด、ถวาย 等）を使うのが正しい",
		Note:     "王族や僧侶の動作・所有・発言を一般の人向けの語で書いていた。王族には王室用語、僧侶には僧侶用語を使う"},
	{ID: "register_mix", Label: "語の高さの混在", Threshold: Threshold,
		Question: "`thai_text` で、くだけた人称（มึง、กู、แก 等）を使う文の中に、改まった語・書き言葉（ยอดเยี่ยม、ดำเนินการ、สามารถ、ต้องการ、เนื่องจาก、อย่างไร、รับประทาน、ขอบพระคุณ 等）を混ぜているか",
		Note:     "くだけた人称を使う文に、改まった語・書き言葉を混ぜていた。くだけた文には口語の語を使う"},
	{ID: "trans_add", Label: "訳の加筆", Threshold: transAddThreshold, JAOnly: true,
		Question: "`japanese_translation` に `thai_text` に無い情報（時制、場所、理由、括弧の補足）が足されているか"},
	{ID: "trans_drop", Label: "訳の欠落", Threshold: transDropThreshold, JAOnly: true,
		Question: "`japanese_translation` から、`thai_text` にある目的・条件・否定・可能性・義務・譲歩を表す語（เพื่อ、เพื่อให้、ถ้า、ไม่、อาจจะ、ต้อง、ทั้งที่ など）の意味が抜けているか。「〜ために」を「〜し、」と並べただけの訳も抜けに含む",
		Note:     "japanese_translation から、thai_text にある目的・条件・否定・可能性・義務・譲歩の意味が抜けていた。「〜ために」を「〜し、」と並べただけの訳も抜けに含む"},
	{ID: "trans_conj", Label: "訳の接続", Threshold: Threshold, JAOnly: true,
		Question: "`japanese_translation` が、`thai_text` の接続語（เพราะ=理由、แต่・แม้ว่า=逆接、ถ้า=条件 等）と違う関係で前後をつないでいるか（理由の เพราะ を「〜が」「〜のに」と逆接で訳す等）",
		Note:     "japanese_translation が、thai_text の接続語と違う関係（理由を逆接で訳す等）で前後をつないでいた"},
	{ID: "trans_vocative", Label: "呼称の音写", Threshold: vocativeThreshold, JAOnly: true,
		Question: "`japanese_translation` に、`thai_text` の呼称（เฮีย、เจ๊、พี่、น้อง 等）をカタカナで音を写した語（ヘイ、ヒア、ヘイア、ジェー、ピー 等）が入っているか。人名・あだ名（カン、ホーム 等）をカタカナで書いたものは含まない",
		Note:     "japanese_translation で、thai_text の呼称をカタカナで音写していた。呼称は音写せず、日本語の呼び方にするか省く"},
	{ID: "trans_thai", Label: "訳にタイ文字", JAOnly: false,
		Note:  "japanese_translation にタイ文字が残っていた。訳にはタイ文字を書かない",
		Check: func(c Candidate) bool { return containsThai(c.JapaneseTranslation) }},
	{ID: "trans_paren", Label: "訳の括弧補足", JAOnly: true,
		Note:  "japanese_translation に括弧で補足を書いていた。括弧を使わずに訳す",
		Check: func(c Candidate) bool { return strings.ContainsAny(c.JapaneseTranslation, "（(") }},
	// 以下4つは rules.go（測定値もそちら）。
	{ID: "trans_term", Label: "訳に文法用語",
		Note:  "japanese_translation に品詞名・文法用語や角括弧を書いていた。対応する語が無いものは訳さずに落とす",
		Check: gramTerm},
	{ID: "trans_bare_not", Label: "英訳の否定の形",
		Note:  "japanese_translation の否定を助動詞なしの not で書いていた。do not / does not など自然な英語の否定にする",
		Check: bareNot},
	{ID: "trans_lexicon", Label: "既知の誤訳",
		Note:  "japanese_translation で、thai_text の語を、それより狭い別の物を指す訳語で訳していた。thai_text の語が指す範囲のまま訳す",
		Check: knownMistrans},
	{ID: "word_misuse", Label: "語の場面違い",
		Note:  "thai_text で、日本語訳が当てはまるだけの語を別の場面に当てていた（体調の語を物の感想に、山頂の語を物や体の上端に、推量の語を依頼の前置きに、乗り場の名を乗り物に）。その場面でタイ語の話者が実際に使う言い方にする",
		Check: wordMisuse},
	{ID: "concessive_head", Label: "譲歩の形",
		Note:  "thai_text で、「〜であっても」を表す文末の語を、「たとえ／どんなに／何であれ」に当たる前置きなしで置いていた。前置きを足すか、文末の語を外す",
		Check: concessiveNoHead},
	// 呼称の音写は trans_vocative が見る。ここに例として残すと、あだ名の正しい
	// カタカナ表記（カン先輩、マウィンさん）まで誤訳にされる（2026-09-26 評価セットで
	// 正常の誤検出 14→8〜11/70、欠陥の検出 45/55 のまま）。
	{ID: "trans_wrong", Label: "誤訳", Threshold: Threshold, JAOnly: true,
		Question: "`japanese_translation` が `thai_text` の語を誤訳している（別の意味の語で訳す、動作の主体を取り違える）か"},
	{ID: "keyword", Label: "key_word の用法", Threshold: Threshold,
		Question: "`key_word` が `thai_text` の中で不自然に、または本来と違う意味で使われているか"},
	// その場で作ったたとえ（×หัวใจผมวิ่งอยู่ในเลนเดียวกับคุณ）だけを落とし、定着した言い回しは
	// 通す（2026-10-01）。BL罠と prod プールの目視ラベルで、不自然 16/18 検出・定着／字義どおり
	// 2/20 誤検出・prod プール 3/233。定着側の語を名指ししないと検出が 14/18 に落ちる。
	{ID: "metaphor", Label: "その場で作ったたとえ", Threshold: Threshold,
		Question: "`thai_text` で、気持ち・関係・人生を物や場所に見立てたたとえのうち、タイ語の母語話者が普段使わない、その場で作ったたとえを使っているか。タイ語で定着した言い回し（อารมณ์ระเบิด、ข้ามเขตเพื่อน、หมูๆ、วงแขน 等）は含まない",
		Note:     "thai_text で、気持ちや関係を物や場所に見立てた、タイ語の母語話者が普段使わないたとえを使っていた。語を字義どおりに使うか、タイ語で定着した言い回しにする"},
}, wordUsageAspects()...)

// Threshold は観点の既定の閾値。これを超えた観点が1つでもあれば不合格。
// 0.4 で誤検出 0/21、0.35 で検出 +2 件・誤検出 +2〜3 件（2026-09-25）。
// 誤検出は sentence_flags の台帳を汚すので誤検出側に倒さない。
const Threshold = 0.4

// transAddThreshold は trans_add だけの閾値（パッケージ先頭のコメント参照）。
const transAddThreshold = 0.6

// transDropThreshold は trans_drop の閾値（Aspects のコメント参照）。
const transDropThreshold = 0.45

// coherenceThreshold は coherence の閾値。この問いは意味の通らない文にも
// 0.12〜0.38 しか付けないが、正常文は ≤0.18 に収まる（2026-09-26、罠25件）。
// 0.25 で prod 7日310本の新規不合格は3本（全部本物）、正解セットの正常 0/21。
const coherenceThreshold = 0.25

// conjunctionThreshold は conjunction の閾値。×สินค้าชิ้นนี้คืนได้ไหมเพราะซื้อเกินเจ็ดวันแล้ว
// （逆接を เพราะ でつなぐ）が 0.35〜0.37 だった。罠12件（2026-09-27）で接続の誤り
// 5/5 が ≥0.35、正しい文 7/7 が ≤0.11。この文は coherence では 0.08 しか立たない。
// prod 7日338本で conjunction / trans_conj が立ったのはこの文だけ（trans_conj 0.64）。
const conjunctionThreshold = 0.3

// vocativeThreshold は trans_vocative の閾値。罠179件で 0.6 以上なら音写 42/42・
// 誤検出 0/137 だが、prod で正しいあだ名表記（カン先輩）が 0.64 になったので 0.7。
const vocativeThreshold = 0.7

// containsThai は s にタイ文字があるか。
func containsThai(s string) bool {
	for _, r := range s {
		if r >= 0x0E00 && r <= 0x0E7F {
			return true
		}
	}
	return false
}

// jevAspects は Jev に送る観点（コードで判定する観点を除く）。
func jevAspects(aspects []Aspect) []Aspect {
	out := make([]Aspect, 0, len(aspects))
	for _, a := range aspects {
		if a.Check == nil {
			out = append(out, a)
		}
	}
	return out
}

// aspectsFor は c に聞く観点を返す。
func aspectsFor(c Candidate) []Aspect {
	return aspectsIn(Aspects, c)
}

// aspectsIn は list のうち c に聞く観点を返す。
func aspectsIn(list []Aspect, c Candidate) []Aspect {
	out := make([]Aspect, 0, len(list))
	for _, a := range list {
		if a.JAOnly && c.Lang == lang.EN {
			continue
		}
		if a.Trigger != nil && !a.Trigger(c) {
			continue
		}
		out = append(out, a)
	}
	return out
}

const (
	defaultEndpoint = "https://api.typesafe.ai/v1/systemone"
	DefaultModel    = "jev-latest"
)

// NewJudge は Secret Manager の typesafe-api-key で Judge を組み立てる。
// ローカルでは環境変数 TYPESAFE_API_KEY が優先される（secrets.Get）。
func NewJudge(ctx context.Context) (*Judge, error) {
	key, err := secrets.Get(ctx, "typesafe-api-key")
	if err != nil {
		return nil, err
	}
	return &Judge{APIKey: key, Model: DefaultModel}, nil
}

// Judge は例文を Jev で判定する。
type Judge struct {
	APIKey string
	// Model は Jev のモデル名。空なら jev-latest。
	Model string
	// Endpoint と HTTP はテストで差し替える。空なら既定値。
	Endpoint string
	HTTP     *http.Client
}

// Result は 1 バッチの判定結果。
type Result struct {
	// Flagged / Verdicts は不自然と判定されたもの（sentence_flags へ書く）。
	Flagged  []Candidate
	Verdicts []Verdict
	// Accepted は自然と判定されたもの（例文プールへ回す）。
	Accepted []Candidate
}

// JudgeBatch は batch を判定し、報告対象の Candidate と Verdict の組を返す。
func (j *Judge) JudgeBatch(ctx context.Context, batch []Candidate) ([]Candidate, []Verdict, error) {
	res, err := j.Review(ctx, batch)
	return res.Flagged, res.Verdicts, err
}

// Review は batch を1文ずつ判定し、落とした側と通した側の両方を返す。
//
// 呼び出しに失敗した文はどちらにも入れない（無言の欠落を合格にしない）。
// 失敗があっても判定できた分は返し、エラーはまとめて返す。
func (j *Judge) Review(ctx context.Context, batch []Candidate) (Result, error) {
	return j.review(ctx, batch, Aspects)
}

// review は list の観点で batch を判定する（Review / ReviewPool の本体）。
func (j *Judge) review(ctx context.Context, batch []Candidate, list []Aspect) (Result, error) {
	var res Result
	var errs []error
	for i, c := range batch {
		aspects := aspectsIn(list, c)
		scores, err := j.score(ctx, c, aspects)
		if err != nil {
			errs = append(errs, fmt.Errorf("%s: %w", FlagID(c), err))
			continue
		}
		if v, bad := verdictFrom(i, aspects, scores); bad {
			res.Flagged = append(res.Flagged, c)
			res.Verdicts = append(res.Verdicts, v)
		} else {
			res.Accepted = append(res.Accepted, c)
		}
	}
	return res, errors.Join(errs...)
}

// verdictFrom は観点ごとの確率から合否を決める。aspects はその文に聞いた観点。
func verdictFrom(index int, aspects []Aspect, scores map[string]float64) (Verdict, bool) {
	var hits []Aspect
	for _, a := range aspects {
		if scores[a.ID] > a.Threshold {
			hits = append(hits, a)
		}
	}
	if len(hits) == 0 {
		return Verdict{}, false
	}
	sort.SliceStable(hits, func(x, y int) bool { return scores[hits[x].ID] > scores[hits[y].ID] })
	parts := make([]string, len(hits))
	ids := make([]string, len(hits))
	for i, a := range hits {
		parts[i] = fmt.Sprintf("%s %.2f", a.Label, scores[a.ID])
		ids[i] = a.ID
	}
	return Verdict{Index: index, Reason: strings.Join(parts, "・"), Scores: scores, Hits: ids}, true
}

// jevState は Jev に渡す state。フィールドの順序に意味がある（下記）。
type jevState struct {
	ThaiText            string `json:"thai_text"`
	JapaneseTranslation string `json:"japanese_translation"`
	KeyWord             string `json:"key_word,omitempty"`
}

// RequestBody は Jev へ送る本文を組む。
//
// state には判定に要る3項目だけ置く。発音は渡さない（読ませる情報を増やすほど
// 注意が散る）。空の key_word は項目ごと出さない。
//
// state は map ではなく構造体で渡し、thai_text を先頭に固定する。Jev は
// state のキー順で確率が大きく動く（2026-09-25、同じ6文で thai_text 先頭
// 0.16〜0.61 → map の辞書順＝japanese_translation 先頭 0.41〜0.87）。
// 閾値は thai_text 先頭で測ったもの。criteria の順序はほぼ効かない。
func RequestBody(model string, c Candidate) map[string]any {
	return requestBody(model, c, aspectsFor(c))
}

// requestBody は aspects（その文に聞く観点）で本文を組む。
func requestBody(model string, c Candidate, aspects []Aspect) map[string]any {
	state := jevState{
		ThaiText:            c.ThaiText,
		JapaneseTranslation: c.JapaneseTranslation,
		KeyWord:             c.KeyWord,
	}
	questions := make(map[string]any, len(aspects))
	for _, a := range jevAspects(aspects) {
		questions[a.ID] = map[string]any{
			"type":         "noul",
			"instructions": aspectPreamble + a.Question,
			"criteria": map[string]string{
				"true":  "はい、問題がある",
				"false": "いいえ、問題はない",
			},
		}
	}
	return map[string]any{"model": model, "state": state, "questions": questions}
}

// score は 1 文を aspects（その文に聞く観点）で判定し、観点 ID → はいの確率 を返す。
// 429 / 529 は指数バックオフで数回だけ再試行する。
func (j *Judge) score(ctx context.Context, c Candidate, aspects []Aspect) (map[string]float64, error) {
	body, err := json.Marshal(requestBody(j.model(), c, aspects))
	if err != nil {
		return nil, err
	}
	client := j.HTTP
	if client == nil {
		client = &http.Client{Timeout: 30 * time.Second}
	}
	endpoint := j.Endpoint
	if endpoint == "" {
		endpoint = defaultEndpoint
	}

	const maxAttempts = 4
	for attempt := 0; ; attempt++ {
		req, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint, bytes.NewReader(body))
		if err != nil {
			return nil, err
		}
		req.Header.Set("Authorization", "Bearer "+j.APIKey)
		req.Header.Set("Content-Type", "application/json")
		resp, err := client.Do(req)
		if err != nil {
			return nil, err
		}
		raw, err := io.ReadAll(resp.Body)
		resp.Body.Close()
		if err != nil {
			return nil, err
		}
		retryable := resp.StatusCode == http.StatusTooManyRequests || resp.StatusCode == 529
		if retryable && attempt+1 < maxAttempts {
			select {
			case <-ctx.Done():
				return nil, ctx.Err()
			case <-time.After(time.Duration(1<<attempt) * time.Second):
			}
			continue
		}
		if resp.StatusCode != http.StatusOK {
			return nil, fmt.Errorf("jev: status %d: %s", resp.StatusCode, strings.TrimSpace(string(raw)))
		}
		scores, err := ParseScores(raw, jevAspects(aspects))
		if err != nil {
			return nil, err
		}
		// コードで判定する観点は 1（不合格）/ 0 で並べる。
		for _, a := range aspects {
			if a.Check == nil {
				continue
			}
			scores[a.ID] = 0
			if a.Check(c) {
				scores[a.ID] = 1
			}
		}
		return scores, nil
	}
}

// ParseScores は Jev のレスポンスから観点ごとの確率を取り出す。
// 観点が1つでも欠けていたら判定不能として扱う（欠けた観点を合格にしない）。
func ParseScores(raw []byte, aspects []Aspect) (map[string]float64, error) {
	var resp struct {
		Answers map[string]struct {
			Noul *float64 `json:"noul"`
		} `json:"answers"`
	}
	if err := json.Unmarshal(raw, &resp); err != nil {
		return nil, fmt.Errorf("jev: parse: %w", err)
	}
	out := make(map[string]float64, len(aspects))
	for _, a := range aspects {
		ans, ok := resp.Answers[a.ID]
		if !ok || ans.Noul == nil {
			return nil, fmt.Errorf("jev: answer %q missing", a.ID)
		}
		out[a.ID] = *ans.Noul
	}
	return out, nil
}

func (j *Judge) model() string {
	if j.Model != "" {
		return j.Model
	}
	return DefaultModel
}

// FlagID は sentence_flags の doc ID。uid と例文 ID から決める。
//
// 自動採番にすると、バッチを流し直したときに同じ文の指摘が二重に積まれ、
// 件数の集計が実行回数に引きずられる。
func FlagID(c Candidate) string {
	return c.UID + "_" + c.SentenceID
}

// FlagDoc は sentence_flags へ書く内容を組み立てる。
//
// 例文本文を複製して持つ。users/{uid}/sentences は退会で
// なくなるので、参照だけ残すと台帳が空洞になる。
// scores は閾値未満の観点も含めて残す（閾値を後から動かして数え直せる）。
func FlagDoc(c Candidate, v Verdict, judgeModel string, judgedAt time.Time) map[string]any {
	return map[string]any{
		"thai_text":            c.ThaiText,
		"pronunciation":        c.Pronunciation,
		"japanese_translation": c.JapaneseTranslation,
		"key_word":             c.KeyWord,
		"topic":                c.Topic,
		"emotion":              c.Emotion,
		"generation_tier":      c.GenerationTier,
		"uid":                  c.UID,
		"sentence_id":          c.SentenceID,
		"created_at":           c.CreatedAt,
		"judged_at":            judgedAt,
		"judge_model":          judgeModel,
		"reason":               v.Reason,
		"scores":               v.Scores,
	}
}

// Write は判定結果を sentence_flags へ書く。
func Write(
	ctx context.Context, db *firestore.Client,
	flagged []Candidate, verdicts []Verdict, judgeModel string, judgedAt time.Time,
) error {
	for i, c := range flagged {
		doc := FlagDoc(c, verdicts[i], judgeModel, judgedAt)
		if _, err := db.Collection("sentence_flags").Doc(FlagID(c)).Set(ctx, doc); err != nil {
			return err
		}
	}
	return nil
}
