// Package sentence は例文生成の定数とロジック。
// functions/python/constants.py ほかの移植。
//
// データ部分（STYLES / TOPICS / ラベル表 / JSON Schema）は
// constants_data.go に自動生成してある。手で編集しないこと。
package sentence

import (
	"encoding/json"
	"os"
	"strings"

	"github.com/mnbst/thai-memo/functions/go/internal/lang"
)

// LLM プロバイダーとモデル。環境変数で上書きできる。
// モデル検証時に再デプロイのみで切り替えられるようにしている。
//
// gemini-2.5 系は 2026-08 時点で新規APIキーからは利用不可（404: no longer
// available to new users）。キーをローテートすると即座に生成が全停止するため
// 3.x 系を使う。
func Provider() string {
	return strings.ToLower(envOr("SENTENCE_PROVIDER", "gemini"))
}

func OpenAIModel() string        { return envOr("OPENAI_MODEL", "gpt-5.6-luna") }
func OpenAIModelPremium() string { return envOr("OPENAI_MODEL_PREMIUM", "gpt-5.6-luna") }
func GeminiModel() string        { return envOr("GEMINI_MODEL", "gemini-3.1-flash-lite") }
func GeminiModelPremium() string {
	return envOr("GEMINI_MODEL_PREMIUM", "gemini-3.1-flash-lite")
}

func envOr(name, fallback string) string {
	if v := os.Getenv(name); v != "" {
		return v
	}
	return fallback
}

const (
	// APIMaxTokens は最大出力トークン数。JSON 形式のレスポンス
	// （例文＋単語分解＋コンテキスト）に十分な量。
	APIMaxTokens = 8192

	// FreeTierMaxVocab は無料ティアの語彙上限（頻度順位）。
	FreeTierMaxVocab = 100
)

// SetSize は「1セット＝何本か」。毎日配信も、アプリからの生成も、この本数を
// ひとまとまりにして 例文 → 確認クイズ → …（SetSize本）… → まとめクイズ を
// 1サイクルとする。まとめクイズの間隔（クライアントの summaryQuizThreshold）と
// 必ず一致させること。docs/design_daily_sentence_batch.md を参照。
const SetSize = 5

// contextLabels は context の軸ラベル（サーバー側の日本語定数）の、1言語ぶんの表示名。
type contextLabels struct {
	topics     map[string]string
	topicHeads map[string]string
	styles     map[string]string
	timeFrames map[string]string
	subThemes  map[string]map[string]string
}

// contextLabelsByLang は ja 以外の言語のラベル表。ja は日本語定数をそのまま出す。
var contextLabelsByLang = map[lang.Lang]contextLabels{
	lang.EN: newContextLabels(topicLabelsEN, styleLabelsEN, timeFrameLabelsEN, subThemeLabelsEN),
	lang.KO: newContextLabels(topicLabelsKO, styleLabelsKO, timeFrameLabelsKO, subThemeLabelsKO),
}

func newContextLabels(
	topics, styles, timeFrames map[string]string, subThemes map[string]map[string]string,
) contextLabels {
	// topicHeads は括弧の例示を落とした短縮形（「食べ物」「旅行」）からの引き当て表。
	// サーバーがテーマを決めなかった回は LLM が選んで書くので短縮形が返る。
	// 完全一致だけだとそこが日本語のまま残る。
	heads := make(map[string]string, len(topics))
	for topic, label := range topics {
		heads[topicHead(topic)] = label
	}
	return contextLabels{topics, heads, styles, timeFrames, subThemes}
}

// topicHead は Python の topic.split("（")[0]。
func topicHead(topic string) string {
	if i := strings.Index(topic, "（"); i >= 0 {
		return topic[:i]
	}
	return topic
}

func (c contextLabels) topic(topic string) string {
	if label, ok := c.topics[topic]; ok {
		return label
	}
	if label, ok := c.topicHeads[topicHead(topic)]; ok {
		return label
	}
	return topic
}

// LocalizeContext は context の軸ラベルを訳文の言語に合わせる。
//
// ja はそのまま返す。他の言語は既知の日本語ラベルだけ差し替え、未知の値
// （LLM が自由記述する emotion・usage_scenarios や、既に訳したもの）は触らない。
// 冪等なので、訳したあとの例文にもう一度かけても壊れない。
func LocalizeContext(context map[string]any, l lang.Lang) map[string]any {
	labels, ok := contextLabelsByLang[l]
	if context == nil || !ok {
		return context
	}

	localized := make(map[string]any, len(context))
	for k, v := range context {
		localized[k] = v
	}

	topic, hasTopic := context["topic"].(string)
	if hasTopic {
		localized["topic"] = labels.topic(topic)
	}
	if style, ok := context["style"].(string); ok {
		if label, found := labels.styles[style]; found {
			localized["style"] = label
		}
	}
	if subTheme, ok := context["subTheme"].(string); ok && hasTopic {
		if label, found := labels.subThemes[topic][subTheme]; found {
			localized["subTheme"] = label
		}
	}
	if timeFrame, ok := context["timeFrame"].(string); ok {
		if label, found := labels.timeFrames[timeFrame]; found {
			localized["timeFrame"] = label
		}
	}
	return localized
}

// ContextFieldSchema は context の1フィールドのスキーマを言語別に返す。
//
// 配信経路のスキーマ（responseJSONSchemaJSON / contextGeneratableFieldsJSON）と
// 同じ定義をそのまま渡すためのもの。静的コーパスへ後から使い方を付ける
// （internal/corpususage）ときに、説明文を書き直さずここから引く。説明を
// 2か所に持つと、字数や言語の指定が配信ぶんとコーパスぶんでずれる。
//
// 未知の名前では nil を返す。
func ContextFieldSchema(name string, l lang.Lang) map[string]any {
	var raw any
	if props, ok := decodeJSON(responseJSONSchemaJSON)["properties"].(map[string]any); ok {
		if context, ok := props["context"].(map[string]any); ok {
			if fields, ok := context["properties"].(map[string]any); ok {
				raw = fields[name]
			}
		}
	}
	if raw == nil {
		raw = decodeJSON(contextGeneratableFieldsJSON)[name]
	}
	if raw == nil {
		return nil
	}
	field, ok := cloneAny(raw).(map[string]any)
	if !ok {
		return nil
	}
	if desc, found := schemaDescriptions[l][name]; found {
		field["description"] = desc
	} else if desc, found := contextDescriptions[l][name]; found {
		field["description"] = desc
	}
	return field
}

// BuildResponseSchema はリクエストごとのレスポンススキーマを組み立てる。
//
// askContextFields は LLM に生成させる context フィールド名。
// プロンプトで値を指定しなかったものだけを渡すこと。
// l が ja 以外のときは description のみ差し替える（構造は変えない）。
func BuildResponseSchema(askContextFields []string, l lang.Lang) map[string]any {
	schema := decodeJSON(responseJSONSchemaJSON)

	if descs, ok := schemaDescriptions[l]; ok {
		applyLangDescriptions(schema, descs)
	}

	if len(askContextFields) == 0 {
		return schema
	}

	generatable := decodeJSON(contextGeneratableFieldsJSON)
	context := schema["properties"].(map[string]any)["context"].(map[string]any)
	contextProps := context["properties"].(map[string]any)

	for _, name := range askContextFields {
		raw, ok := generatable[name]
		if !ok {
			continue
		}
		field := cloneAny(raw).(map[string]any)
		if desc, found := contextDescriptions[l][name]; found {
			field["description"] = desc
		}
		contextProps[name] = field
		context["required"] = append(context["required"].([]any), name)
	}
	return schema
}

// applyLangDescriptions は ja 以外の言語の description に差し替える（構造は変えない）。
func applyLangDescriptions(schema map[string]any, descs map[string]string) {
	props := schema["properties"].(map[string]any)

	setDesc := func(m map[string]any, key string) {
		m["description"] = descs[key]
	}

	setDesc(props["japanese_translation"].(map[string]any), "japanese_translation")
	setDesc(props["word_breakdown"].(map[string]any), "word_breakdown")
	setDesc(
		props["word_breakdown"].(map[string]any)["items"].(map[string]any)["properties"].(map[string]any)["meaning"].(map[string]any),
		"meaning",
	)
	setDesc(
		props["target_notes"].(map[string]any)["items"].(map[string]any)["properties"].(map[string]any)["note"].(map[string]any),
		"note",
	)
	contextProps := props["context"].(map[string]any)["properties"].(map[string]any)
	for _, name := range []string{"usage_scenarios", "cultural_notes"} {
		setDesc(contextProps[name].(map[string]any), name)
	}
}

// decodeJSON は生成済み JSON をデコードする。中身は生成時に検証済みなので
// ここで失敗することはない。
func decodeJSON(raw string) map[string]any {
	var out map[string]any
	if err := json.Unmarshal([]byte(raw), &out); err != nil {
		panic("constants_data.go の JSON が壊れている: " + err.Error())
	}
	return out
}

// cloneAny は JSON 由来の値を深くコピーする（Python の dict(field) 相当）。
func cloneAny(v any) any {
	switch x := v.(type) {
	case map[string]any:
		out := make(map[string]any, len(x))
		for k, val := range x {
			out[k] = cloneAny(val)
		}
		return out
	case []any:
		out := make([]any, len(x))
		for i, val := range x {
			out[i] = cloneAny(val)
		}
		return out
	}
	return v
}
