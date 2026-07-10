/**
 * deleteUserData.ts — Firebase Auth ユーザー削除時の Firestore データ自動クリーンアップ
 *
 * 「まいにちタイ語」アプリでは Firebase Auth の匿名認証を使用しているが、
 * ユーザーがアカウント削除を行った場合（またはFirebase側で自動削除された場合）、
 * Firestore に残ったユーザーデータを自動的に削除する必要がある。
 *
 * 本関数は Firebase Auth の onDelete トリガーにより自動実行され、
 * 以下の Firestore データを一括削除する:
 *   - users/{uid}/sentences（学習した例文データ）
 *   - users/{uid}/quiz_answers（クイズの回答履歴）
 *   - users/{uid}/uvm（語彙習得モデル）
 *   - users/{uid}（ユーザードキュメント本体）
 *   - quiz_queue 内の該当ユーザーのドキュメント
 *
 * 注意: Cloud Functions v1 の auth トリガーを使用（v2 ではまだ非サポート）
 */
import * as functions from 'firebase-functions/v1';
import * as admin from 'firebase-admin';

/** Firestore インスタンス */
const db = admin.firestore();

/**
 * 指定ユーザーの Firestore データを同期削除する。
 *
 * onDelete トリガーと dailyBatch の匿名ユーザー掃除の両方から呼ばれる。
 * バッチ書き込み（500件制限）を分割しながら関連する全データを削除する。
 * 既に存在しない doc への delete は無害（冪等）。
 *
 * @param uid - 削除対象ユーザーの uid
 * @returns 削除した DocumentReference 数
 */
export async function deleteUserFirestoreData(uid: string): Promise<number> {
  // 削除対象の DocumentReference を収集
  const refs: admin.firestore.DocumentReference[] = [];

  // users/{uid}/sentences サブコレクション（学習した例文データ）
  const sentences = await db.collection(`users/${uid}/sentences`).listDocuments();
  refs.push(...sentences);

  // users/{uid}/quiz_answers サブコレクション（クイズの回答履歴）
  const quizAnswers = await db.collection(`users/${uid}/quiz_answers`).listDocuments();
  refs.push(...quizAnswers);

  // users/{uid}/uvm サブコレクション（語彙習得モデル）
  const uvm = await db.collection(`users/${uid}/uvm`).listDocuments();
  refs.push(...uvm);

  // users/{uid} ドキュメント本体
  refs.push(db.doc(`users/${uid}`));

  // quiz_queue 内の該当ユーザーのドキュメント
  const quizQueue = await db.collection('quiz_queue')
    .where('uid', '==', uid)
    .get();
  for (const doc of quizQueue.docs) {
    refs.push(doc.ref);
  }

  // 500件ずつバッチ分割して削除
  const BATCH_LIMIT = 500;
  for (let i = 0; i < refs.length; i += BATCH_LIMIT) {
    const batch = db.batch();
    const chunk = refs.slice(i, i + BATCH_LIMIT);
    for (const ref of chunk) {
      batch.delete(ref);
    }
    await batch.commit();
  }

  return refs.length;
}

/**
 * deleteUserData - Firebase Auth ユーザー削除時に Firestore のユーザーデータを自動削除
 *
 * Firebase Auth の onDelete イベントトリガーにより自動実行される。
 *
 * @param user - 削除されたユーザーの情報（uid を含む）
 */
export const deleteUserData = functions.region('asia-northeast1').auth.user().onDelete(async (user) => {
  const uid = user.uid;
  console.log(`Deleting data for user: ${uid}`);
  const count = await deleteUserFirestoreData(uid);
  console.log(`Deleted ${count} document(s) for user: ${uid}`);
});
