package sentence

import (
	"context"

	"cloud.google.com/go/firestore"
	"google.golang.org/api/iterator"
)

// historyLimit は既出判定で読む例文の件数。
//
// users/{uid}/sentences は 30 日で消える（dailyBatch の cleanOldSentences）。
// 1日の上限は配信5本＋自発生成ぶんなので、上限いっぱい使う人でも 30 日で
// 300 本には届かない。ここを小さくすると、読まなかった古い文が「既出でない」
// 扱いになって再び出る。
const historyLimit = 300

// History はそのユーザーに既に出した例文の本文を返す。
//
// バンク（FreeBank / CorpusBank）は語×テーマで1本しか持たないので、
// 同じ key_word が再選出されると同じ文がそのまま出る。既出を渡して
// バンク側で除けるようにする。
type History interface {
	SeenTexts(ctx context.Context, db *firestore.Client, uid string) (map[string]bool, error)
}

// FirestoreHistory は users/{uid}/sentences から既出の本文を読む。
type FirestoreHistory struct {
	// Limit は読む件数。0 なら historyLimit。
	Limit int
}

// SeenTexts は直近 Limit 件の thai_text を集合で返す。
//
// 本文だけを射影する。既出かどうかの判定に word_breakdown まで運ぶ必要は無い
// （読み取り課金は件数で決まるので変わらないが、転送量と復号の手間が減る）。
func (h *FirestoreHistory) SeenTexts(
	ctx context.Context, db *firestore.Client, uid string,
) (map[string]bool, error) {
	limit := h.Limit
	if limit <= 0 {
		limit = historyLimit
	}
	it := db.Collection("users").Doc(uid).Collection("sentences").
		OrderBy("created_at", firestore.Desc).Limit(limit).
		Select("thai_text").Documents(ctx)
	defer it.Stop()

	seen := map[string]bool{}
	for {
		doc, err := it.Next()
		if err == iterator.Done {
			return seen, nil
		}
		if err != nil {
			return nil, err
		}
		if text, ok := doc.Data()["thai_text"].(string); ok && text != "" {
			seen[text] = true
		}
	}
}
