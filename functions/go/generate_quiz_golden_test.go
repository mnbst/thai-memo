package function

import (
	"context"
	"encoding/json"
	"os"
	"reflect"
	"testing"

	"github.com/mnbst/thai-memo/functions/go/internal/callable"
	"github.com/mnbst/thai-memo/functions/go/internal/lang"
	"github.com/mnbst/thai-memo/functions/go/internal/quizgen"
	"github.com/mnbst/thai-memo/functions/go/internal/uvm"
)

type learningQuizGoldenCase struct {
	Name             string                            `json:"name"`
	Sentence         map[string]any                    `json:"sentence"`
	Lang             any                               `json:"lang"`
	StubbedQuestions [][]quizgen.GeneratedQuizQuestion `json:"stubbed_questions"`
	OK               bool                              `json:"ok"`
	ErrorCode        *string                           `json:"error_code"`
	ErrorMessage     *string                           `json:"error_message"`
	Result           map[string]any                    `json:"result"`
}

// stubQuizService は golden が指定した問題を呼び出し順に返す。
type stubQuizService struct {
	responses [][]quizgen.GeneratedQuizQuestion
	calls     int
}

func (s *stubQuizService) GenerateQuizQuestions(
	_ context.Context, _ []quizgen.QuizSentenceSeed,
) []quizgen.GeneratedQuizQuestion {
	i := min(s.calls, len(s.responses)-1)
	s.calls++
	if i < 0 {
		return nil
	}
	return s.responses[i]
}

// TestGenerateLearningQuizGolden は JS 実装の generateLearningQuiz と
// 同じ入力に対して同じ結果を返すことを確かめる。
//
// golden は本物の generateQuiz.ts に Firestore と Gemini をスタブして通したもの
// （scripts/genLearningQuizGolden.ts）。sentence_detail の組み立て、
// key_word の突き合わせと再試行、失敗時のエラーコードと文言まで比べる。
func TestGenerateLearningQuizGolden(t *testing.T) {
	raw, err := os.ReadFile("testdata/javascript/learning_quiz_golden.json")
	if err != nil {
		t.Fatalf("golden の読み込みに失敗: %v", err)
	}
	var cases []learningQuizGoldenCase
	if err := json.Unmarshal(raw, &cases); err != nil {
		t.Fatal(err)
	}
	if len(cases) == 0 {
		t.Fatal("golden が空")
	}

	var ok, ng int
	for _, c := range cases {
		t.Run(c.Name, func(t *testing.T) {
			stub := &stubQuizService{responses: c.StubbedQuestions}
			original := quizServiceFactory
			quizServiceFactory = func(
				_ context.Context, _ string, _ bool, _ lang.Lang,
			) (quizService, error) {
				return stub, nil
			}
			t.Cleanup(func() { quizServiceFactory = original })

			// 入力の妥当性判定と組み立てだけを見たいので、Firestore を引く前に
			// 落ちる経路（buildLearningQuizSource）と、通った後の組み立てを
			// それぞれ確かめる。
			source, sourceOK := buildLearningQuizSource(c.Sentence)
			ready := sourceOK && quizgen.IsSeedReady(source.Seed)

			if !c.OK && c.ErrorCode != nil && *c.ErrorCode == "invalid-argument" {
				ng++
				if ready {
					t.Fatalf("JS は %s で弾いたのに Go は通した", *c.ErrorMessage)
				}
				// 文言もクライアントに出るので合わせる
				_, err := generateLearningQuiz(context.Background(),
					learningQuizRequest(c.Sentence, c.Lang))
				assertCallableError(t, err, callable.InvalidArgument, *c.ErrorMessage)
				return
			}

			if !ready {
				t.Fatalf("JS は通したのに Go は入力を弾いた: %+v", c.Sentence)
			}

			questions := generateQuestionsFromSources(
				context.Background(), stub, []quizSeedSource{source})

			if !c.OK {
				ng++
				if len(questions) != 0 {
					t.Fatalf("JS は失敗した（%s）のに Go は %d 問返した",
						*c.ErrorMessage, len(questions))
				}
				return
			}

			ok++
			if len(questions) == 0 {
				t.Fatal("JS は成功したのに Go は0問")
			}

			want := c.Result["questions"].([]any)
			if len(want) != len(questions) {
				t.Fatalf("問題数: JS=%d Go=%d", len(want), len(questions))
			}
			for i := range want {
				gotJSON := roundTripAny(t, questions[i])
				if !reflect.DeepEqual(gotJSON, want[i]) {
					t.Errorf("questions[%d]\n  JS = %s\n  Go = %s",
						i, mustJSONIndent(want[i]), mustJSONIndent(gotJSON))
				}
			}
		})
	}

	t.Logf("%d ケース一致（成功 %d / 失敗 %d）", len(cases), ok, ng)
	if ok == 0 || ng == 0 {
		t.Error("成功ケースか失敗ケースのどちらかが無い。golden が退化している")
	}
}

func learningQuizRequest(sentence map[string]any, l any) *callable.Request {
	data := map[string]any{"sentence": sentence}
	if l != nil {
		data["lang"] = l
	}
	raw, _ := json.Marshal(data)
	req := authedRequest(string(raw))
	return req
}

func roundTripAny(t *testing.T, v any) any {
	t.Helper()
	raw, err := json.Marshal(v)
	if err != nil {
		t.Fatal(err)
	}
	var out any
	if err := json.Unmarshal(raw, &out); err != nil {
		t.Fatal(err)
	}
	return out
}

func mustJSONIndent(v any) string {
	raw, err := json.MarshalIndent(v, "", " ")
	if err != nil {
		return "<marshal error>"
	}
	return string(raw)
}

// TestVocabFloorFilter は境界より下の key_word を出題から外すことを確かめる。
func TestVocabFloorFilter(t *testing.T) {
	freqRank := uvm.FreqRank{"low": 40, "atFloor": 100, "high": 200}

	if f := vocabFloorFilter(freqRank, 0); f != nil {
		t.Error("境界 0 ではフィルタを作らない")
	}

	f := vocabFloorFilter(freqRank, 100)
	for _, c := range []struct {
		word string
		want bool
	}{
		{"low", false},
		{"atFloor", true},
		{"high", true},
		{"unknown", true}, // freq_rank 未収録は判定できないので残す
	} {
		if got := f.allows(c.word); got != c.want {
			t.Errorf("allows(%q) = %v, want %v", c.word, got, c.want)
		}
	}

	var nilFilter keyWordFilter
	if !nilFilter.allows("low") {
		t.Error("nil フィルタは全部通す")
	}
}
