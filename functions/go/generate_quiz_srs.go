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
// 意味4択・綴り4択だけが失敗した場合は、同じ例文の穴埋めへ戻して問題数を保つ。
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

	for i, q := range results {
		if q != nil || ready[i].Seed.QuizFormat == quizgen.FormatClozeChoice {
			continue
		}
		fallback := ready[i]
		log.Printf("quiz_falling_back_to_cloze format=%s sentenceId=%s",
			fallback.Seed.QuizFormat, fallback.SentenceID)
		fallback.Seed.QuizFormat = quizgen.FormatClozeChoice
		fallback.Seed.MeaningChoices = nil
		// 綴り4択のダミーは非語なので、穴埋めの選択肢に持ち越してはいけない。
		fallback.Seed.FixedDummies = nil
		fallback.Seed.FixedExplanation = ""
		fallback.WordOrder = nil
		results[i] = generateSingleQuizQuestion(ctx, service, fallback, 2)
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
	// 並び替えはタイルも正解も切り出し時に確定しているのでモデルを呼ばない。
	if source.Seed.QuizFormat == quizgen.FormatWordOrder {
		if source.WordOrder == nil {
			return nil
		}
		out := wordOrderQuestion(source)
		return &out
	}

	// 綴り4択は選択肢も解説もルールベースで確定しているのでモデルを呼ばない。
	if source.Seed.QuizFormat == quizgen.FormatSpellingChoice {
		question, ok := quizgen.BuildSpellingQuestion(source.Seed)
		if !ok {
			return nil
		}
		out := toQuizQuestion(question, source)
		out.SpellingParts, out.SpellingGlyphs, out.SpellingToneRule =
			spellingBreakdownOf(question.CorrectAnswer)
		return &out
	}

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

// keyWordFilter は key_word を出題してよいかを返す。nil は「絞り込み無し」。
type keyWordFilter func(keyWord string) bool

// allows は nil を「全部通す」として扱う。
func (f keyWordFilter) allows(keyWord string) bool {
	return f == nil || f(keyWord)
}

// selection は選出の途中経過。既読だけで1周し、足りなければ未読も含めて
// もう1周するので、選んだ例文と使った key_word を周をまたいで持ち回る。
type selection struct {
	sentences    []selectedSentence
	usedIDs      map[string]bool
	usedKeyWords map[string]bool
	// srsCount は SRS 枠（srsLimit）から選んだ本数。
	srsCount int
	// limit は問題数（＝選ぶ例文の数）。セット本数にそろえる。
	limit int
}

func newSelection(limit int) *selection {
	return &selection{
		usedIDs:      map[string]bool{},
		usedKeyWords: map[string]bool{},
		limit:        min(limit, maxQuestions),
	}
}

// srsLimit は SRS 枠の本数。問題数の半分まで（5問なら maxSrsSentences の2）。
// 短いクイズを SRS で埋めると、いま学んだ例文が出題から押し出される。
func (s *selection) srsLimit() int { return min(maxSrsSentences, s.limit/2) }

func (s *selection) add(candidate selectedSentence) {
	s.sentences = append(s.sentences, candidate)
	s.usedIDs[candidate.ID] = true
	if keyWord, ok := candidate.Data["key_word"].(string); ok && keyWord != "" {
		s.usedKeyWords[keyWord] = true
	}
	if candidate.SrsInterval > 0 {
		s.srsCount++
	}
}

func (s *selection) full() bool { return len(s.sentences) >= s.limit }

// isSentenceViewed は例文がユーザーに表示済みかどうか。
//
// viewed フィールドが無い例文は既読扱いにする。旧クライアント宛て・
// この機能より前に書かれた doc には付かないので、無い＝判定不能であり、
// 未読扱いにすると出題できる例文が消える（sentence.SupportsViewTracking）。
// 値が入っていて false のときだけ未読。
func isSentenceViewed(data map[string]any) bool {
	viewed, ok := data["viewed"].(bool)
	return !ok || viewed
}

// selectSentencesBySRS はユーザーの全例文から復習対象を選び、sel へ足す。
//
// 選出の優先順位:
//  1. srsDays をランダム順に見て、ジャスト日付ごとに P 値最低の1文を最大2文選出
//  2. ①で埋まらなかった枠を、UVM のキーワードから1語1文で補充
//     （苦手枠: 範囲外の苦手な語を1本 → スコア枠: bandWords の P 昇順
//     → 低P枠: それ以外の P 昇順）
//
// bandWords はスコア枠で見る語（uvm.QuizScoreBand）。
// nil（順位表を読めないとき）はスコア枠が空になり、苦手枠のあとは低P枠で埋める。
//
// filter は語彙テスト受験後に測定値より下の key_word を落とすために使う
// （quizKeyWordFilter を参照）。呼び出し側は、絞った結果が空になったら
// filter 無しでやり直すこと。
//
// viewedOnly が真なら未読（viewed == false）の例文を候補から外す。
// まだ読んでいない例文を出題しないための絞り込みで、これだけでは
// 問題数が埋まらないことがあるため、呼び出し側が偽でもう1周する。
func selectSentencesBySRS(
	ctx context.Context, db *firestore.Client, uid string, jstNow time.Time,
	filter keyWordFilter, bandWords []string, viewedOnly bool, sel *selection,
) error {
	srsSentences, err := selectSrsSentences(ctx, db, uid, jstNow, filter, viewedOnly, sel)
	if err != nil {
		return err
	}
	for _, candidate := range srsSentences {
		sel.add(candidate)
	}

	if remaining := sel.limit - len(sel.sentences); remaining > 0 {
		fillers, err := selectFillerSentencesByUvm(
			ctx, db, uid, jstNow, remaining, sel.usedIDs, sel.usedKeyWords, filter, bandWords, viewedOnly)
		if err != nil {
			return err
		}
		for _, candidate := range fillers {
			sel.add(candidate)
		}
	}

	return nil
}

type srsIntervalCandidates struct {
	Interval   int
	Candidates []*firestore.DocumentSnapshot
}

func selectSrsSentences(
	ctx context.Context, db *firestore.Client, uid string, jstNow time.Time,
	filter keyWordFilter, viewedOnly bool, sel *selection,
) ([]selectedSentence, error) {
	intervals := append([]int(nil), srsDays...)
	shuffleN(len(intervals), func(i, j int) {
		intervals[i], intervals[j] = intervals[j], intervals[i]
	})

	intervalCandidates := make([]srsIntervalCandidates, len(intervals))
	for i, interval := range intervals {
		got, err := fetchSrsCandidatesForInterval(
			ctx, db, uid, jstNow, interval, filter, viewedOnly)
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
	// 既に選んだぶんは2周目で選び直さない。SRS 枠の残りも周をまたいで数える。
	for id := range sel.usedIDs {
		usedIDs[id] = true
	}

	for _, c := range intervalCandidates {
		if sel.srsCount+len(selected) >= sel.srsLimit() {
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
	filter keyWordFilter, viewedOnly bool,
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
		data := doc.Data()
		keyWord, _ := data["key_word"].(string)
		// 本人が消した例文・洗い替えた未読セットは出題しない。
		if isSentenceDeleted(data) {
			continue
		}
		if viewedOnly && !isSentenceViewed(data) {
			continue
		}
		if isUserSentenceDocReady(data) && filter.allows(keyWord) {
			out.Candidates = append(out.Candidates, doc)
		}
	}
}

// weakPThreshold はこれを下回り、かつ複数回間違えている語を優先する境目。
const weakPThreshold = 0.3

// maxWeakFillerSentences は補充のうち苦手枠（範囲外の苦手な語）の上限。
// 残りはスコア枠に回す。
const maxWeakFillerSentences = 1

func selectFillerSentencesByUvm(
	ctx context.Context, db *firestore.Client, uid string, jstNow time.Time, needed int,
	usedIDs, usedKeyWords map[string]bool, filter keyWordFilter, bandWords []string, viewedOnly bool,
) ([]selectedSentence, error) {
	var selected []selectedSentence
	if needed <= 0 {
		return selected, nil
	}

	uvmRef := db.Collection("users").Doc(uid).Collection("uvm")
	it := uvmRef.OrderBy("p", firestore.Asc).
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

	// スコアの再計算範囲の語。ここで正解すると estimated_vocab に効く。
	// P の低い順だけだと、範囲外の P=prior の語と同点で並び（同点は doc ID
	// ＝文字コード順）、スコアのすぐ上の語がいつまでも出題されなかった。
	var bandDocs []*firestore.DocumentSnapshot
	if len(bandWords) > 0 {
		refs := make([]*firestore.DocumentRef, len(bandWords))
		for i, word := range bandWords {
			refs[i] = uvmRef.Doc(word)
		}
		snaps, err := db.GetAll(ctx, refs)
		if err != nil {
			return nil, err
		}
		for _, snap := range snaps {
			if snap.Exists() {
				bandDocs = append(bandDocs, snap)
			}
		}
	}

	// 苦手枠: 「2回以上出題して、それでも P が低い」語のうち範囲外のもの。
	// 範囲外はほぼ estimated_vocab より下の基本語で、間違えたままの語を
	// 出し直す。範囲内の苦手な語は P が最も低いのでスコア枠の先頭に来る。
	// スコア枠: 範囲内の P の低い順（同点はランダム）。正解がスコアに効く。
	// 低P枠: 範囲内に例文が足りないときだけ、残りを P の低い順で埋める。
	inBand := make(map[string]bool, len(bandDocs))
	for _, doc := range bandDocs {
		inBand[doc.Ref.ID] = true
	}
	p := func(doc *firestore.DocumentSnapshot) float64 { return floatField(doc.Data()["p"]) }
	isWeak := func(doc *firestore.DocumentSnapshot) bool {
		return floatField(doc.Data()["quiz_attempts"]) >= 2 && p(doc) < weakPThreshold
	}
	var weak, rest []string
	// Firestore は同点を doc ID（文字コード）順で返す。苦手な語は PFloor に
	// 張り付いて同点になりやすいので、シャッフルしてから並べて偏りを消す。
	shuffleN(len(uvmDocs), func(a, b int) {
		uvmDocs[a], uvmDocs[b] = uvmDocs[b], uvmDocs[a]
	})
	sort.SliceStable(uvmDocs, func(i, j int) bool { return p(uvmDocs[i]) < p(uvmDocs[j]) })
	for _, doc := range uvmDocs {
		switch {
		case inBand[doc.Ref.ID]:
		case isWeak(doc):
			weak = append(weak, doc.Ref.ID)
		default:
			rest = append(rest, doc.Ref.ID)
		}
	}
	shuffleN(len(bandDocs), func(a, b int) {
		bandDocs[a], bandDocs[b] = bandDocs[b], bandDocs[a]
	})
	sort.SliceStable(bandDocs, func(i, j int) bool { return p(bandDocs[i]) < p(bandDocs[j]) })
	band := make([]string, len(bandDocs))
	for i, doc := range bandDocs {
		band[i] = doc.Ref.ID
	}

	// pick は words を先頭から見て、例文のある語を limit 本まで selected に足す。
	pick := func(words []string, limit int) error {
		for i := 0; i < len(words) && len(selected) < limit; i += keywordInQueryLimit {
			end := min(i+keywordInQueryLimit, len(words))

			var keyWords []string
			for _, word := range words[i:end] {
				if !usedKeyWords[word] && filter.allows(word) {
					keyWords = append(keyWords, word)
				}
			}
			if len(keyWords) == 0 {
				continue
			}

			byKeyWord, err := fetchSentenceCandidatesByKeyWords(
				ctx, db, uid, jstNow, keyWords, usedIDs, viewedOnly)
			if err != nil {
				return err
			}

			for _, keyWord := range keyWords {
				if len(selected) >= limit {
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
		return nil
	}

	if err := pick(weak, min(needed, maxWeakFillerSentences)); err != nil {
		return nil, err
	}
	if err := pick(band, needed); err != nil {
		return nil, err
	}
	if err := pick(rest, needed); err != nil {
		return nil, err
	}

	return selected, nil
}

// keyWordCandidateLookbackDays は語から例文を引くときに遡る日数。
//
// users/{uid}/sentences は消さずに残すので、期間で切らないと使い込むほど
// 読み取り件数が増える。
const keyWordCandidateLookbackDays = 90

func fetchSentenceCandidatesByKeyWords(
	ctx context.Context, db *firestore.Client, uid string, jstNow time.Time,
	keyWords []string, usedIDs map[string]bool, viewedOnly bool,
) (map[string][]*firestore.DocumentSnapshot, error) {
	out := map[string][]*firestore.DocumentSnapshot{}
	if len(keyWords) == 0 {
		return out, nil
	}

	it := db.Collection("users").Doc(uid).Collection("sentences").
		Where("key_word", "in", keyWords).
		Where("created_at", ">=", startOfJstDayDaysAgo(jstNow, keyWordCandidateLookbackDays)).
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
		if !ok || usedIDs[doc.Ref.ID] || isSentenceDeleted(data) ||
			!isUserSentenceDocReady(data) {
			continue
		}
		if viewedOnly && !isSentenceViewed(data) {
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
		Words:                seedWords(data),
		Pronunciation:        str("pronunciation"),
		JapaneseTranslation:  str("japanese_translation"),
		KeyWord:              str("key_word"),
		KeyWordPronunciation: str("key_word_pronunciation"),
		KeyWordMeaning:       resolveKeyWordMeaning(data),
	})
}
