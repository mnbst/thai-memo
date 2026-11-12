package function

import (
	"context"
	"log"
	"strconv"
	"strings"

	"cloud.google.com/go/firestore"
	"google.golang.org/api/iterator"

	"github.com/mnbst/thai-memo/functions/go/internal/callable"
	"github.com/mnbst/thai-memo/functions/go/internal/fbapp"
	"github.com/mnbst/thai-memo/functions/go/internal/uvm"
)

// vocabProgressPageSize は1回で返す語数。語が多い人は続きを取りに来る。
const vocabProgressPageSize = 500

type getVocabProgressRequest struct {
	// Cursor は前回の next_cursor。空なら最初から。
	Cursor string `json:"cursor"`
}

// getVocabProgress は履歴の語彙一覧に使う語の習熟度と語彙ランクを返す。
//
// last_seen の古い順に返すので、端末は next_cursor を覚えておけば次回から
// 変わった語だけを受け取れる。
func getVocabProgress(ctx context.Context, req *callable.Request) (any, error) {
	uid, err := req.RequireAuth()
	if err != nil {
		return nil, err
	}
	var in getVocabProgressRequest
	if err := req.Bind(&in); err != nil {
		return nil, err
	}

	db, err := fbapp.Firestore(ctx)
	if err != nil {
		return nil, err
	}
	freqRank, err := uvm.GetFreqRank(ctx, fbapp.ProjectID())
	if err != nil {
		return nil, callable.Errorf(callable.Internal, "語彙データを読み込めませんでした")
	}

	q := db.Collection("users").Doc(uid).Collection("uvm").
		OrderBy("last_seen", firestore.Asc).
		OrderBy(firestore.DocumentID, firestore.Asc).
		Limit(vocabProgressPageSize)
	if seen, word, ok := parseVocabCursor(in.Cursor); ok {
		q = q.StartAfter(seen, word)
	}

	it := q.Documents(ctx)
	defer it.Stop()

	words := make([]map[string]any, 0, vocabProgressPageSize)
	cursor := in.Cursor
	for {
		doc, err := it.Next()
		if err == iterator.Done {
			break
		}
		if err != nil {
			log.Printf("getVocabProgress: uid=%s error=%v", uid, err)
			return nil, callable.Errorf(callable.Internal, "語彙データを読み込めませんでした")
		}
		data := doc.Data()
		words = append(words, vocabProgressRow(doc.Ref.ID, data, freqRank))
		cursor = formatVocabCursor(floatField(data["last_seen"]), doc.Ref.ID)
	}

	return map[string]any{
		"words":       words,
		"next_cursor": cursor,
		"done":        len(words) < vocabProgressPageSize,
	}, nil
}

// vocabProgressRow は uvm doc を端末へ返す1行にする。rank は頻度表に無い語で 0。
func vocabProgressRow(word string, data map[string]any, freqRank map[string]int) map[string]any {
	return map[string]any{
		"word":     word,
		"rank":     freqRank[word],
		"p":        floatField(data["p"]),
		"answered": isVocabAnswered(data),
	}
}

// isVocabAnswered は語の力を測る回答をしたことがあるかを返す。
//
// 確認クイズの正解は P を動かさないので「答えた」に数えない。不正解は P が
// 初期値より下がるので数える。graded が無い doc は導入前のもので、回答があれば
// 採点済みとして扱う。
func isVocabAnswered(data map[string]any) bool {
	graded, hasGraded := data["graded"].(bool)
	if graded {
		return true
	}
	if !hasGraded && floatField(data["quiz_attempts"]) > 0 {
		return true
	}
	return floatField(data["p"]) < uvm.NewWordP
}

func formatVocabCursor(seen float64, word string) string {
	return strconv.FormatFloat(seen, 'f', -1, 64) + "|" + word
}

// parseVocabCursor は端末から来た cursor を解く。読めなければ最初から返す。
func parseVocabCursor(cursor string) (float64, string, bool) {
	raw, word, ok := strings.Cut(cursor, "|")
	if !ok || word == "" {
		return 0, "", false
	}
	seen, err := strconv.ParseFloat(raw, 64)
	if err != nil {
		return 0, "", false
	}
	return seen, word, true
}
