package function

import (
	"context"
	"log"
	"sort"
	"sync"
	"time"

	"cloud.google.com/go/firestore"
	"google.golang.org/api/iterator"

	"github.com/mnbst/thai-memo/functions/go/internal/quizgen"
)

// selectedSentence は選出した例文1件。
type selectedSentence struct {
	ID   string
	Data map[string]any
	// SrsInterval はどの SRS 間隔で選ばれたか。
	//   -1: SRS 対象外（UVM による補充）
	//   1/3/7/14/30: 該当する SRS 間隔（日数）
	SrsInterval int
}

// generateQuestionsFromSources は生成元ごとに1問ずつ作る。
// 失敗した分は1度だけ作り直す（key_word 不一致が主な失敗理由）。
func generateQuestionsFromSources(
	ctx context.Context, service quizService, sources []quizSeedSource,
) []quizQuestion {
	var ready []quizSeedSource
	for _, source := range sources {
		if isQuizSeedSourceReady(source) {
			ready = append(ready, source)
		}
	}
	if len(ready) == 0 {
		return nil
	}

	results := make([]*quizQuestion, len(ready))

	var wg sync.WaitGroup
	for i, source := range ready {
		wg.Add(1)
		go func(i int, source quizSeedSource) {
			defer wg.Done()
			results[i] = generateSingleQuizQuestion(ctx, service, source, 0)
		}(i, source)
	}
	wg.Wait()

	var retryIndices []int
	for i, q := range results {
		if q == nil {
			retryIndices = append(retryIndices, i)
		}
	}

	if len(retryIndices) > 0 {
		log.Printf("quiz_generation_retrying_failed_sources requested=%d failed=%d",
			len(ready), len(retryIndices))

		wg = sync.WaitGroup{}
		for _, i := range retryIndices {
			wg.Add(1)
			go func(i int) {
				defer wg.Done()
				results[i] = generateSingleQuizQuestion(ctx, service, ready[i], 1)
			}(i)
		}
		wg.Wait()
	}

	out := make([]quizQuestion, 0, len(results))
	var skipped int
	for _, q := range results {
		if q == nil {
			skipped++
			continue
		}
		out = append(out, *q)
	}
	if skipped > 0 {
		log.Printf("quiz_generation_skipped_sources_after_retry requested=%d skipped=%d",
			len(ready), skipped)
	}
	return out
}

func generateSingleQuizQuestion(
	ctx context.Context, service quizService, source quizSeedSource, attempt int,
) *quizQuestion {
	questions := service.GenerateQuizQuestions(ctx,
		[]quizgen.QuizSentenceSeed{source.Seed})
	if len(questions) == 0 {
		return nil
	}

	question := questions[0]
	if !matchesKeyWord(question, source.Seed) {
		if attempt == 0 {
			log.Printf("quiz_key_word_mismatch_retrying expected=%q got=%q attempt=%d",
				source.Seed.KeyWord, question.CorrectAnswer, attempt)
		} else {
			log.Printf("quiz_key_word_mismatch_after_retry expected=%q got=%q attempt=%d",
				source.Seed.KeyWord, question.CorrectAnswer, attempt)
		}
		return nil
	}

	out := toQuizQuestion(question, source)
	return &out
}

// ---------------------------------------------------------------------------
// SRS 例文選出
// ---------------------------------------------------------------------------

// selectSentencesBySRS はユーザーの全例文から復習対象を選出する。
//
// 選出の優先順位:
//  1. srsDays をランダム順に見て、ジャスト日付ごとに P 値最低の1文を最大2文選出
//  2. ①で埋まらなかった枠を、UVM の P 値が低いキーワード順に1語1文で補充
func selectSentencesBySRS(
	ctx context.Context, db *firestore.Client, uid string, jstNow time.Time,
) ([]selectedSentence, error) {
	var selected []selectedSentence
	usedIDs := map[string]bool{}
	usedKeyWords := map[string]bool{}

	add := func(candidate selectedSentence) {
		selected = append(selected, candidate)
		usedIDs[candidate.ID] = true
		if keyWord, ok := candidate.Data["key_word"].(string); ok && keyWord != "" {
			usedKeyWords[keyWord] = true
		}
	}

	srsSentences, err := selectSrsSentences(ctx, db, uid, jstNow)
	if err != nil {
		return nil, err
	}
	for _, candidate := range srsSentences {
		add(candidate)
	}

	if remaining := maxQuestions - len(selected); remaining > 0 {
		fillers, err := selectFillerSentencesByUvm(ctx, db, uid, remaining, usedIDs, usedKeyWords)
		if err != nil {
			return nil, err
		}
		for _, candidate := range fillers {
			add(candidate)
		}
	}

	return selected, nil
}

type srsIntervalCandidates struct {
	Interval   int
	Candidates []*firestore.DocumentSnapshot
}

func selectSrsSentences(
	ctx context.Context, db *firestore.Client, uid string, jstNow time.Time,
) ([]selectedSentence, error) {
	intervals := append([]int(nil), srsDays...)
	shuffleN(len(intervals), func(i, j int) {
		intervals[i], intervals[j] = intervals[j], intervals[i]
	})

	intervalCandidates := make([]srsIntervalCandidates, len(intervals))
	for i, interval := range intervals {
		got, err := fetchSrsCandidatesForInterval(ctx, db, uid, jstNow, interval)
		if err != nil {
			return nil, err
		}
		intervalCandidates[i] = got
	}

	var allDocs []*firestore.DocumentSnapshot
	for _, c := range intervalCandidates {
		allDocs = append(allDocs, c.Candidates...)
	}
	pMap, err := fetchUvmPValues(ctx, db, uid, collectKeyWords(allDocs))
	if err != nil {
		return nil, err
	}

	var selected []selectedSentence
	usedIDs := map[string]bool{}

	for _, c := range intervalCandidates {
		if len(selected) >= maxSrsSentences {
			break
		}

		var candidates []*firestore.DocumentSnapshot
		for _, doc := range c.Candidates {
			if !usedIDs[doc.Ref.ID] {
				candidates = append(candidates, doc)
			}
		}
		if len(candidates) == 0 {
			continue
		}

		// P 値が最も低い（= 覚えていない）語の文を選ぶ。
		// UVM 未登録は 1（十分に覚えている扱い）で最後尾へ。
		p := func(doc *firestore.DocumentSnapshot) float64 {
			keyWord, _ := doc.Data()["key_word"].(string)
			if v, ok := pMap[keyWord]; ok {
				return v
			}
			return 1
		}
		sort.SliceStable(candidates, func(i, j int) bool {
			return p(candidates[i]) < p(candidates[j])
		})

		candidate := candidates[0]
		selected = append(selected, selectedSentence{
			ID: candidate.Ref.ID, Data: candidate.Data(), SrsInterval: c.Interval,
		})
		usedIDs[candidate.Ref.ID] = true
	}

	return selected, nil
}

func fetchSrsCandidatesForInterval(
	ctx context.Context, db *firestore.Client, uid string, jstNow time.Time, interval int,
) (srsIntervalCandidates, error) {
	targetStart := startOfJstDayDaysAgo(jstNow, interval)
	targetEnd := targetStart.Add(dayDuration)

	it := db.Collection("users").Doc(uid).Collection("sentences").
		Where("created_at", ">=", targetStart).
		Where("created_at", "<", targetEnd).
		Documents(ctx)
	defer it.Stop()

	out := srsIntervalCandidates{Interval: interval}
	for {
		doc, err := it.Next()
		if err == iterator.Done {
			return out, nil
		}
		if err != nil {
			return srsIntervalCandidates{}, err
		}
		if isUserSentenceDocReady(doc.Data()) {
			out.Candidates = append(out.Candidates, doc)
		}
	}
}

// weakPThreshold はこれを下回り、かつ複数回間違えている語を優先する境目。
const weakPThreshold = 0.3

func selectFillerSentencesByUvm(
	ctx context.Context, db *firestore.Client, uid string, needed int,
	usedIDs, usedKeyWords map[string]bool,
) ([]selectedSentence, error) {
	var selected []selectedSentence
	if needed <= 0 {
		return selected, nil
	}

	it := db.Collection("users").Doc(uid).Collection("uvm").
		OrderBy("p", firestore.Asc).
		Limit(uvmFillerPageSize).
		Documents(ctx)
	defer it.Stop()

	var uvmDocs []*firestore.DocumentSnapshot
	for {
		doc, err := it.Next()
		if err == iterator.Done {
			break
		}
		if err != nil {
			return nil, err
		}
		uvmDocs = append(uvmDocs, doc)
	}

	// 「2回以上出題して、それでも P が低い」語を先頭へ。次に P の低い順。
	isWeak := func(doc *firestore.DocumentSnapshot) bool {
		data := doc.Data()
		return floatField(data["quiz_attempts"]) >= 2 && floatField(data["p"]) < weakPThreshold
	}
	sort.SliceStable(uvmDocs, func(i, j int) bool {
		wi, wj := isWeak(uvmDocs[i]), isWeak(uvmDocs[j])
		if wi != wj {
			return wi
		}
		return floatField(uvmDocs[i].Data()["p"]) < floatField(uvmDocs[j].Data()["p"])
	})

	for i := 0; i < len(uvmDocs) && len(selected) < needed; i += keywordInQueryLimit {
		end := min(i+keywordInQueryLimit, len(uvmDocs))

		var keyWords []string
		for _, doc := range uvmDocs[i:end] {
			if !usedKeyWords[doc.Ref.ID] {
				keyWords = append(keyWords, doc.Ref.ID)
			}
		}
		if len(keyWords) == 0 {
			continue
		}

		byKeyWord, err := fetchSentenceCandidatesByKeyWords(ctx, db, uid, keyWords, usedIDs)
		if err != nil {
			return nil, err
		}

		for _, keyWord := range keyWords {
			if len(selected) >= needed {
				break
			}
			if usedKeyWords[keyWord] {
				continue
			}
			candidates := byKeyWord[keyWord]
			if len(candidates) == 0 {
				continue
			}
			shuffleN(len(candidates), func(a, b int) {
				candidates[a], candidates[b] = candidates[b], candidates[a]
			})

			sentence := candidates[0]
			selected = append(selected, selectedSentence{
				ID: sentence.Ref.ID, Data: sentence.Data(), SrsInterval: -1,
			})
			usedIDs[sentence.Ref.ID] = true
			usedKeyWords[keyWord] = true
		}
	}

	return selected, nil
}

func fetchSentenceCandidatesByKeyWords(
	ctx context.Context, db *firestore.Client, uid string,
	keyWords []string, usedIDs map[string]bool,
) (map[string][]*firestore.DocumentSnapshot, error) {
	out := map[string][]*firestore.DocumentSnapshot{}
	if len(keyWords) == 0 {
		return out, nil
	}

	it := db.Collection("users").Doc(uid).Collection("sentences").
		Where("key_word", "in", keyWords).
		Documents(ctx)
	defer it.Stop()

	for {
		doc, err := it.Next()
		if err == iterator.Done {
			return out, nil
		}
		if err != nil {
			return nil, err
		}
		data := doc.Data()
		keyWord, ok := data["key_word"].(string)
		if !ok || usedIDs[doc.Ref.ID] || !isUserSentenceDocReady(data) {
			continue
		}
		out[keyWord] = append(out[keyWord], doc)
	}
}

// startOfJstDayDaysAgo は daysAgo 日前の JST 0:00 を UTC で返す。
func startOfJstDayDaysAgo(jstNow time.Time, daysAgo int) time.Time {
	jstNow = jstNow.UTC()
	shifted := time.Date(jstNow.Year(), jstNow.Month(), jstNow.Day()-daysAgo,
		0, 0, 0, 0, time.UTC)
	return shifted.Add(-jstOffset)
}

func collectKeyWords(docs []*firestore.DocumentSnapshot) []string {
	seen := map[string]bool{}
	var out []string
	for _, doc := range docs {
		keyWord, ok := doc.Data()["key_word"].(string)
		if !ok || keyWord == "" || seen[keyWord] {
			continue
		}
		seen[keyWord] = true
		out = append(out, keyWord)
	}
	return out
}

// fetchUvmPValues は指定された key_word 群の UVM P 値を一括取得する。
// UVM 未登録の単語は結果に含まれない（呼び出し側で既定値を使う）。
func fetchUvmPValues(
	ctx context.Context, db *firestore.Client, uid string, keyWords []string,
) (map[string]float64, error) {
	pMap := map[string]float64{}
	if len(keyWords) == 0 {
		return pMap, nil
	}

	uvmRef := db.Collection("users").Doc(uid).Collection("uvm")
	refs := make([]*firestore.DocumentRef, 0, len(keyWords))
	for _, keyWord := range keyWords {
		refs = append(refs, uvmRef.Doc(keyWord))
	}

	snapshots, err := db.GetAll(ctx, refs)
	if err != nil {
		return nil, err
	}
	for _, snap := range snapshots {
		if !snap.Exists() {
			continue
		}
		switch p := snap.Data()["p"].(type) {
		case float64:
			pMap[snap.Ref.ID] = p
		case int64:
			pMap[snap.Ref.ID] = float64(p)
		}
	}
	return pMap, nil
}

// isUserSentenceDocReady は例文 doc からクイズを作れるか。
func isUserSentenceDocReady(data map[string]any) bool {
	str := func(key string) string {
		s, _ := data[key].(string)
		return s
	}
	return quizgen.IsSeedReady(quizgen.QuizSentenceSeed{
		ThaiText:             str("thai_text"),
		Pronunciation:        str("pronunciation"),
		JapaneseTranslation:  str("japanese_translation"),
		KeyWord:              str("key_word"),
		KeyWordPronunciation: str("key_word_pronunciation"),
		KeyWordMeaning:       resolveKeyWordMeaning(data),
	})
}
