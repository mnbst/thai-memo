package function

import (
	"reflect"
	"testing"

	"github.com/mnbst/thai-memo/functions/go/internal/uvm"
)

// セッション doc の往復。選択肢を残さないと、応答が届かなかった段を
// もう一度返せない（クライアントは何を出せばいいか分からなくなる）。
func TestStoredQuestionsRoundTrip(t *testing.T) {
	in := []uvm.TestQuestion{
		{Word: "กิน", Rank: 12, Choices: []string{"食べる", "行く", "見る", "寝る"}, AnswerIndex: 0},
		{Word: "ไป", Rank: 34, Choices: []string{"食べる", "行く", "見る", "寝る"}, AnswerIndex: 1},
	}

	got := storedQuestions(questionsToStore(in))
	if len(got) != len(in) {
		t.Fatalf("件数 = %d, want %d", len(got), len(in))
	}
	for i, q := range got {
		if q.word != in[i].Word || q.rank != in[i].Rank || q.answer != in[i].AnswerIndex {
			t.Errorf("[%d] = %+v, want %+v", i, q, in[i])
		}
		if !reflect.DeepEqual(q.choices, in[i].Choices) {
			t.Errorf("[%d] 選択肢 = %v, want %v", i, q.choices, in[i].Choices)
		}
	}
}

// 保存済みの出題をそのまま返せる（＝同じ段の再送）。正解は載せない。
func TestStoredStageResponseHidesAnswer(t *testing.T) {
	stored := storedQuestions(questionsToStore([]uvm.TestQuestion{
		{Word: "กิน", Rank: 12, Choices: []string{"食べる", "行く", "見る", "寝る"}, AnswerIndex: 2},
	}))

	res := storedStageResponse(1, stored)
	if res["done"] != false || res["stage"] != 1 {
		t.Errorf("done/stage = %v/%v, want false/1", res["done"], res["stage"])
	}
	out, ok := res["questions"].([]vocabTestQuestionOut)
	if !ok || len(out) != 1 {
		t.Fatalf("questions = %#v", res["questions"])
	}
	if out[0].Word != "กิน" || len(out[0].Choices) != 4 {
		t.Errorf("出題 = %+v", out[0])
	}
	// vocabTestQuestionOut に正解の欄が無いこと自体が保証。増やしたら気づけるよう
	// フィールド数を見ておく。
	if n := reflect.TypeOf(vocabTestQuestionOut{}).NumField(); n != 2 {
		t.Errorf("vocabTestQuestionOut のフィールド数 = %d, want 2（正解を足していないか）", n)
	}
}
