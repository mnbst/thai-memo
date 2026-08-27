package gemini

import (
	"encoding/json"
	"os"
	"reflect"
	"strings"
	"testing"

	"github.com/mnbst/thai-memo/functions/go/internal/lang"
	"github.com/mnbst/thai-memo/functions/go/internal/quizgen"
)

type geminiGolden struct {
	GeminiRequests []struct {
		Lang      string                     `json:"lang"`
		Sentences []quizgen.QuizSentenceSeed `json:"sentences"`
		Request   struct {
			URL  string         `json:"url"`
			Body map[string]any `json:"body"`
		} `json:"request"`
	} `json:"gemini_requests"`
}

// TestBuildRequestBodyGolden は Gemini へ送るリクエスト本文が JS 版と
// 同じ内容になることを確かめる。
//
// プロンプト・スキーマ・生成パラメータのどれがずれても出力の質が変わる。
// JSON のキー順は Go と JS で違う（Go の map は整列される）ので、
// バイト比較ではなく構造で比べる。
func TestBuildRequestBodyGolden(t *testing.T) {
	raw, err := os.ReadFile("../../../javascript/scripts/quiz_golden.json")
	if err != nil {
		t.Fatalf("golden の読み込みに失敗: %v", err)
	}
	var golden geminiGolden
	if err := json.Unmarshal(raw, &golden); err != nil {
		t.Fatal(err)
	}
	if len(golden.GeminiRequests) == 0 {
		t.Fatal("golden が空")
	}

	seenLang := map[string]int{}
	for i, c := range golden.GeminiRequests {
		seenLang[c.Lang]++

		got := roundTrip(t, BuildRequestBody(c.Sentences, lang.Lang(c.Lang)))
		want := c.Request.Body

		if !reflect.DeepEqual(got, want) {
			// どこが違うか分かるように、まず大枠を比べる
			for _, key := range []string{"systemInstruction", "contents", "generationConfig"} {
				if !reflect.DeepEqual(got[key], want[key]) {
					t.Errorf("case %d (%s): %s が違う\n  JS = %s\n  Go = %s",
						i, c.Lang, key, mustJSON(want[key]), mustJSON(got[key]))
				}
			}
		}
	}

	// URL の組み立て（モデル名とキーの載せ方）も確認する
	sample := golden.GeminiRequests[0].Request.URL
	if !strings.Contains(sample, Model) {
		t.Errorf("golden の URL のモデル名が Go 側の Model (%s) と違う: %s", Model, sample)
	}

	t.Logf("%d ケース一致 %v", len(golden.GeminiRequests), seenLang)
	if seenLang["ja"] == 0 || seenLang["en"] == 0 {
		t.Error("ja と en の両方が無い。golden が退化している")
	}
}

// roundTrip は Go の値を JSON 経由で any に均す（数値を float64 に揃える）。
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

func mustJSON(v any) string {
	raw, err := json.MarshalIndent(v, "", " ")
	if err != nil {
		return "<marshal error>"
	}
	return string(raw)
}
