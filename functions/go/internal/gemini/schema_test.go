package gemini

import (
	"reflect"
	"testing"

	"github.com/mnbst/thai-memo/functions/go/internal/lang"
)

func TestMeaningResponseSchemaRequestsOnlyWordExplanation(t *testing.T) {
	schema := responseSchema(lang.JA, true, false)
	properties, ok := schema["properties"].(map[string]any)
	if !ok {
		t.Fatalf("properties = %#v", schema["properties"])
	}
	if got := reflect.ValueOf(properties).MapKeys(); len(got) != 1 {
		t.Fatalf("meaning properties = %#v", properties)
	}
	if _, ok := properties["explanation"]; !ok {
		t.Fatalf("meaning properties = %#v", properties)
	}
	if want := []any{"explanation"}; !reflect.DeepEqual(schema["required"], want) {
		t.Fatalf("required = %#v, want %#v", schema["required"], want)
	}
}

// ダミー確定時は dummies を返させない（渡した語を書き換えられないように）。
func TestFixedDummyResponseSchemaDropsDummies(t *testing.T) {
	schema := responseSchema(lang.JA, false, true)
	properties, ok := schema["properties"].(map[string]any)
	if !ok {
		t.Fatalf("properties = %#v", schema["properties"])
	}
	if _, exists := properties["dummies"]; exists {
		t.Errorf("dummies が残っている: %#v", properties)
	}
	if want := []any{"explanation", "dummy_reasons"}; !reflect.DeepEqual(schema["required"], want) {
		t.Errorf("required = %#v, want %#v", schema["required"], want)
	}

	// 従来の穴埋め（ダミーもモデルが作る）は据え置き。
	old := responseSchema(lang.JA, false, false)
	oldProps := old["properties"].(map[string]any)
	if _, exists := oldProps["dummies"]; !exists {
		t.Errorf("従来のスキーマから dummies が消えている: %#v", oldProps)
	}
}
