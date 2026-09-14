package function

import (
	"context"
	"crypto/sha1"
	"encoding/hex"
	"log"
	"strings"

	"cloud.google.com/go/firestore"

	"github.com/mnbst/thai-memo/functions/go/internal/lang"
	"github.com/mnbst/thai-memo/functions/go/internal/quizgen"
)

// 意味4択の解説キャッシュ。
//
// 意味4択でモデルが作るのは explanation の1項目だけで、正解・選択肢・発音は
// すべてルールベースで確定している。解説は「対象単語そのものの説明」なので
// 例文に依存せず、同じ語・同じ意味なら誰に出しても同じ内容でよい。
// そこで最初に生成したユーザーの結果を全ユーザー共有のキャッシュへ貯め、
// 2人目以降は Gemini を叩かずに返す（レイテンシと生成失敗の削減が主目的、
// 費用は1問 $0.0003 程度なので副次的）。
const wordExplanationCollection = "word_explanations"

// wordExplanationStore は解説キャッシュの読み書き。テストで差し替える。
type wordExplanationStore interface {
	Load(ctx context.Context, key string) (string, bool)
	Save(ctx context.Context, key string, entry wordExplanationEntry)
}

// wordExplanationEntry は保存する1件。key は語と意味のハッシュなので、
// 中身を人が読めるように語・意味・言語も一緒に持たせる。
type wordExplanationEntry struct {
	Lang        string `firestore:"lang"`
	Word        string `firestore:"word"`
	Meaning     string `firestore:"meaning"`
	Explanation string `firestore:"explanation"`
}

// wordExplanationKey は言語・語・意味からキャッシュキーを作る。
// 同じ語でも意味が違えば別の解説になるため、意味までキーに含める。
// どれかが空なら空文字を返し、呼び出し側はキャッシュを使わない。
func wordExplanationKey(l lang.Lang, word, meaning string) string {
	word = strings.TrimSpace(word)
	meaning = strings.TrimSpace(meaning)
	if word == "" || meaning == "" {
		return ""
	}
	sum := sha1.Sum([]byte(string(l) + "\x00" + word + "\x00" + meaning))
	return hex.EncodeToString(sum[:])
}

// firestoreWordExplanationStore は Firestore 実装。
type firestoreWordExplanationStore struct {
	db *firestore.Client
}

func (s firestoreWordExplanationStore) Load(ctx context.Context, key string) (string, bool) {
	doc, err := s.db.Collection(wordExplanationCollection).Doc(key).Get(ctx)
	if err != nil || doc == nil || !doc.Exists() {
		return "", false
	}
	explanation, _ := doc.Data()["explanation"].(string)
	explanation = strings.TrimSpace(explanation)
	return explanation, explanation != ""
}

// Save は失敗してもクイズは成立するのでログだけ残す。
func (s firestoreWordExplanationStore) Save(
	ctx context.Context, key string, entry wordExplanationEntry,
) {
	_, err := s.db.Collection(wordExplanationCollection).Doc(key).Set(ctx, entry)
	if err != nil {
		log.Printf("word_explanation_cache_save_failed key=%s error=%v", key, err)
	}
}

// cachedQuizService は意味4択のときだけ解説キャッシュを挟む quizService。
type cachedQuizService struct {
	inner quizService
	store wordExplanationStore
	lang  lang.Lang
}

// withWordExplanationCache は確認クイズ用にキャッシュを噛ませる。
// 穴埋め（まとめクイズ）はモデルにダミーと理由も作らせるため対象外。
func withWordExplanationCache(
	inner quizService, db *firestore.Client, l lang.Lang,
) quizService {
	return &cachedQuizService{
		inner: inner,
		store: firestoreWordExplanationStore{db: db},
		lang:  l,
	}
}

func (c *cachedQuizService) GenerateQuizQuestions(
	ctx context.Context, sentences []quizgen.QuizSentenceSeed,
) []quizgen.GeneratedQuizQuestion {
	key := ""
	if len(sentences) == 1 && sentences[0].QuizFormat == quizgen.FormatMeaningChoice {
		key = wordExplanationKey(
			c.lang, sentences[0].KeyWord, sentences[0].KeyWordMeaning)
	}
	if key == "" {
		return c.inner.GenerateQuizQuestions(ctx, sentences)
	}

	if explanation, ok := c.store.Load(ctx, key); ok {
		if questions := buildMeaningQuestionFromCache(sentences, explanation); questions != nil {
			log.Printf("word_explanation_cache_hit word=%q", sentences[0].KeyWord)
			return questions
		}
	}

	questions := c.inner.GenerateQuizQuestions(ctx, sentences)
	if len(questions) == 0 || strings.TrimSpace(questions[0].Explanation) == "" {
		return questions
	}
	c.store.Save(ctx, key, wordExplanationEntry{
		Lang:        string(c.lang),
		Word:        sentences[0].KeyWord,
		Meaning:     sentences[0].KeyWordMeaning,
		Explanation: strings.TrimSpace(questions[0].Explanation),
	})
	return questions
}

// buildMeaningQuestionFromCache はモデルを呼ばずに1問を組み立てる。
// 意味4択でモデルが担当するのは explanation だけなので、
// それをキャッシュで埋めれば本番と同じ経路（ルールベース合成→検査）を通せる。
// 検査に落ちたら nil を返し、呼び出し側は通常どおりモデルへ回す。
func buildMeaningQuestionFromCache(
	sentences []quizgen.QuizSentenceSeed, explanation string,
) []quizgen.GeneratedQuizQuestion {
	merged := quizgen.ApplyRuleBasedFields(
		[]quizgen.Draft{{Explanation: explanation}}, sentences)
	questions := quizgen.DefaultSanitizer.Questions(merged)
	if len(questions) == 0 {
		return nil
	}
	return questions
}
