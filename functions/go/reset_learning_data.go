package function

import (
	"context"
	"log"

	"cloud.google.com/go/firestore"
	"google.golang.org/api/iterator"

	"github.com/mnbst/thai-memo/functions/go/internal/callable"
	"github.com/mnbst/thai-memo/functions/go/internal/fbapp"
	"github.com/mnbst/thai-memo/functions/go/internal/quota"
)

// batchLimit は Firestore の一括書き込み上限。
const batchLimit = 500

// resetLearningData は functions/javascript/src/resetLearningData.ts の移植。
//
// 呼び出し元ユーザーの学習データを全消しし、クォータを free の初期値に戻す。
// 返り値は {"deleted": <件数>}。JS 版と同じ電文・同じ文言を返すこと。
func resetLearningData(ctx context.Context, req *callable.Request) (any, error) {
	uid, err := req.RequireAuth()
	if err != nil {
		return nil, err
	}

	db, err := fbapp.Firestore(ctx)
	if err != nil {
		return nil, err
	}

	var refs []*firestore.DocumentRef

	// JS の listDocuments() 相当。実体の無い doc（サブコレクションだけ持つ）も
	// 拾う必要があるので Documents ではなく DocumentRefs を使う。
	for _, sub := range []string{"sentences", "quiz_answers", "uvm"} {
		got, err := documentRefs(ctx, db.Collection("users").Doc(uid).Collection(sub))
		if err != nil {
			return nil, err
		}
		refs = append(refs, got...)
	}

	queue := db.Collection("quiz_queue").Where("uid", "==", uid).Documents(ctx)
	defer queue.Stop()
	for {
		doc, err := queue.Next()
		if err == iterator.Done {
			break
		}
		if err != nil {
			return nil, callable.Errorf(callable.Internal, "quiz_queue の取得に失敗しました")
		}
		refs = append(refs, doc.Ref)
	}

	for i := 0; i < len(refs); i += batchLimit {
		end := min(i+batchLimit, len(refs))
		batch := db.BulkWriter(ctx)
		for _, ref := range refs[i:end] {
			if _, err := batch.Delete(ref); err != nil {
				return nil, callable.Errorf(callable.Internal, "削除に失敗しました")
			}
		}
		batch.End()
	}

	_, err = db.Collection("users").Doc(uid).Set(ctx, map[string]any{
		"remaining_sentences":      quota.FreeDailySentences,
		"remaining_quizzes":        quota.FreeDailyQuizzes,
		"daily_sentence_generated": false,
		"sentence_generated_count": 0,
		"estimated_vocab":          0,
	}, firestore.MergeAll)
	if err != nil {
		return nil, callable.Errorf(callable.Internal, "クォータの初期化に失敗しました")
	}

	log.Printf("Reset %d document(s) for user: %s", len(refs), uid)
	return map[string]any{"deleted": len(refs)}, nil
}

func documentRefs(ctx context.Context, col *firestore.CollectionRef) ([]*firestore.DocumentRef, error) {
	it := col.DocumentRefs(ctx)

	var out []*firestore.DocumentRef
	for {
		ref, err := it.Next()
		if err == iterator.Done {
			return out, nil
		}
		if err != nil {
			return nil, callable.Errorf(callable.Internal, "%s の取得に失敗しました", col.Path)
		}
		out = append(out, ref)
	}
}
