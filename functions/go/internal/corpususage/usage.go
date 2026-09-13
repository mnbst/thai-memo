// Package corpususage は確定したコーパスの文に「使い方」の情報を後から付ける。
// 静的コーパスの生成だけが使う（配信経路は1回の生成で context まで作る）。
//
// 付けるのはアプリの「使い方」セクション（detail_screen.dart:_buildContextSection）
// が読む4項目。コーパスは topic と subTheme しか持っておらず、そのままでは
// 画面のこの欄がほぼ空になる。
//
// 日英を1回のレスポンスで作るのは corpustrans と同じ理由。同じ文の説明なので、
// 別々に生成すると日本語版と英語版で内容がずれる。
package corpususage

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"

	"github.com/mnbst/thai-memo/functions/go/internal/lang"
	"github.com/mnbst/thai-memo/functions/go/internal/sentence"
)

// Styles は style に入れてよい値。sentence.styleLabelsEN のキーと一致させること。
// ここにない文字列を入れると、en 配信でラベルが日本語のまま出る。
var Styles = []string{
	"口語体（友達同士のカジュアルな話し言葉）",
	"丁寧語（フォーマルな敬語・丁寧な表現）",
	"ニュース記事体（客観的・フォーマルな報道文体）",
	"SNS・テキストメッセージ（略語・絵文字・短い表現）",
	"物語・文学体（描写的・書き言葉的な表現）",
}

// Input は説明を付ける対象。文・訳は確定済みで、ここでは変えない。
type Input struct {
	ThaiText      string
	Pronunciation string
	JA            string
	EN            string
	TargetWord    string
	Topic         string
	SubTheme      string
}

// Result は1文ぶんの「使い方」。ja / en は同じ内容の日本語版・英語版で、
// それぞれ corpus_sentences_ja.json / _en.json の context に入る。
type Result struct {
	Style     string `json:"style"`
	EmotionJA string `json:"emotion_ja"`
	EmotionEN string `json:"emotion_en"`
	UsageJA   string `json:"usage_ja"`
	UsageEN   string `json:"usage_en"`
	CultureJA string `json:"culture_ja"`
	CultureEN string `json:"culture_en"`
}

const systemPrompt = "あなたはタイ語の学習教材を作る編集者です。" +
	"確定したタイ語の例文に、学習者向けの使い方の説明を付けます。文と訳は変更しません。" +
	"出力は指定されたJSONスキーマに従ってください。"

// BuildPrompt は説明を作らせるプロンプト。
//
// 例は載せない（載せると全文がその場面・その言い回しに寄る）。
// 文体だけは正常形が5つに閉じているので選択肢を列挙する。
func BuildPrompt(in Input) string {
	var b strings.Builder
	b.WriteString("次のタイ語文に、学習者向けの使い方の説明を付けてください。\n\n")
	fmt.Fprintf(&b, "タイ語文: %s\n", in.ThaiText)
	if in.Pronunciation != "" {
		fmt.Fprintf(&b, "発音: %s\n", in.Pronunciation)
	}
	fmt.Fprintf(&b, "日本語訳: %s\n", in.JA)
	fmt.Fprintf(&b, "英訳: %s\n", in.EN)
	fmt.Fprintf(&b, "学習対象の語: %s\n", in.TargetWord)
	if in.Topic != "" {
		fmt.Fprintf(&b, "場面: %s", in.Topic)
		if in.SubTheme != "" {
			fmt.Fprintf(&b, " / %s", in.SubTheme)
		}
		b.WriteString("\n")
	}

	b.WriteString("\n【style】次から1つ選ぶ（この5つ以外は禁止）\n")
	for _, s := range Styles {
		fmt.Fprintf(&b, "- %s\n", s)
	}
	// 丁寧語の過剰判定を止める。訳文（日本語は「です・ます」で訳す規約）を
	// 見て丁寧語に倒すので、判定はタイ語の文末詞だけに縛る。
	b.WriteString("判定はタイ語本文だけで行う。訳文の「です・ます」は根拠にしない。\n" +
		"ครับ / ค่ะ / คะ が無い文は丁寧語ではない。\n")

	b.WriteString(`
【usage_ja / usage_en】
- この文を実際に口にする場面。だれに向かって・どんな状況で言うか。
- 訳文の言い換えは禁止。訳を読めばわかることは書かない。

【culture_ja / culture_en】
- この文を使うときに日本語話者・英語話者が外しやすい点。丁寧さの度合い、
  相手との関係、タイの習慣のうち、この文に関係するものだけ。
- 一般論（タイ人は礼儀正しい等）は禁止。この文の語・言い回しに即して書く。
- 学習対象語そのものの語義説明は禁止（単語欄に別途出る）。文全体の使われ方を書く。

_ja と _en は同じ内容にする（一方だけに情報を足さない）。字数と言語は
スキーマの指定に従うこと。
`)
	return b.String()
}

// Schema は構造化レスポンスのスキーマ。
//
// 各フィールドの説明は配信経路のスキーマ（sentence.ContextFieldSchema）から
// 引く。字数や言語の指定をここに書き写すと、同じ context の同じキーなのに
// コーパスぶんだけ条件が違う状態になる。
//
// style だけは選択肢を enum で閉じる。日本語ラベルが en 配信のラベル
// 差し替え（styleLabelsEN）のキーなので、自由記述にすると差し替えが効かない。
func Schema() map[string]any {
	field := func(name string, l lang.Lang) map[string]any {
		f := sentence.ContextFieldSchema(name, l)
		if f == nil {
			f = map[string]any{"type": "string"}
		}
		return f
	}
	style := field("style", lang.JA)
	style["enum"] = toAnySlice(Styles)

	// emotion だけ字数を足す。配信ぶんの定義には字数が無く、実測では
	// prod の生成が平均5.4字に収まるのに対し、この後付けでは句で返って
	// 平均が倍になった（2026-09-12、rank300 の1392件）。画面は1行なので
	// 長いほうが不揃いに見える。説明の書き換えではなく末尾に足すだけに
	// して、配信ぶんとの差分がこの1行だと読めるようにする。
	emotionJA := field("emotion", lang.JA)
	emotionJA["description"] = fmt.Sprintf("%v。10文字以内、体言止め", emotionJA["description"])
	emotionEN := field("emotion", lang.EN)
	emotionEN["description"] = fmt.Sprintf("%v。3語以内", emotionEN["description"])
	return map[string]any{
		"type":                 "object",
		"additionalProperties": false,
		"properties": map[string]any{
			"style":      style,
			"emotion_ja": emotionJA,
			"emotion_en": emotionEN,
			"usage_ja":   field("usage_scenarios", lang.JA),
			"usage_en":   field("usage_scenarios", lang.EN),
			"culture_ja": field("cultural_notes", lang.JA),
			"culture_en": field("cultural_notes", lang.EN),
		},
		"required": []any{
			"style", "emotion_ja", "emotion_en",
			"usage_ja", "usage_en", "culture_ja", "culture_en",
		},
	}
}

// Fill は1文に使い方の説明を付ける。
//
// style が選択肢外・項目が空のときは1回だけ作り直す。style は en 配信の
// ラベル差し替えのキーなので、外れた値を通すと英語画面に日本語が出る。
func Fill(ctx context.Context, gen sentence.Generator, in Input) (*Result, error) {
	prompt := BuildPrompt(in)
	var last error
	for range 2 {
		raw, err := gen.GenerateSentence(ctx, systemPrompt, prompt, true, "premium", Schema())
		if err != nil {
			return nil, err
		}
		res, err := decode(raw)
		if err != nil {
			return nil, err
		}
		if err := validate(res); err != nil {
			last = err
			prompt = BuildPrompt(in) + fmt.Sprintf(
				"\n【やり直し】前回の出力は %v。\n", err)
			continue
		}
		return res, nil
	}
	return nil, fmt.Errorf("USAGE_ERROR: %w", last)
}

func decode(raw map[string]any) (*Result, error) {
	b, err := json.Marshal(raw)
	if err != nil {
		return nil, err
	}
	var res Result
	if err := json.Unmarshal(b, &res); err != nil {
		return nil, fmt.Errorf("USAGE_ERROR: unexpected structured output: %w", err)
	}
	return &res, nil
}

func validate(res *Result) error {
	known := false
	for _, s := range Styles {
		if res.Style == s {
			known = true
			break
		}
	}
	if !known {
		return fmt.Errorf("style が選択肢外（%q）", res.Style)
	}
	for _, f := range []struct {
		name  string
		value string
	}{
		{"emotion_ja", res.EmotionJA}, {"emotion_en", res.EmotionEN},
		{"usage_ja", res.UsageJA}, {"usage_en", res.UsageEN},
		{"culture_ja", res.CultureJA}, {"culture_en", res.CultureEN},
	} {
		if strings.TrimSpace(f.value) == "" {
			return fmt.Errorf("%s が空", f.name)
		}
	}
	return nil
}

func toAnySlice(in []string) []any {
	out := make([]any, len(in))
	for i, s := range in {
		out[i] = s
	}
	return out
}
