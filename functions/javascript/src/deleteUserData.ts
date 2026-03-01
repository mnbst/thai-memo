import { auth } from 'firebase-functions/v1';
import * as admin from 'firebase-admin';

const db = admin.firestore();

/**
 * Firebase Auth ユーザー削除時に Firestore のユーザーデータを自動削除
 */
export const deleteUserData = auth.user().onDelete(async (user) => {
  const uid = user.uid;
  console.log(`Deleting data for user: ${uid}`);

  const batch = db.batch();

  // users/{uid}/sentences サブコレクション削除
  const sentences = await db.collection(`users/${uid}/sentences`).listDocuments();
  for (const doc of sentences) {
    batch.delete(doc);
  }

  // users/{uid}/quiz_answers サブコレクション削除
  const quizAnswers = await db.collection(`users/${uid}/quiz_answers`).listDocuments();
  for (const doc of quizAnswers) {
    batch.delete(doc);
  }

  // users/{uid} ドキュメント削除
  batch.delete(db.doc(`users/${uid}`));

  // quiz_queue の該当ユーザーのドキュメント削除
  const quizQueue = await db.collection('quiz_queue')
    .where('uid', '==', uid)
    .get();
  for (const doc of quizQueue.docs) {
    batch.delete(doc.ref);
  }

  await batch.commit();
  console.log(`Deleted all data for user: ${uid}`);
});
