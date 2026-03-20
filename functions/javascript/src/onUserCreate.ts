import * as functions from 'firebase-functions/v1';
import * as admin from 'firebase-admin';
import { INITIAL_SENTENCES, INITIAL_QUIZZES } from './constants/quota';

/**
 * Firebase Auth の onCreate トリガー
 * 新規ユーザー作成時に初回ボーナスクォータを付与する
 */
export const onUserCreate = functions
  .region('asia-northeast1')
  .auth.user()
  .onCreate(async (user) => {
    await admin
      .firestore()
      .collection('users')
      .doc(user.uid)
      .set(
        {
          remaining_sentences: INITIAL_SENTENCES,
          remaining_quizzes: INITIAL_QUIZZES,
          uvm_initialized: true,
          daily_sentence_generated: false,
          is_first_generation: true,
        },
        { merge: true },
      );

    console.log(`Initial quota set for user ${user.uid}`);
  });
