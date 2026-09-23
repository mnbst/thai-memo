package function

import (
	"bufio"
	"context"
	"encoding/json"
	"os"
	"strconv"
	"testing"

	"github.com/mnbst/thai-memo/functions/go/internal/gemini"
	"github.com/mnbst/thai-memo/functions/go/internal/lang"
	"github.com/mnbst/thai-memo/functions/go/internal/quizgen"
	"github.com/mnbst/thai-memo/functions/go/internal/secrets"
)

// 韓国語の解説が出た例文（2026-09、prod の quiz_questions から削除済み）。
// 作り直しが日本語で出るか、ここで直接確かめる。
var driftedQuestions = []struct{ thai, keyWord string }{
	{"นี่คือเวลาคุยของเรา", "นี่"},
	// 静的コーパスではなく LLM 生成の例文。語の分解は手元に無いので、
	// 本文と正解だけ渡して空欄を作らせる。
	{"จังหวะหัวใจพี่เนี่ย ผมว่ามันฟ้องความรู้สึกที่พี่ต้องหาคำตอบเอง", "ต้องหา"},
}

// TestQuizLanguageLive は実 Gemini で解説とダミー理由の言語を確かめる。
// キャッシュは噛ませない（毎回モデルに作らせる）。
//
//	GOOGLE_CLOUD_PROJECT=thai-memo-prod QUIZ_LANGUAGE_LIVE=1 \
//	  go test ./ -run TestQuizLanguageLive -v
//
// 繰り返し回数は QUIZ_LANGUAGE_RUNS（既定3）。ドリフトは実測 0.6% 程度なので、
// 「出ないこと」の確認にはならない。見ているのは、作り直した中身が日本語で
// 読めるか（と、書き直しの経路が通ること）。
func TestQuizLanguageLive(t *testing.T) {
	if os.Getenv("QUIZ_LANGUAGE_LIVE") == "" {
		t.Skip("QUIZ_LANGUAGE_LIVE=1 で実行する")
	}
	ctx := context.Background()
	key, err := secrets.Get(ctx, "gemini-api-key")
	if err != nil {
		t.Skipf("gemini-api-key が要る: %v", err)
	}
	runs := 3
	if v := os.Getenv("QUIZ_LANGUAGE_RUNS"); v != "" {
		if n, err := strconv.Atoi(v); err == nil && n > 0 {
			runs = n
		}
	}

	service := &gemini.QuizService{
		APIKey: key, UID: "language-live-test", Tier: "premium", Lang: lang.JA,
	}
	for _, target := range driftedQuestions {
		seed := seedFor(t, target.thai, target.keyWord)
		for run := range runs {
			t.Run(target.keyWord+"/"+strconv.Itoa(run+1), func(t *testing.T) {
				questions := service.GenerateQuizQuestions(
					ctx, []quizgen.QuizSentenceSeed{seed})
				if len(questions) != 1 {
					t.Fatal("問題が作れない")
				}
				q := questions[0]
				t.Logf("解説: %s", q.Explanation)
				for _, reason := range q.DummyReasons {
					t.Logf("理由: %s", reason)
				}
				if lang.IsWrongLanguage(q.Explanation, lang.JA) {
					t.Errorf("解説が日本語でない: %q", q.Explanation)
				}
				for _, reason := range q.DummyReasons {
					if lang.IsWrongLanguage(reason, lang.JA) {
						t.Errorf("理由が日本語でない: %q", reason)
					}
				}
			})
		}
	}
}

// seedFor は出題の種を組む。静的コーパスに本文があればその行から
// （配信経路 toQuizSeedSourceFromSelected と同じ項目を埋める）、
// 無ければ本文と正解だけの最小構成で返す。
func seedFor(t *testing.T, thaiText, keyWord string) quizgen.QuizSentenceSeed {
	t.Helper()
	f, err := os.Open("../../scripts/corpus/corpus.jsonl")
	if err != nil {
		t.Skipf("コーパスが無い: %v", err)
	}
	defer f.Close()

	sc := bufio.NewScanner(f)
	sc.Buffer(make([]byte, 1<<22), 1<<22)
	for sc.Scan() {
		var row struct {
			ThaiText      string `json:"thai_text"`
			TargetWord    string `json:"target_word"`
			Pronunciation string `json:"pronunciation"`
			JA            string `json:"ja"`
			Words         []struct {
				Word          string `json:"word"`
				JA            string `json:"ja"`
				Pronunciation string `json:"pronunciation"`
			} `json:"words"`
		}
		if json.Unmarshal(sc.Bytes(), &row) != nil || row.ThaiText != thaiText {
			continue
		}
		words := make([]string, len(row.Words))
		targetPron, targetMeaning := "", ""
		for i, w := range row.Words {
			words[i] = w.Word
			if w.Word == row.TargetWord {
				targetPron, targetMeaning = w.Pronunciation, w.JA
			}
		}
		return quizgen.QuizSentenceSeed{
			QuizFormat:           quizgen.FormatClozeChoice,
			ThaiText:             row.ThaiText,
			Words:                words,
			Pronunciation:        row.Pronunciation,
			JapaneseTranslation:  row.JA,
			KeyWord:              row.TargetWord,
			KeyWordPronunciation: targetPron,
			KeyWordMeaning:       targetMeaning,
		}
	}
	t.Logf("コーパスに無いので本文と正解だけで作る: %s", thaiText)
	return quizgen.QuizSentenceSeed{
		QuizFormat: quizgen.FormatClozeChoice,
		ThaiText:   thaiText,
		KeyWord:    keyWord,
	}
}
