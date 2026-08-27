package function

import (
	"context"
	"log"
	"math/rand"
	"time"

	"cloud.google.com/go/firestore"

	"github.com/mnbst/thai-memo/functions/go/internal/callable"
	"github.com/mnbst/thai-memo/functions/go/internal/fbapp"
	"github.com/mnbst/thai-memo/functions/go/internal/gemini"
	"github.com/mnbst/thai-memo/functions/go/internal/lang"
	"github.com/mnbst/thai-memo/functions/go/internal/premium"
	"github.com/mnbst/thai-memo/functions/go/internal/quizgen"
	"github.com/mnbst/thai-memo/functions/go/internal/secrets"
)

// generateQuiz / generateLearningQuiz は
// functions/javascript/src/generateQuiz.ts の移植。
//
// クイズ生成に回数上限は設けない。出題できるのは SRS で復習期日を迎えた
// 自分の例文だけなので、例文が無ければ no_user_sentences で空を返す。
// 実質的な上限は例文側のクォータ（internal/quota）が決めている。

const (
	// maxQuestions は1回のクイズ生成で出題する最大問題数。
	maxQuestions = 5

	// maxSrsSentences は SRS から選ぶ最大例文数。
	maxSrsSentences = 2

	// uvmFillerPageSize は補充用に一度に確認する UVM 語数。
	uvmFillerPageSize = 50

	// keywordInQueryLimit は Firestore の in query に渡すキーワード数。
	keywordInQueryLimit = 10

	dayDuration = 24 * time.Hour
	jstOffset   = 9 * time.Hour
)

// srsDays は SRS（間隔反復）の復習間隔（日数）。
//
// 学習した例文を「1日後 → 3日後 → 7日後 → 14日後 → 30日後」に再出題することで
// 忘却曲線に沿った効率的な定着を狙う。
var srsDays = []int{1, 3, 7, 14, 30}

// shuffleN は並べ替え。テストで固定するために差し替えられるようにしている。
var shuffleN = func(n int, swap func(i, j int)) {
	rand.Shuffle(n, swap)
}

// quizSeedSource は1問ぶんの生成元。
type quizSeedSource struct {
	Seed                  quizgen.QuizSentenceSeed
	SentenceID            string
	SrsInterval           int
	JapaneseTranslation   string
	SentencePronunciation string
	SentenceDetail        map[string]any
}

// quizQuestion はクライアントへ返す1問。
type quizQuestion struct {
	SentenceID                 string         `json:"sentence_id"`
	ThaiText                   string         `json:"thai_text"`
	BlankText                  string         `json:"blank_text"`
	CorrectAnswer              string         `json:"correct_answer"`
	CorrectAnswerMeaning       string         `json:"correct_answer_meaning"`
	Choices                    []string       `json:"choices"`
	ChoicePronunciations       []string       `json:"choice_pronunciations"`
	Pronunciation              string         `json:"pronunciation"`
	Explanation                string         `json:"explanation"`
	SrsInterval                int            `json:"srs_interval"`
	JapaneseTranslation        string         `json:"japanese_translation"`
	SentencePronunciation      string         `json:"sentence_pronunciation"`
	BlankSentencePronunciation string         `json:"blank_sentence_pronunciation"`
	DummyReasons               []string       `json:"dummy_reasons"`
	SentenceDetail             map[string]any `json:"sentence_detail,omitempty"`
}

// ---------------------------------------------------------------------------
// エントリポイント
// ---------------------------------------------------------------------------

func generateQuiz(ctx context.Context, req *callable.Request) (any, error) {
	uid, err := req.RequireAuth()
	if err != nil {
		return nil, err
	}

	var in struct {
		Lang any `json:"lang"`
	}
	_ = req.Bind(&in)
	// 解説の言語。旧クライアントは送ってこないので ja に落ちる。
	l := lang.Resolve(in.Lang)

	db, err := fbapp.Firestore(ctx)
	if err != nil {
		return nil, err
	}

	userRef := db.Collection("users").Doc(uid)
	userData := userDocData(ctx, userRef)

	// トライアル中も premium と同じ品質で出す。
	service, err := newQuizService(ctx, uid, premium.IsEffectivePremium(userData, time.Now()), l)
	if err != nil {
		return nil, callable.Errorf(callable.Internal, "クイズの生成に失敗しました")
	}

	// SRS ベースでリアルタイムに復習対象例文を選出
	selected, err := selectSentencesBySRS(ctx, db, uid, nowJST())
	if err != nil {
		log.Printf("Failed to generate quiz: %v", err)
		return nil, callable.Errorf(callable.Internal, "クイズの生成に失敗しました")
	}

	// ユーザー例文がない場合 → クライアントに通知
	if len(selected) == 0 {
		return map[string]any{
			"questions":         []quizQuestion{},
			"no_user_sentences": true,
		}, nil
	}

	questions := generateQuestionsFromSources(ctx, service, buildQuizSources(selected))
	if len(questions) == 0 {
		return nil, callable.Errorf(callable.Internal, "クイズの生成に失敗しました")
	}

	if err := updateQuizStats(ctx, userRef, len(questions)); err != nil {
		log.Printf("Failed to generate quiz: %v", err)
		return nil, callable.Errorf(callable.Internal, "クイズの生成に失敗しました")
	}

	if len(questions) > maxQuestions {
		questions = questions[:maxQuestions]
	}
	return map[string]any{"questions": questions}, nil
}

func generateLearningQuiz(ctx context.Context, req *callable.Request) (any, error) {
	uid, err := req.RequireAuth()
	if err != nil {
		return nil, err
	}

	var in struct {
		Lang     any            `json:"lang"`
		Sentence map[string]any `json:"sentence"`
	}
	_ = req.Bind(&in)
	l := lang.Resolve(in.Lang)

	source, ok := buildLearningQuizSource(in.Sentence)
	if !ok || !quizgen.IsSeedReady(source.Seed) {
		return nil, callable.Errorf(callable.InvalidArgument,
			"クイズに使える例文データがありません")
	}

	db, err := fbapp.Firestore(ctx)
	if err != nil {
		return nil, err
	}
	userData := userDocData(ctx, db.Collection("users").Doc(uid))

	service, err := newQuizService(ctx, uid, premium.IsEffectivePremium(userData, time.Now()), l)
	if err != nil {
		return nil, callable.Errorf(callable.Internal, "クイズの生成に失敗しました")
	}

	questions := generateQuestionsFromSources(ctx, service, []quizSeedSource{source})
	if len(questions) == 0 {
		return nil, callable.Errorf(callable.Internal, "クイズの生成に失敗しました")
	}

	return map[string]any{"questions": questions[:1]}, nil
}

func userDocData(ctx context.Context, ref *firestore.DocumentRef) map[string]any {
	doc, err := ref.Get(ctx)
	if err != nil || doc == nil || !doc.Exists() {
		return map[string]any{}
	}
	return doc.Data()
}

// newQuizService は Gemini のクライアントを作る。
// quizServiceFactory はテストから差し替える。
var quizServiceFactory = func(
	ctx context.Context, uid string, isPremium bool, l lang.Lang,
) (quizService, error) {
	apiKey, err := secrets.Get(ctx, "gemini-api-key")
	if err != nil {
		return nil, err
	}
	tier := "free"
	if isPremium {
		tier = "premium"
	}
	return &gemini.QuizService{APIKey: apiKey, UID: uid, Tier: tier, Lang: l}, nil
}

// quizService はクイズ生成の依存。テストで差し替えられるように挟む。
type quizService interface {
	GenerateQuizQuestions(
		ctx context.Context, sentences []quizgen.QuizSentenceSeed,
	) []quizgen.GeneratedQuizQuestion
}

func newQuizService(
	ctx context.Context, uid string, isPremium bool, l lang.Lang,
) (quizService, error) {
	return quizServiceFactory(ctx, uid, isPremium, l)
}

func updateQuizStats(
	ctx context.Context, userRef *firestore.DocumentRef, questionCount int,
) error {
	_, err := userRef.Set(ctx, map[string]any{
		"last_active_at":                firestore.ServerTimestamp,
		"last_quiz_generated_at":        firestore.ServerTimestamp,
		"quiz_generated_count":          firestore.Increment(1),
		"quiz_question_generated_count": firestore.Increment(questionCount),
	}, firestore.MergeAll)
	return err
}

// nowJST は JST 現在日時（UTC の時計に +9h した値）。JS 版の nowJST() と同じ。
func nowJST() time.Time {
	return time.Now().UTC().Add(jstOffset)
}
