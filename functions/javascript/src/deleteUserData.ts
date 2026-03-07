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
 *   - users/{uid}（ユーザードキュメント本体）
 *   - quiz_queue 内の該当ユーザーのドキュメント
 *
 * 注意: Cloud Functions v1 の auth トリガーを使用（v2 ではまだ非サポート）
 */
import { auth } from 'firebase-functions/v1';
import * as admin from 'firebase-admin';

/** Firestore インスタンス */
const db = admin.firestore();

/**
 * deleteUserData - Firebase Auth ユーザー削除時に Firestore のユーザーデータを自動削除
 *
 * Firebase Auth の onDelete イベントトリガーにより自動実行される。
 * バッチ書き込みを使って関連する全データを1回のトランザクションで削除する。
 *
 * @param user - 削除されたユーザーの情報（uid を含む）
 */
export const deleteUserData = auth.user().onDelete(async (user) => {
  const uid = user.uid;
  console.log(`Deleting data for user: ${uid}`);

  const batch = db.batch();

  // users/{uid}/sentences サブコレクション削除（学習した例文データ）
  const sentences = await db.collection(`users/${uid}/sentences`).listDocuments();
  for (const doc of sentences) {
    batch.delete(doc);
  }

  // users/{uid}/quiz_answers サブコレクション削除（クイズの回答履歴）
  const quizAnswers = await db.collection(`users/${uid}/quiz_answers`).listDocuments();
  for (const doc of quizAnswers) {
    batch.delete(doc);
  }

  // users/{uid} ドキュメント削除（ユーザーの設定・サブスクリプション情報など）
  batch.delete(db.doc(`users/${uid}`));

  // quiz_queue 内の該当ユーザーのドキュメント削除
  const quizQueue = await db.collection('quiz_queue')
    .where('uid', '==', uid)
    .get();
  for (const doc of quizQueue.docs) {
    batch.delete(doc.ref);
  }

  // バッチ書き込みで一括削除を実行
  await batch.commit();
  console.log(`Deleted all data for user: ${uid}`);
});
