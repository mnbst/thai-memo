package function

import (
	"context"
	"errors"
	"log"
	"sort"

	"cloud.google.com/go/firestore"
	"google.golang.org/api/iterator"
)

// 洗い替えた未読配信の露出の取り消し。
//
// 配信は通知が届いた時点で key_word の露出を UVM に記録する（P=0.4 の doc を
// 作る）。読まれないまま洗い替えると例文 doc には削除印が付くが、UVM の記録は
// 残る。その語は「既出」なので新しい例文の対象にならず、例文が無いので
// 出し直し（PickReused）にもまとめクイズにも出ない。帯の語がこうして埋まると
// 未出語が尽き、例文が残っている数語だけが出し直され続ける（2026-11 prod）。
//
// 一度も答えていない語で、ほかに生きた例文も無いものだけ UVM の doc を消して
// 未出に戻す。答えた語・別の例文で読んだ語の記録には触らない。
// 洗い替えは viewed を書く版（SupportsViewTracking）の未読 doc にしか
// 起きないので、viewed を書かない旧クライアントの挙動は変わらない。

// unexposeSentenceLimit は語ごとに生きた例文を探す doc 数の上限。
// 削除印つきの doc も同じ語に残るので reuseSentenceLimit と同じだけ読む。
const unexposeSentenceLimit = 50

// purgedKeyWords は今回削除印を付けた doc の key_word（重複なし・昇順）。
func purgedKeyWords(docs []deliveredDoc, purged map[string]bool) []string {
	seen := map[string]bool{}
	var words []string
	for _, doc := range docs {
		if !purged[doc.ID] {
			continue
		}
		word, _ := doc.Data["key_word"].(string)
		if word == "" || seen[word] {
			continue
		}
		seen[word] = true
		words = append(words, word)
	}
	sort.Strings(words)
	return words
}

// isExposureOnlyUVM は露出しただけで一度も答えていない UVM doc か。
func isExposureOnlyUVM(data map[string]any) bool {
	return intValue(data["quiz_attempts"]) == 0 && floatField(data["evidence"]) <= 0
}

// hasLiveSentence は purged 以外に削除印の無い例文があるか。
func hasLiveSentence(docs []deliveredDoc, purged map[string]bool) bool {
	for _, doc := range docs {
		if !purged[doc.ID] && !isSentenceDeleted(doc.Data) {
			return true
		}
	}
	return false
}

var errKeepExposure = errors.New("keep exposure")

// unexposePurgedKeyWords は words のうち未出に戻せる語の UVM doc を消し、消した数を返す。
// 失敗しても配信は止めない（取り消せなかった語は従来どおり既出のまま残る）。
func unexposePurgedKeyWords(
	ctx context.Context, db *firestore.Client, userRef *firestore.DocumentRef,
	words []string, purged map[string]bool,
) int {
	removed := 0
	for _, word := range words {
		uvmRef := userRef.Collection("uvm").Doc(word)
		query := userRef.Collection("sentences").
			Where("key_word", "==", word).Limit(unexposeSentenceLimit)
		// 判定と削除を1トランザクションにする。そのあいだに同じ語の例文が
		// 作られた・答えられたら、読み直して消さない側へ倒れる。
		err := db.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
			snap, err := tx.Get(uvmRef)
			if isNotFoundErr(err) {
				return errKeepExposure
			}
			if err != nil {
				return err
			}
			if !isExposureOnlyUVM(snap.Data()) {
				return errKeepExposure
			}
			docs, err := transactionDocs(tx, query)
			if err != nil {
				return err
			}
			if hasLiveSentence(docs, purged) {
				return errKeepExposure
			}
			return tx.Delete(uvmRef)
		})
		switch {
		case err == nil:
			removed++
		case errors.Is(err, errKeepExposure):
		default:
			log.Printf("daily_sentence: 露出の取り消しに失敗 uid=%s word=%s: %v", userRef.ID, word, err)
		}
	}
	return removed
}

func transactionDocs(tx *firestore.Transaction, q firestore.Query) ([]deliveredDoc, error) {
	it := tx.Documents(q)
	defer it.Stop()
	var docs []deliveredDoc
	for {
		doc, err := it.Next()
		if err == iterator.Done {
			return docs, nil
		}
		if err != nil {
			return nil, err
		}
		docs = append(docs, deliveredDoc{ID: doc.Ref.ID, Data: doc.Data()})
	}
}
