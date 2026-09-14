// Package corpustrans は確定したタイ語文に日本語訳と英訳を後から付ける。
// 静的コーパスの生成だけが使う（配信経路は訳まで1回の生成で作る）。
//
// 訳を生成と分けるのは2つ理由がある。
//
//   - 日英を同じ1回のレスポンスで作れる。同じタイ語文を同じ読みから訳すので、
//     日本語版と英語版で意味がずれない（別々に生成すると文自体が変わる）。
//   - 訳の指示を、文を作らせる指示と混ぜずに書ける。生成側のプロンプトは
//     場面・長さ・語の制約で埋まっていて、訳の注文を足す余地がない。
package corpustrans

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"

	"github.com/mnbst/thai-memo/functions/go/internal/sentence"
)

// Input は訳を付ける対象。タイ語文は確定済みで、ここでは変えない。
type Input struct {
	ThaiText      string
	Pronunciation string
	// Words は word_breakdown の語。この順・この数でそのまま返させる。
	Words []string
	// TargetWord は学習対象の語。補足（notes）はこの語にだけ付ける。
	TargetWord string
	Topic      string
	SubTheme   string
}

// Gloss は1語ぶんの語義。
type Gloss struct {
	Word string `json:"word"`
	JA   string `json:"ja"`
	EN   string `json:"en"`
}

// Result は一文二訳の結果。
type Result struct {
	JA     string  `json:"ja"`
	EN     string  `json:"en"`
	Words  []Gloss `json:"words"`
	NoteJA string  `json:"note_ja"`
	NoteEN string  `json:"note_en"`
}

const systemPrompt = "あなたはタイ語の学習教材を作る翻訳者です。" +
	"タイ語の文を読み、日本語と英語の訳を作ります。文は変更しません。" +
	"出力は指定されたJSONスキーマに従ってください。"

// BuildPrompt は訳を作らせるプロンプト。
//
// 例は載せない。載せるとタイ語文のほうを例に寄せて訳す。
func BuildPrompt(in Input) string {
	var b strings.Builder
	b.WriteString("次のタイ語文に日本語訳と英訳を付けてください。\n\n")
	fmt.Fprintf(&b, "タイ語文: %s\n", in.ThaiText)
	if in.Pronunciation != "" {
		fmt.Fprintf(&b, "発音: %s\n", in.Pronunciation)
	}
	fmt.Fprintf(&b, "学習対象の語: %s\n", in.TargetWord)
	if in.Topic != "" {
		fmt.Fprintf(&b, "場面: %s", in.Topic)
		if in.SubTheme != "" {
			fmt.Fprintf(&b, " / %s", in.SubTheme)
		}
		b.WriteString("\n")
	}
	fmt.Fprintf(&b, "単語（この順・この数のまま返すこと）: %s\n",
		strings.Join(in.Words, " / "))

	b.WriteString(`
【訳の作り方】
- 日本語訳と英訳は同じ文の訳です。どちらも同じ内容を指すようにし、
  一方だけに情報を足したり落としたりしないこと。
- 逐語訳にしないこと。同じ場面で母語話者が言う自然な言い方にする。
- タイ語の丁寧さ（文末の丁寧語など）は、日本語では文体で、英語では
  語選びで表す。訳文に「〜です・ます」以上の説明を足さないこと。
- 主語や目的語がタイ語で省かれている場合、日本語では省いたまま、
  英語では文が成り立つよう補うこと。
- 人称は文脈から自然に決める。性別が分かる語が thai_text に無い三人称は
  they / them / their で訳すこと。he・she・him・her と、それらを
  スラッシュで併記した形（he/she、him/her）は英訳に書かないこと。

【語義】
- 各語の意味は、この文の中での意味を書く。辞書の語義を並べないこと。
- 機能語（助詞・接続詞など）は働きがわかる短い説明にする。
- 日本語の語義は日本語だけ、英語の語義は英語だけで書くこと。

【補足】
- note_ja / note_en は学習対象の語についてだけ書く。使い方や
  ニュアンス、他の語との違いを1〜2文で。
- 書くことがなければ空文字にする。埋めるために当たり障りのない
  説明を書かないこと。
`)
	return b.String()
}

// Schema は構造化レスポンスのスキーマ。
func Schema() map[string]any {
	str := func(desc string) map[string]any {
		return map[string]any{"type": "string", "description": desc}
	}
	return map[string]any{
		"type":                 "object",
		"additionalProperties": false,
		"properties": map[string]any{
			"ja": str("例文の日本語訳。必ず日本語で書くこと"),
			"en": str("例文の英訳。必ず英語で書くこと"),
			"words": map[string]any{
				"type":        "array",
				"description": "各単語の意味。渡した単語と同じ順・同じ数で返すこと",
				"items": map[string]any{
					"type":                 "object",
					"additionalProperties": false,
					"properties": map[string]any{
						"word": str("渡したタイ語の単語をそのまま"),
						"ja":   str("この文での意味を日本語で"),
						"en":   str("この文での意味を英語で"),
					},
					"required": []any{"word", "ja", "en"},
				},
			},
			"note_ja": str("学習対象の語の補足を日本語で。無ければ空文字"),
			"note_en": str("学習対象の語の補足を英語で。無ければ空文字"),
		},
		"required": []any{"ja", "en", "words", "note_ja", "note_en"},
	}
}

// Translate は1文に日英の訳を付ける。
//
// 語の数が合わなければ1回だけ作り直す。語義は word_breakdown の行に
// そのまま入るので、数がずれたまま返すと語と意味が1つずつずれる。
func Translate(ctx context.Context, gen sentence.Generator, in Input) (*Result, error) {
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
		if err := validate(res, in); err != nil {
			last = err
			prompt = BuildPrompt(in) + fmt.Sprintf(
				"\n【やり直し】前回の出力は %v。words は渡した単語を"+
					"そのままの順で %d 件返してください。\n", err, len(in.Words))
			continue
		}
		return res, nil
	}
	return nil, fmt.Errorf("TRANSLATE_ERROR: %w", last)
}

func decode(raw map[string]any) (*Result, error) {
	b, err := json.Marshal(raw)
	if err != nil {
		return nil, err
	}
	var res Result
	if err := json.Unmarshal(b, &res); err != nil {
		return nil, fmt.Errorf("TRANSLATE_ERROR: unexpected structured output: %w", err)
	}
	return &res, nil
}

func validate(res *Result, in Input) error {
	if strings.TrimSpace(res.JA) == "" || strings.TrimSpace(res.EN) == "" {
		return fmt.Errorf("訳が空")
	}
	if len(res.Words) != len(in.Words) {
		return fmt.Errorf("単語が %d 件（%d 件のはず）", len(res.Words), len(in.Words))
	}
	for i, w := range res.Words {
		if w.Word != in.Words[i] {
			return fmt.Errorf("%d 件目の単語が違う", i+1)
		}
		if strings.TrimSpace(w.JA) == "" || strings.TrimSpace(w.EN) == "" {
			return fmt.Errorf("%d 件目の語義が空", i+1)
		}
	}
	return nil
}
