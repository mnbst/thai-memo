package function

import (
	"context"
	"errors"
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
	"github.com/mnbst/thai-memo/functions/go/internal/spellunit"
	"github.com/mnbst/thai-memo/functions/go/internal/uvm"
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

	quizGenerationLeaseDuration = 2 * time.Minute
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
	QuizFormat                 string         `json:"quiz_format,omitempty"`
	// SpellingParts は綴り4択の答え合わせ用。正解の綴りを頭子音・母音・
	// 末子音・声調に分けたもの（音の順）。
	SpellingParts []spellunit.Part `json:"spelling_parts,omitempty"`
	// SpellingGlyphs は同じ正解を書く順に切ったもの。画面はこれで
	// 「綴りのどの字がどの部品か」を色分けする。
	SpellingGlyphs []spellunit.Glyph `json:"spelling_glyphs,omitempty"`
	// SpellingToneRule は声調が決まる3要素（頭子音の階級・生音/死音・
	// 声調記号）。声調だけは字が1つに対応しないので、規則として見せる。
	SpellingToneRule *spellunit.ToneRule `json:"spelling_tone_rule,omitempty"`
}

// ---------------------------------------------------------------------------
// エントリポイント
// ---------------------------------------------------------------------------

// acquireQuizLease は同一ユーザーのクイズ生成を直列化する lease を取る。
//
// 競合は ResourceExhausted にしない。クライアントは resource-exhausted を
// 「本日の生成上限」として扱い（backend_api_service.dart）、連打やタイムアウト
// 後の再試行で「今日の新しいクイズはここまでです」と嘘を出してしまう。
// 一時的な衝突は Aborted、それ以外の障害は Internal にしてログへ残す。
func acquireQuizLease(
	ctx context.Context, db *firestore.Client, uid string, userRef *firestore.DocumentRef,
) (string, error) {
	token, err := acquireOperationLease(
		ctx, db, userRef, "quiz", quizGenerationLeaseDuration)
	if errors.Is(err, errGenerationInProgress) {
		return "", callable.Errorf(callable.Aborted,
			"クイズを生成中です。しばらくしてから再度お試しください")
	}
	if err != nil {
		log.Printf("generateQuiz: lease の取得に失敗: uid=%s error=%v", uid, err)
		return "", callable.Errorf(callable.Internal, "クイズの生成に失敗しました")
	}
	return token, nil
}

func generateQuiz(ctx context.Context, req *callable.Request) (any, error) {
	uid, err := req.RequireAuth()
	if err != nil {
		return nil, err
	}

	var in struct {
		Lang                 any      `json:"lang"`
		SupportedQuizFormats []string `json:"supported_quiz_formats"`
	}
	_ = req.Bind(&in)
	// 解説の言語。旧クライアントは送ってこないので ja に落ちる。
	l := lang.Resolve(in.Lang)

	db, err := fbapp.Firestore(ctx)
	if err != nil {
		return nil, err
	}

	userRef := db.Collection("users").Doc(uid)
	leaseToken, err := acquireQuizLease(ctx, db, uid, userRef)
	if err != nil {
		return nil, err
	}
	defer releaseOperationLease(ctx, db, userRef, "quiz", leaseToken)
	userData := userDocData(ctx, userRef)

	// トライアル中も premium と同じ品質で出す。
	service, err := newQuizService(ctx, uid, premium.IsEffectivePremium(userData, time.Now()), l)
	if err != nil {
		return nil, callable.Errorf(callable.Internal, "クイズの生成に失敗しました")
	}

	// SRS ベースでリアルタイムに復習対象例文を選出
	filter := quizKeyWordFilter(ctx, userData)
	sel := newSelection()
	// 語彙テストの測定値で絞り、空なら絞らずにやり直す（1周ぶん）。
	selectPass := func(viewedOnly bool) error {
		if err := selectSentencesBySRS(
			ctx, db, uid, nowJST(), filter, viewedOnly, sel); err != nil {
			return err
		}
		if len(sel.sentences) == 0 && filter != nil {
			// 測定値より上の例文がまだ無いユーザーを無出題にしない。
			log.Printf("quiz_vocab_floor_filter_empty uid=%s", uid)
			return selectSentencesBySRS(ctx, db, uid, nowJST(), nil, viewedOnly, sel)
		}
		return nil
	}

	// まず既読だけで選ぶ。まだ読んでいない例文から出題しないため。
	if err := selectPass(true); err != nil {
		log.Printf("Failed to generate quiz: %v", err)
		return nil, callable.Errorf(callable.Internal, "クイズの生成に失敗しました")
	}
	if !sel.full() {
		// 既読だけでは問題数が埋まらない（始めたばかり・例文を読まずに
		// クイズだけ回す人）。無出題や2問だけのクイズにするより、
		// 未読を混ぜてでも従来どおりの問題数を出す。
		log.Printf("quiz_viewed_only_short uid=%s viewed=%d", uid, len(sel.sentences))
		if err := selectPass(false); err != nil {
			log.Printf("Failed to generate quiz: %v", err)
			return nil, callable.Errorf(callable.Internal, "クイズの生成に失敗しました")
		}
	}
	selected := sel.sentences

	// ユーザー例文がない場合 → クライアントに通知
	if len(selected) == 0 {
		return map[string]any{
			"questions":         []quizQuestion{},
			"no_user_sentences": true,
		}, nil
	}

	sources := buildQuizSources(selected)
	if beginnerQuizEnabled(userData) {
		words := make([]string, 0, len(sources))
		for _, source := range sources {
			words = append(words, source.Seed.KeyWord)
		}
		applied := applyBeginnerFormats(sources, in.SupportedQuizFormats, l,
			beginnerPassedWords(ctx, db, uid, words))
		log.Printf("beginner_quiz_formats_applied uid=%s applied=%d of=%d",
			uid, applied, len(sources))
	}

	// まとめクイズはダミーが確定していれば理由と解説を使い回せる。
	questions := generateQuestionsFromSources(ctx,
		withQuizClozeCache(service, db, l), sources)
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

func supportsQuizFormat(supported []string, format string) bool {
	for _, candidate := range supported {
		if candidate == format {
			return true
		}
	}
	return false
}

func generateLearningQuiz(ctx context.Context, req *callable.Request) (any, error) {
	uid, err := req.RequireAuth()
	if err != nil {
		return nil, err
	}

	var in struct {
		Lang                 any            `json:"lang"`
		Sentence             map[string]any `json:"sentence"`
		SupportedQuizFormats []string       `json:"supported_quiz_formats"`
	}
	_ = req.Bind(&in)
	l := lang.Resolve(in.Lang)

	source, ok := buildLearningQuizSourceForClient(
		in.Sentence,
		supportsQuizFormat(in.SupportedQuizFormats, quizgen.FormatMeaningChoice),
		func() []uvm.TestItem {
			// 例文が短くて選択肢が埋まらないときだけ読む（インスタンス内で使い回す）。
			items, err := vocabTestItems(ctx, l)
			if err != nil {
				log.Printf("meaning_choice_topup_unavailable error=%v", err)
				return nil
			}
			return items
		},
	)
	if !ok || !quizgen.IsSeedReady(source.Seed) {
		return nil, callable.Errorf(callable.InvalidArgument,
			"クイズに使える例文データがありません")
	}

	db, err := fbapp.Firestore(ctx)
	if err != nil {
		return nil, err
	}
	userRef := db.Collection("users").Doc(uid)
	leaseToken, err := acquireQuizLease(ctx, db, uid, userRef)
	if err != nil {
		return nil, err
	}
	defer releaseOperationLease(ctx, db, userRef, "quiz", leaseToken)
	userData := userDocData(ctx, userRef)

	service, err := newQuizService(ctx, uid, premium.IsEffectivePremium(userData, time.Now()), l)
	if err != nil {
		return nil, callable.Errorf(callable.Internal, "クイズの生成に失敗しました")
	}

	// 意味4択の解説は語単位で、穴埋めは文・正解・ダミーの組で使い回せるので、
	// どちらも共有キャッシュを挟む。
	questions := generateQuestionsFromSources(ctx,
		withQuizClozeCache(withWordExplanationCache(service, db, l), db, l),
		[]quizSeedSource{source})
	if len(questions) == 0 {
		return nil, callable.Errorf(callable.Internal, "クイズの生成に失敗しました")
	}

	return map[string]any{"questions": questions[:1]}, nil
}

// quizKeyWordFilter は境界より下のランクの key_word を出題から外すフィルタを返す。
// 境界が 0（＝まだ証拠が無い）や freq_rank を読めないときは nil。
//
// 境界より下の語ばかり出していると estimated_vocab が動かない。推定は境界付近の
// 窓の平均 P でしか動かないのに、まとめクイズは SRS で過去の例文＝もっと低い帯から
// 選んだ key_word を出すため、何問正解しても推定が動かなかった。
//
// 下端は estimated_vocab ではなく **語彙テストの測定値（vocab_test_vocab、固定値）**
// を使う。estimated_vocab を下端にすると自己参照の正のフィードバックになる:
//
//	出題が必ず境界以上 → 正解で境界より上に P>0.5 の語ができる
//	→ EstimateVocab の knownMaxRank が current を必ず上回る → スコアが上がる
//	→ 境界が上がる → 出題がさらに上へ → 正解し続ける限り止まらない
//
// 測定値なら原点として動かないので、estimated_vocab は「実際に上の帯の語へ
// 正解した」ぶんだけ伸びて止まる。未受験（0）は nil で従来どおり絞り込み無し。
// free は測定値を使わない。key_word 帯も推定の走査帯も free では原点シフト
// しない（GetSessionWords / SyncEstimatedVocab）ので、出題側だけ測定値で
// 切ると、上限 100 に収まる例文が全部フィルタで落ちて空になる。
func quizKeyWordFilter(ctx context.Context, userData map[string]any) keyWordFilter {
	if !premium.IsEffectivePremium(userData, time.Now()) {
		return nil
	}
	floor := intOf(userData["vocab_test_vocab"])
	if floor <= 0 {
		return nil
	}
	freqRank, err := uvm.GetFreqRank(ctx, fbapp.ProjectID())
	if err != nil || len(freqRank) == 0 {
		log.Printf("quiz_vocab_floor_filter_unavailable error=%v", err)
		return nil
	}
	return vocabFloorFilter(freqRank, floor)
}

// vocabFloorFilter は rank が floor 以上の語だけを通す。
// freq_rank に無い語は判定できないので残す。
func vocabFloorFilter(freqRank uvm.FreqRank, floor int) keyWordFilter {
	if floor <= 0 || len(freqRank) == 0 {
		return nil
	}
	return func(keyWord string) bool {
		rank, ok := freqRank[keyWord]
		return !ok || rank >= floor
	}
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
