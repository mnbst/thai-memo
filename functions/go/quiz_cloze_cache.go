package function

import (
	"context"
	"crypto/sha1"
	"encoding/hex"
	"log"
	"strings"
	"sync"

	"cloud.google.com/go/firestore"

	"github.com/mnbst/thai-memo/functions/go/internal/lang"
	"github.com/mnbst/thai-memo/functions/go/internal/quizgen"
)

// 穴埋めクイズ（まとめクイズ）のキャッシュ。
//
// 1つの例文に1件。出題に要るもの（ダミー3語・その発音・不正解理由・解説）を
// まとめて持つので、当たったときはダミー選定も品詞判定も発音生成もモデル呼び出しも
// 走らない。例文と正解が同じなら誰に出しても同じ問題でよい。
//
// 当たる場面は2つ。
//
//   - 同じユーザーへの出し直し。SRS は同じ例文を 1/3/7/14/30 日後に再出題する
//     ので、1つの例文が最大5回クイズになる。
//   - ユーザーをまたぐ共有。静的コーパスの例文は多くのユーザーへ同じ本文が
//     配られるため、2人目以降はそのまま使える。
//
// 選択肢の並びはキャッシュ後に Sanitizer が毎回混ぜるので、同じ問題でも
// 並び順は変わる。
const quizClozeCollection = "quiz_questions"

// quizClozeStore は穴埋めキャッシュの読み書き。テストで差し替える。
type quizClozeStore interface {
	Load(ctx context.Context, key string) (quizClozeEntry, bool)
	Save(ctx context.Context, key string, entry quizClozeEntry)
}

// quizClozeEntry は保存する1件。出題を組み立て直せるだけの内容を持つ。
// key はハッシュなので、中身を人が読めるように文と正解も入れておく。
type quizClozeEntry struct {
	Lang          string `firestore:"lang"`
	ThaiText      string `firestore:"thai_text"`
	CorrectAnswer string `firestore:"correct_answer"`
	// Dummies と DummyPronunciations は選定結果。当たったときは
	// PickDistractors を呼ばずにこれを使う。
	Dummies             []string          `firestore:"dummies"`
	DummyPronunciations map[string]string `firestore:"dummy_pronunciations"`
	Explanation         string            `firestore:"explanation"`
	DummyReasons        []string          `firestore:"dummy_reasons"`
}

// quizClozeKey は言語と本文からキャッシュキーを作る。例文1つにつき1件。
//
// ダミーはキーに入れない。入れると選定が変わるたびに別エントリになり、
// 当たるかどうかが選定の再現性に左右される。ダミーは中身として持ち、
// 当たったらそれをそのまま出題に使う。
//
// 正解（key_word）はキーに入れず、読み出し時に突き合わせる。同じ本文が
// 別の語を出題語として登録されることは実データでは無いが、そうなった
// ときに空欄の位置が違う問題を返さないため。
//
// 本文が空なら空文字を返し、呼び出し側はキャッシュを使わない。
func quizClozeKey(l lang.Lang, thaiText string) string {
	thai := strings.TrimSpace(thaiText)
	if thai == "" {
		return ""
	}
	sum := sha1.Sum([]byte(strings.Join([]string{string(l), thai}, "\x00")))
	return hex.EncodeToString(sum[:])
}

// firestoreQuizClozeStore は Firestore 実装。
type firestoreQuizClozeStore struct {
	db *firestore.Client
}

func (s firestoreQuizClozeStore) Load(ctx context.Context, key string) (quizClozeEntry, bool) {
	doc, err := s.db.Collection(quizClozeCollection).Doc(key).Get(ctx)
	if err != nil || doc == nil || !doc.Exists() {
		return quizClozeEntry{}, false
	}
	var entry quizClozeEntry
	if err := doc.DataTo(&entry); err != nil {
		return quizClozeEntry{}, false
	}
	// 出題に要るものが欠けていたら無かったことにする（作り直して上書きする）。
	if strings.TrimSpace(entry.Explanation) == "" ||
		len(entry.Dummies) != quizgen.DistractorCount ||
		len(entry.DummyReasons) != quizgen.DistractorCount {
		return quizClozeEntry{}, false
	}
	return entry, true
}

// Save は失敗してもクイズは成立するのでログだけ残す。
func (s firestoreQuizClozeStore) Save(ctx context.Context, key string, entry quizClozeEntry) {
	if _, err := s.db.Collection(quizClozeCollection).Doc(key).Set(ctx, entry); err != nil {
		log.Printf("quiz_cloze_cache_save_failed key=%s error=%v", key, err)
	}
}

// clozeCachedQuizService は穴埋めクイズのキャッシュ層。
//
// ダミーの選定もここが持つ。キャッシュに当たればダミーを選ばずに済むので、
// 選定（freq_rank の帯・品詞・発音）はミスしたときだけ走らせる。
type clozeCachedQuizService struct {
	inner quizService
	store quizClozeStore
	lang  lang.Lang

	// vocab はダミー選定に使う語彙情報。初回のミスまで作らない
	// （freq_rank の読み込みとランク順の並べ替えが要るため）。
	vocabOnce sync.Once
	vocab     quizgen.Vocab
}

// withQuizClozeCache は穴埋めクイズ用にキャッシュを噛ませる。
func withQuizClozeCache(inner quizService, db *firestore.Client, l lang.Lang) quizService {
	return &clozeCachedQuizService{
		inner: inner,
		store: firestoreQuizClozeStore{db: db},
		lang:  l,
	}
}

// distractors はダミー3件とその発音を作る。選べなければ空を返し、
// 呼び出し側は従来どおりモデルにダミーごと作らせる。
func (c *clozeCachedQuizService) distractors(
	ctx context.Context, seed quizgen.QuizSentenceSeed,
) ([]string, map[string]string) {
	// 呼び出し側が先に決めていればそれを使う（テストと、将来別経路から
	// 渡したいとき用）。
	if len(seed.FixedDummies) == quizgen.DistractorCount {
		pron := seed.FixedDummyPronunciations
		if len(pron) == 0 {
			pron = dummyPronunciations(seed.FixedDummies)
		}
		return seed.FixedDummies, pron
	}
	c.vocabOnce.Do(func() { c.vocab = newQuizVocab(ctx) })
	if c.vocab == nil {
		return nil, nil
	}
	dummies := quizgen.PickDistractors(
		c.vocab, quizgen.NormalizeTextValue(seed.KeyWord), seed.Words, nil)
	if len(dummies) == 0 {
		return nil, nil
	}
	return dummies, dummyPronunciations(dummies)
}

func (c *clozeCachedQuizService) GenerateQuizQuestions(
	ctx context.Context, sentences []quizgen.QuizSentenceSeed,
) []quizgen.GeneratedQuizQuestion {
	key := ""
	if len(sentences) == 1 && sentences[0].QuizFormat != quizgen.FormatMeaningChoice {
		key = quizClozeKey(c.lang, sentences[0].ThaiText)
	}
	if key == "" {
		return c.inner.GenerateQuizQuestions(ctx, sentences)
	}
	seed := sentences[0]
	answer := quizgen.NormalizeTextValue(seed.KeyWord)

	if entry, ok := c.store.Load(ctx, key); ok &&
		quizgen.NormalizeTextValue(entry.CorrectAnswer) == answer {
		if questions := buildClozeQuestionFromCache(seed, entry); questions != nil {
			log.Printf("quiz_cloze_cache_hit answer=%q", answer)
			return questions
		}
	}

	// ミスしたときだけダミーを選ぶ。
	seed.FixedDummies, seed.FixedDummyPronunciations = c.distractors(ctx, seed)

	questions := c.inner.GenerateQuizQuestions(ctx, []quizgen.QuizSentenceSeed{seed})
	if len(questions) == 0 {
		return questions
	}
	q := questions[0]
	// ダミーを選べなかった問題（モデルが作ったダミー）は保存しない。
	// 何を選択肢にしたかを保存しても、次に同じ組を作れる保証がない。
	if len(seed.FixedDummies) != quizgen.DistractorCount ||
		strings.TrimSpace(q.Explanation) == "" ||
		len(q.DummyReasons) != quizgen.DistractorCount {
		return questions
	}
	c.store.Save(ctx, key, quizClozeEntry{
		Lang:                string(c.lang),
		ThaiText:            seed.ThaiText,
		CorrectAnswer:       answer,
		Dummies:             append([]string(nil), seed.FixedDummies...),
		DummyPronunciations: seed.FixedDummyPronunciations,
		Explanation:         strings.TrimSpace(q.Explanation),
		DummyReasons:        append([]string(nil), q.DummyReasons...),
	})
	return questions
}

// buildClozeQuestionFromCache はモデルもダミー選定も通さずに1問を組み立てる。
//
// 選択肢・発音・理由・解説はすべてキャッシュの中身。空欄の位置と正解の発音だけ
// 例文側から作る（本番と同じ ApplyRuleBasedFields → 検査の経路）。
// 検査に落ちたら nil を返し、呼び出し側を通常どおりモデルへ回す。
func buildClozeQuestionFromCache(
	seed quizgen.QuizSentenceSeed, entry quizClozeEntry,
) []quizgen.GeneratedQuizQuestion {
	seed.FixedDummies = append([]string(nil), entry.Dummies...)
	seed.FixedDummyPronunciations = entry.DummyPronunciations
	sentences := []quizgen.QuizSentenceSeed{seed}
	merged := quizgen.ApplyRuleBasedFields([]quizgen.Draft{{
		Explanation:  entry.Explanation,
		DummyReasons: entry.DummyReasons,
	}}, sentences)
	questions := quizgen.DefaultSanitizer.Questions(merged)
	if len(questions) == 0 {
		return nil
	}
	return questions
}
