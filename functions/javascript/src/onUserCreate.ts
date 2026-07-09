import * as functions from 'firebase-functions/v1';
import * as admin from 'firebase-admin';
import { FREE_DAILY_SENTENCES, FREE_DAILY_QUIZZES, PREMIUM_TRIAL_SENTENCES } from './constants/quota';

/**
 * Firebase Auth の onCreate トリガー
 * 新規ユーザー作成時にクォータを付与する
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
          remaining_sentences: FREE_DAILY_SENTENCES,
          remaining_quizzes: FREE_DAILY_QUIZZES,
          uvm_initialized: true,
          daily_sentence_generated: false,
          premium_trial_remaining: PREMIUM_TRIAL_SENTENCES,
        },
        { merge: true },
      );

    console.log(`Initial quota set for user ${user.uid}`);
  });
