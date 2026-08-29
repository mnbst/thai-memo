// Package userdata はユーザーの Firestore データ一括削除。
// functions/javascript/src/deleteUserData.ts:deleteUserFirestoreData の移植。
package userdata

import (
	"context"
	"fmt"
	"strings"

	"cloud.google.com/go/firestore"
	"google.golang.org/api/iterator"
)

// batchLimit は Firestore の一括書き込み上限。
const batchLimit = 500

// DeleteFirestoreData は指定ユーザーの Firestore データを同期削除する。
//
// Auth の onDelete トリガーと dailyBatch の匿名ユーザー掃除の両方から呼ばれる。
// バッチ書き込み（500件制限）を分割しながら関連する全データを削除する。
// 既に存在しない doc への delete は無害（冪等）。
//
// 削除対象:
//   - users/{uid}/sentences（学習した例文データ）
//   - users/{uid}/quiz_answers（クイズの回答履歴）
//   - users/{uid}/uvm（語彙習得モデル）
//   - users/{uid}（ユーザードキュメント本体）
//   - leaderboard/{uid}（ランキング公開用の複製）
//   - nicknames/{nickname}（ニックネームの予約）
//   - quiz_queue 内の該当ユーザーのドキュメント
//
// 返り値は削除した DocumentReference 数。
func DeleteFirestoreData(ctx context.Context, db *firestore.Client, uid string) (int, error) {
	var refs []*firestore.DocumentRef

	// 実体の無い doc（サブコレクションだけ持つ）も拾うため DocumentRefs を使う
	// （JS の listDocuments() 相当）。
	for _, sub := range []string{"sentences", "quiz_answers", "uvm"} {
		got, err := documentRefs(ctx, db.Collection("users").Doc(uid).Collection(sub))
		if err != nil {
			return 0, err
		}
		refs = append(refs, got...)
	}

	refs = append(refs, db.Collection("users").Doc(uid))

	// leaderboard/{uid} と nicknames の予約。
	// ニックネームは一度きりで本人も消せないため、ここで解放しないと名前が永久に埋まる。
	leaderboardRef := db.Collection("leaderboard").Doc(uid)
	snap, err := leaderboardRef.Get(ctx)
	if err != nil && !isNotFound(err) {
		return 0, fmt.Errorf("leaderboard/%s の取得に失敗: %w", uid, err)
	}
	if err == nil && snap.Exists() {
		if nickname, ok := snap.Data()["nickname"].(string); ok {
			if trimmed := strings.TrimSpace(nickname); trimmed != "" {
				refs = append(refs, db.Collection("nicknames").Doc(strings.ToLower(trimmed)))
			}
		}
	}
	refs = append(refs, leaderboardRef)

	queue := db.Collection("quiz_queue").Where("uid", "==", uid).Documents(ctx)
	defer queue.Stop()
	for {
		doc, err := queue.Next()
		if err == iterator.Done {
			break
		}
		if err != nil {
			return 0, fmt.Errorf("quiz_queue の取得に失敗: %w", err)
		}
		refs = append(refs, doc.Ref)
	}

	for i := 0; i < len(refs); i += batchLimit {
		end := min(i+batchLimit, len(refs))
		bw := db.BulkWriter(ctx)
		for _, ref := range refs[i:end] {
			if _, err := bw.Delete(ref); err != nil {
				return 0, fmt.Errorf("削除に失敗: %w", err)
			}
		}
		bw.End()
	}

	return len(refs), nil
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
			return nil, fmt.Errorf("%s の取得に失敗: %w", col.Path, err)
		}
		out = append(out, ref)
	}
}
