package quizgen

import (
	"testing"

	"github.com/mnbst/thai-memo/functions/go/internal/lang"
)

func TestDriftedFields(t *testing.T) {
	draft := Draft{
		Explanation: "주어 자리에 오는 지시 대명사입니다",
		DummyReasons: []string{
			"แกง（kɛɛng / カレー）：動詞の位置に名詞が入り不自然",
			"เบื่อ（bʉ̀a / 飽きる）：目的語に動詞が入り不自然",
			"เสื้อ（sʉ̂a / 服）：移動動詞の目的語に衣類名詞が入り不自然",
		},
		// ダミー自体はタイ語なので判定しない。
		Dummies: []string{"แกง", "เบื่อ", "เสื้อ"},
	}
	if got := DriftedFields(draft, lang.JA); len(got) != 1 || got[0] != FieldExplanation {
		t.Fatalf("DriftedFields = %v, want [%s]", got, FieldExplanation)
	}

	draft.DummyReasons[1] = "เบื่อ（bʉ̀a / 지루하다）：동사 자리에 들어갈 수 없습니다"
	got := DriftedFields(draft, lang.JA)
	if len(got) != 2 || got[0] != FieldExplanation || got[1] != FieldDummyReasons {
		t.Fatalf("DriftedFields = %v, want [%s %s]", got, FieldExplanation, FieldDummyReasons)
	}

	draft.Explanation = "主語の位置に置く指示代名詞"
	draft.DummyReasons[1] = "เบื่อ（bʉ̀a / 飽きる）：目的語に動詞が入り不自然"
	if got := DriftedFields(draft, lang.JA); len(got) != 0 {
		t.Fatalf("DriftedFields = %v, want empty", got)
	}
}
