package gemini

import (
	"reflect"
	"testing"

	"github.com/mnbst/thai-memo/functions/go/internal/lang"
)

func TestMeaningResponseSchemaRequestsOnlyWordExplanation(t *testing.T) {
	schema := responseSchema(lang.JA, true)
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
