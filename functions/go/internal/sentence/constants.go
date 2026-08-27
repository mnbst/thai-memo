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

// 新規ユーザー初期クォータ。
//
// users/{uid} doc が未作成のまま生成された場合の初期値。
// 主経路は onUserCreate トリガー（functions/javascript/src/constants/quota.ts）。
// doc 欠損時のフォールバックとしてここでも初期化するため、
// **必ず quota.ts / internal/quota と値を一致させること。**
const (
	FreeDailySentences    = 5
	FreeDailyQuizzes      = 5
	PremiumDailySentences = 20
	PremiumDailyQuizzes   = 5
	PremiumTrialDays      = 2

	// PremiumTrialSentences は premium_trial_remaining の付与値（凍結した互換値）。
	// サーバは読まないし減らさない。
	PremiumTrialSentences = PremiumDailySentences * PremiumTrialDays
)

// topicHeadsEN は括弧の例示を落とした短縮形（「食べ物」「旅行」）からの引き当て表。
//
// サーバーがテーマを決めなかった回は LLM が選んで書くので短縮形が返る。
// 完全一致だけだとそこが日本語のまま残る。
var topicHeadsEN = func() map[string]string {
	out := make(map[string]string, len(topicLabelsEN))
	for topic, label := range topicLabelsEN {
		out[topicHead(topic)] = label
	}
	return out
}()

// topicHead は Python の topic.split("（")[0]。
func topicHead(topic string) string {
	if i := strings.Index(topic, "（"); i >= 0 {
		return topic[:i]
	}
	return topic
}

func localizeTopic(topic string) string {
	if label, ok := topicLabelsEN[topic]; ok {
		return label
	}
	if label, ok := topicHeadsEN[topicHead(topic)]; ok {
		return label
	}
	return topic
}

// LocalizeContext は context の軸ラベルを訳文の言語に合わせる。
//
// ja はそのまま返す。en は既知の日本語ラベルだけ差し替え、未知の値
// （LLM が自由記述する emotion・usage_scenarios や、既に英語のもの）は触らない。
// 冪等なので、英語化済みの例文にもう一度かけても壊れない。
func LocalizeContext(context map[string]any, l lang.Lang) map[string]any {
	if context == nil || l != lang.EN {
		return context
	}

	localized := make(map[string]any, len(context))
	for k, v := range context {
		localized[k] = v
	}

	topic, hasTopic := context["topic"].(string)
	if hasTopic {
		localized["topic"] = localizeTopic(topic)
	}
	if style, ok := context["style"].(string); ok {
		if label, found := styleLabelsEN[style]; found {
			localized["style"] = label
		}
	}
	if subTheme, ok := context["subTheme"].(string); ok && hasTopic {
		if label, found := subThemeLabelsEN[topic][subTheme]; found {
			localized["subTheme"] = label
		}
	}
	if timeFrame, ok := context["timeFrame"].(string); ok {
		if label, found := timeFrameLabelsEN[timeFrame]; found {
			localized["timeFrame"] = label
		}
	}
	return localized
}

// BuildResponseSchema はリクエストごとのレスポンススキーマを組み立てる。
//
// askContextFields は LLM に生成させる context フィールド名。
// プロンプトで値を指定しなかったものだけを渡すこと。
// l が en のときは description のみ差し替える（構造は変えない）。
func BuildResponseSchema(askContextFields []string, l lang.Lang) map[string]any {
	schema := decodeJSON(responseJSONSchemaJSON)

	if l != lang.Default {
		applyLangDescriptions(schema)
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
		if l != lang.Default {
			if desc, found := contextDescriptionsEN[name]; found {
				field["description"] = desc
			}
		}
		contextProps[name] = field
		context["required"] = append(context["required"].([]any), name)
	}
	return schema
}

// applyLangDescriptions は en 用に description を差し替える（構造は変えない）。
func applyLangDescriptions(schema map[string]any) {
	props := schema["properties"].(map[string]any)

	setDesc := func(m map[string]any, key string) {
		m["description"] = schemaDescriptionsEN[key]
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
