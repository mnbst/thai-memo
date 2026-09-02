// Package quality は生成済み例文の品質監査（judge）を担う。
//
// 生成経路には入れない。dailyBatch が前日ぶんの premium 例文を後追いで読み、
// 不自然と判定されたものだけを sentence_flags コレクションへ残す。
// 目的はユーザーへの表示ではなく、prompts_data.go を直す根拠を貯めること。
//
// 判定基準は与えない。観点を並べるとその観点しか見なくなり、想定外の
// 壊れ方が拾えない。タイ語・訳文・学習対象語だけ渡して、不自然なら理由を書かせる。
package quality

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"
	"time"

	"cloud.google.com/go/firestore"
)

// Generator は LLM を呼ぶ。internal/llm.Client がこれを満たす
// （internal/sentence.Generator と同じ形）。
type Generator interface {
	GenerateSentence(ctx context.Context, systemPrompt, userPrompt string,
		isPremium bool, tierLabel string, schema map[string]any) (map[string]any, error)
}

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
	CreatedAt           time.Time
}

// Verdict は judge の判定 1 件。
type Verdict struct {
	Index   int    `json:"index"`
	Natural bool   `json:"natural"`
	Reason  string `json:"reason"`
}

// SystemPrompt は judge の固定システムプロンプト。
//
// 呼び出しごとに変わらないので組み立てない（prompt caching の prefix になる）。
// 可変部（例文そのもの）は BuildUserPrompt 側だけに置く。
const SystemPrompt = `タイ語学習アプリが生成した例文を検査する。

key_word はその文で学ばせたい語。文はこの語を使うという条件で生成されている。
translation はその文の訳。アプリの表示言語によって日本語か英語のどちらかで、どちらも正しい。訳文が英語であること自体は問題にしない。

各 index について、タイ語がタイ語母語話者の書く自然な文になっているか、translation がその訳として正しいか、key_word の使い方が正しいかを見る。
問題が無ければ natural=true、reason は空文字。
問題があれば natural=false、reason に何がどう不自然かを日本語80文字以内で書く。どの語・どの箇所かを名指しする。

入力の全 index について1件ずつ返す。
迷うものは natural=true にする。`

// BuildUserPrompt は判定対象を index 付きで並べる。
//
// 例文はタグで囲う（指示との境界を誤らせない）。締めの1行は指示なので
// データの後ろに置く。
func BuildUserPrompt(batch []Candidate) string {
	var b strings.Builder
	b.WriteString("<sentences>\n")
	for i, c := range batch {
		fmt.Fprintf(&b, "[%d]\n", i)
		fmt.Fprintf(&b, "thai: %s\n", c.ThaiText)
		fmt.Fprintf(&b, "translation: %s\n", c.JapaneseTranslation)
		if c.KeyWord != "" {
			fmt.Fprintf(&b, "key_word: %s\n", c.KeyWord)
		}
	}
	b.WriteString("</sentences>\n")
	fmt.Fprintf(&b, "index 0〜%d の%d件すべてを判定する。", len(batch)-1, len(batch))
	return b.String()
}

// ResponseSchema は構造化出力のスキーマ。
//
// additionalProperties は OpenAI の strict json_schema が要求する。
// Gemini は受け付けないが、llm.GeminiSchema が送信前に落とす。
func ResponseSchema() map[string]any {
	return map[string]any{
		"type":                 "object",
		"additionalProperties": false,
		"properties": map[string]any{
			"results": map[string]any{
				"type": "array",
				"items": map[string]any{
					"type":                 "object",
					"additionalProperties": false,
					"properties": map[string]any{
						"index":   map[string]any{"type": "integer"},
						"natural": map[string]any{"type": "boolean"},
						"reason":  map[string]any{"type": "string"},
					},
					"required": []any{"index", "natural", "reason"},
				},
			},
		},
		"required": []any{"results"},
	}
}

// ParseVerdicts は LLM のレスポンスから、報告すべき判定だけを取り出す。
//
// 落とすもの:
//   - index が範囲外／重複（同じ文に2件返ってきたら先勝ち）
//   - natural=true（正常なものは記録しない）
//   - reason が空（理由の無い指摘は台帳の役に立たない）
func ParseVerdicts(raw map[string]any, batchSize int) []Verdict {
	data, err := json.Marshal(raw["results"])
	if err != nil {
		return nil
	}
	var results []Verdict
	if err := json.Unmarshal(data, &results); err != nil {
		return nil
	}

	seen := map[int]bool{}
	var out []Verdict
	for _, v := range results {
		if v.Index < 0 || v.Index >= batchSize || seen[v.Index] {
			continue
		}
		seen[v.Index] = true
		v.Reason = strings.TrimSpace(v.Reason)
		if v.Natural || v.Reason == "" {
			continue
		}
		out = append(out, v)
	}
	return out
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
// 例文本文を複製して持つ。users/{uid}/sentences は30日で消える
// （dailyBatch の cleanOldSentences）ので、参照だけ残すと台帳が空洞になる。
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
	}
}

// Judge は例文の束を判定する。
type Judge struct {
	Gen   Generator
	Model string
}

// JudgeBatch は 1 回の LLM 呼び出しで batch 全体を判定し、
// 報告対象の Candidate と Verdict の組を返す。
func (j *Judge) JudgeBatch(ctx context.Context, batch []Candidate) ([]Candidate, []Verdict, error) {
	if len(batch) == 0 {
		return nil, nil, nil
	}
	raw, err := j.Gen.GenerateSentence(ctx, SystemPrompt, BuildUserPrompt(batch),
		true, "judge", ResponseSchema())
	if err != nil {
		return nil, nil, err
	}
	verdicts := ParseVerdicts(raw, len(batch))
	flagged := make([]Candidate, len(verdicts))
	for i, v := range verdicts {
		flagged[i] = batch[v.Index]
	}
	return flagged, verdicts, nil
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
