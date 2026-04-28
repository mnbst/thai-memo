import * as functions from 'firebase-functions/v2';
import * as admin from 'firebase-admin';
import { INITIAL_SENTENCES, INITIAL_QUIZZES } from './constants/quota';

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
        remaining_sentences: INITIAL_SENTENCES,
        remaining_quizzes: INITIAL_QUIZZES,
        uvm_initialized: true,
        daily_sentence_generated: false,
        is_first_generation: true,
        is_first_quiz_generation: true,
        sentence_generated_count: 0,
      },
      { merge: true },
    );

    console.log(`Reset ${refs.length} document(s) for user: ${uid}`);
    return { deleted: refs.length };
  },
);
