import * as functions from 'firebase-functions/v2';
import * as admin from 'firebase-admin';
import { FREE_DAILY_SENTENCES, FREE_DAILY_QUIZZES } from './constants/quota';

const db = admin.firestore();

export const resetLearningData = functions.https.onCall(
  {
    region: 'asia-northeast1',
    timeoutSeconds: 60,
    memory: '256MiB',
  },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new functions.https.HttpsError('unauthenticated', '認証が必要です');
    }

    const refs: admin.firestore.DocumentReference[] = [];

    const sentences = await db.collection(`users/${uid}/sentences`).listDocuments();
    refs.push(...sentences);

    const quizAnswers = await db.collection(`users/${uid}/quiz_answers`).listDocuments();
    refs.push(...quizAnswers);

    const uvm = await db.collection(`users/${uid}/uvm`).listDocuments();
    refs.push(...uvm);

    const quizQueue = await db.collection('quiz_queue')
      .where('uid', '==', uid)
      .get();
    for (const doc of quizQueue.docs) {
      refs.push(doc.ref);
    }

    const BATCH_LIMIT = 500;
    for (let i = 0; i < refs.length; i += BATCH_LIMIT) {
      const batch = db.batch();
      const chunk = refs.slice(i, i + BATCH_LIMIT);
      for (const ref of chunk) {
        batch.delete(ref);
      }
      await batch.commit();
    }

    await db.collection('users').doc(uid).set(
      {
        remaining_sentences: FREE_DAILY_SENTENCES,
        remaining_quizzes: FREE_DAILY_QUIZZES,
        daily_sentence_generated: false,
        sentence_generated_count: 0,
        estimated_vocab: 0,
      },
      { merge: true },
    );

    console.log(`Reset ${refs.length} document(s) for user: ${uid}`);
    return { deleted: refs.length };
  },
);
