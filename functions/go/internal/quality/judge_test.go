package quality

import (
	"context"
	"encoding/json"
	"errors"
	"strings"
	"testing"
	"time"
)

func sample(n int) []Candidate {
	out := make([]Candidate, n)
	for i := range out {
		out[i] = Candidate{
			UID:                 "u1",
			SentenceID:          string(rune('a' + i)),
			ThaiText:            "ผมกินข้าว",
			Pronunciation:       "phom kin khao",
			JapaneseTranslation: "ご飯を食べます",
			KeyWord:             "กิน",
		}
	}
	return out
}

// verdictsJSON は LLM のレスポンス相当を組む。
func verdictsJSON(t *testing.T, items ...map[string]any) map[string]any {
	t.Helper()
	raw, err := json.Marshal(map[string]any{"results": items})
	if err != nil {
		t.Fatal(err)
	}
	var out map[string]any
	if err := json.Unmarshal(raw, &out); err != nil {
		t.Fatal(err)
	}
	return out
}

func TestBuildUserPromptIncludesEveryIndex(t *testing.T) {
	p := BuildUserPrompt(sample(3))
	for _, want := range []string{"[0]", "[1]", "[2]", "<sentences>", "</sentences>", "index 0〜2 の3件", "translation: ご飯を食べます"} {
		if !strings.Contains(p, want) {
			t.Errorf("プロンプトに %q が無い:\n%s", want, p)
		}
	}
	if !strings.Contains(p, "key_word: กิน") {
		t.Errorf("key_word を渡していない:\n%s", p)
	}
	// 発音は判定に使わない（読ませる情報を増やすほど注意が散る）。
	if strings.Contains(p, "pronunciation") {
		t.Errorf("発音まで渡している:\n%s", p)
	}
	// 空の項目は行ごと出さない（欠損を「空文字」として読ませない）。
	c := sample(1)
	c[0].KeyWord = ""
	if strings.Contains(BuildUserPrompt(c), "key_word:") {
		t.Error("空の key_word の行が残っている")
	}
}

func TestParseVerdictsKeepsOnlyReportable(t *testing.T) {
	raw := verdictsJSON(t,
		// 正常な指摘。
		map[string]any{"index": 0, "natural": false, "reason": "ดูงาน は視察の意"},
		// natural は記録しない。
		map[string]any{"index": 1, "natural": true, "reason": ""},
		// 理由が無い指摘は台帳の役に立たない。
		map[string]any{"index": 2, "natural": false, "reason": "   "},
		// 範囲外の index。
		map[string]any{"index": 9, "natural": false, "reason": "x"},
		// index 0 の重複 → 先勝ちで捨てる。
		map[string]any{"index": 0, "natural": false, "reason": "後から来た"},
	)

	got := ParseVerdicts(raw, 4)
	if len(got) != 1 {
		t.Fatalf("報告対象は1件のはず: %+v", got)
	}
	if got[0].Index != 0 || got[0].Reason != "ดูงาน は視察の意" {
		t.Errorf("先勝ちになっていない: %+v", got[0])
	}
}

func TestParseVerdictsBrokenResponse(t *testing.T) {
	if got := ParseVerdicts(map[string]any{}, 3); got != nil {
		t.Errorf("results 欠損は nil: %+v", got)
	}
	if got := ParseVerdicts(map[string]any{"results": "文字列"}, 3); got != nil {
		t.Errorf("型違いは nil: %+v", got)
	}
}

// stubGen は決められたレスポンスを返す。
type stubGen struct {
	res    map[string]any
	err    error
	system string
	user   string
	schema map[string]any
}

func (g *stubGen) GenerateSentence(
	_ context.Context, systemPrompt, userPrompt string,
	_ bool, _ string, schema map[string]any,
) (map[string]any, error) {
	g.system, g.user, g.schema = systemPrompt, userPrompt, schema
	return g.res, g.err
}

func TestJudgeBatchMapsIndexToCandidate(t *testing.T) {
	batch := sample(3)
	batch[2].SentenceID = "target"

	gen := &stubGen{res: verdictsJSON(t, map[string]any{
		"index": 2, "natural": false, "reason": "否定辞の位置",
	})}

	flagged, verdicts, err := (&Judge{Gen: gen, Model: "m"}).JudgeBatch(context.Background(), batch)
	if err != nil {
		t.Fatal(err)
	}
	if len(flagged) != 1 || flagged[0].SentenceID != "target" {
		t.Fatalf("index と Candidate の対応がずれている: %+v", flagged)
	}
	if verdicts[0].Reason != "否定辞の位置" {
		t.Errorf("verdict がずれている: %+v", verdicts[0])
	}
	if gen.system != SystemPrompt {
		t.Error("システムプロンプトを渡していない")
	}
	if gen.schema == nil {
		t.Error("スキーマを渡していない")
	}
}

func TestJudgeBatchEmptyAndError(t *testing.T) {
	j := &Judge{Gen: &stubGen{err: errors.New("boom")}, Model: "m"}
	if _, _, err := j.JudgeBatch(context.Background(), nil); err != nil {
		t.Errorf("空の束は呼び出さずに終わる: %v", err)
	}
	if _, _, err := j.JudgeBatch(context.Background(), sample(1)); err == nil {
		t.Error("LLM のエラーを返していない")
	}
}

func TestFlagIDIsStable(t *testing.T) {
	c := Candidate{UID: "u1", SentenceID: "s1"}
	if FlagID(c) != "u1_s1" {
		t.Errorf("doc ID が固定でない: %s", FlagID(c))
	}
}

func TestFlagDocCarriesSentenceBody(t *testing.T) {
	created := time.Date(2026, 9, 1, 0, 0, 0, 0, time.UTC)
	judged := created.Add(24 * time.Hour)
	c := Candidate{
		UID: "u1", SentenceID: "s1",
		ThaiText: "ผมกินข้าว", JapaneseTranslation: "ご飯を食べます",
		KeyWord: "กิน", Topic: "食べ物", Emotion: "neutral",
		GenerationTier: "premium", CreatedAt: created,
	}
	v := Verdict{Reason: "ดูงาน は視察の意"}

	doc := FlagDoc(c, v, "judge-model", judged)

	// 30日後に例文が消えても台帳が読めること＝本文の複製が要る。
	for k, want := range map[string]any{
		"thai_text":            "ผมกินข้าว",
		"japanese_translation": "ご飯を食べます",
		"key_word":             "กิน",
		"topic":                "食べ物",
		"uid":                  "u1",
		"sentence_id":          "s1",
		"reason":               "ดูงาน は視察の意",
		"judge_model":          "judge-model",
		"created_at":           created,
		"judged_at":            judged,
	} {
		if doc[k] != want {
			t.Errorf("%s = %v, want %v", k, doc[k], want)
		}
	}
}

// スキーマの必須キーと Verdict のフィールドがずれると、LLM が返した内容を
// 読み落とす。
func TestSchemaRequiresVerdictFields(t *testing.T) {
	props := ResponseSchema()["properties"].(map[string]any)
	items := props["results"].(map[string]any)["items"].(map[string]any)
	required := items["required"].([]any)

	want := map[string]bool{"index": true, "natural": true, "reason": true}
	if len(required) != len(want) {
		t.Fatalf("required の件数が違う: %v", required)
	}
	for _, k := range required {
		if !want[k.(string)] {
			t.Errorf("未知の required: %v", k)
		}
	}
}
