package sentence

import (
	"encoding/json"
	"os"
	"reflect"
	"testing"

	"github.com/mnbst/thai-memo/functions/go/internal/lang"
)

type constantsGolden struct {
	SchemaCases []struct {
		AskContextFields []string       `json:"ask_context_fields"`
		Lang             string         `json:"lang"`
		Schema           map[string]any `json:"schema"`
	} `json:"schema_cases"`
	ContextCases []struct {
		Context map[string]any `json:"context"`
		Lang    string         `json:"lang"`
		Result  map[string]any `json:"result"`
	} `json:"context_cases"`
}

func loadConstantsGolden(t *testing.T) *constantsGolden {
	t.Helper()
	raw, err := os.ReadFile(
		"../../../python/scripts/daily_golden/constants_golden.json")
	if err != nil {
		t.Fatalf("golden の読み込みに失敗: %v", err)
	}
	var golden constantsGolden
	if err := json.Unmarshal(raw, &golden); err != nil {
		t.Fatal(err)
	}
	return &golden
}

// TestBuildResponseSchemaGolden はレスポンススキーマの組み立てを
// Python 実装と突き合わせる。
//
// スキーマは LLM の出力形式そのものなので、description ひとつのずれでも
// 生成結果の言語が変わる。全フィールド組み合わせ × ja/en で比べる。
func TestBuildResponseSchemaGolden(t *testing.T) {
	golden := loadConstantsGolden(t)
	if len(golden.SchemaCases) == 0 {
		t.Fatal("golden が空")
	}

	for i, c := range golden.SchemaCases {
		got := roundTrip(t, BuildResponseSchema(c.AskContextFields, lang.Lang(c.Lang)))
		if !reflect.DeepEqual(got, c.Schema) {
			t.Errorf("case %d (fields=%v lang=%s):\n  Python = %s\n  Go     = %s",
				i, c.AskContextFields, c.Lang,
				mustJSON(c.Schema), mustJSON(got))
		}
	}
	t.Logf("%d ケース一致", len(golden.SchemaCases))
}

// TestBuildResponseSchemaDoesNotLeak は組み立てが元のスキーマを汚さないことを
// 確かめる。Python は ja かつ指定なしのとき RESPONSE_JSON_SCHEMA を
// そのまま返すため、うっかり書き換えると以降の全リクエストに漏れる。
func TestBuildResponseSchemaDoesNotLeak(t *testing.T) {
	before := mustJSON(BuildResponseSchema(nil, lang.JA))

	// en とフィールド追加を挟む
	BuildResponseSchema([]string{"topic", "style", "emotion"}, lang.EN)
	BuildResponseSchema([]string{"topic"}, lang.JA)

	if after := mustJSON(BuildResponseSchema(nil, lang.JA)); after != before {
		t.Errorf("素のスキーマが汚染されている\n  前 = %s\n  後 = %s", before, after)
	}
}

// TestLocalizeContextGolden は context の英語化を Python 実装と突き合わせる。
func TestLocalizeContextGolden(t *testing.T) {
	golden := loadConstantsGolden(t)
	if len(golden.ContextCases) == 0 {
		t.Fatal("golden が空")
	}

	var changed, unchanged int
	for i, c := range golden.ContextCases {
		got := LocalizeContext(c.Context, lang.Lang(c.Lang))

		if reflect.DeepEqual(got, c.Context) {
			unchanged++
		} else {
			changed++
		}

		if !reflect.DeepEqual(roundTripMaybeNil(t, got), c.Result) {
			t.Errorf("case %d (lang=%s):\n  入力   = %s\n  Python = %s\n  Go     = %s",
				i, c.Lang, mustJSON(c.Context), mustJSON(c.Result), mustJSON(got))
		}
	}

	t.Logf("%d ケース一致（差し替えあり %d / そのまま %d）",
		len(golden.ContextCases), changed, unchanged)
	if changed == 0 || unchanged == 0 {
		t.Error("差し替えの有無どちらかが踏まれていない。golden が退化している")
	}
}

// TestLocalizeContextIsIdempotent は英語化済みの context にもう一度かけても
// 壊れないことを確かめる（Python 側のドキュメントが冪等を約束している）。
func TestLocalizeContextIsIdempotent(t *testing.T) {
	golden := loadConstantsGolden(t)

	for i, c := range golden.ContextCases {
		if c.Lang != "en" || c.Context == nil {
			continue
		}
		once := LocalizeContext(c.Context, lang.EN)
		twice := LocalizeContext(once, lang.EN)
		if !reflect.DeepEqual(once, twice) {
			t.Errorf("case %d: 2回かけると変わる\n  1回 = %s\n  2回 = %s",
				i, mustJSON(once), mustJSON(twice))
		}
	}
}

func roundTrip(t *testing.T, v any) map[string]any {
	t.Helper()
	raw, err := json.Marshal(v)
	if err != nil {
		t.Fatal(err)
	}
	var out map[string]any
	if err := json.Unmarshal(raw, &out); err != nil {
		t.Fatal(err)
	}
	return out
}

func roundTripMaybeNil(t *testing.T, v map[string]any) map[string]any {
	t.Helper()
	if v == nil {
		return nil
	}
	return roundTrip(t, v)
}

func mustJSON(v any) string {
	raw, err := json.Marshal(v)
	if err != nil {
		return "<marshal error>"
	}
	return string(raw)
}
