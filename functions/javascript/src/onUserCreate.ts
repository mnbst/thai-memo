import * as functions from 'firebase-functions/v1';
import * as admin from 'firebase-admin';
import { FREE_DAILY_SENTENCES, FREE_DAILY_QUIZZES, PREMIUM_TRIAL_SENTENCES } from './constants/quota';
import { notifyUtcHour } from './utils/notifyUtcHour';

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
          daily_sentence_generated: false,
          premium_trial_remaining: PREMIUM_TRIAL_SENTENCES,
          // 毎日例文の配信対象クエリ用。実際の timezone / 希望時刻に基づく値は
          // クライアントの設定書き込みか dailyBatch が上書きする。ここで既定値を
          // 入れておかないと、初回生成から次の dailyBatch までの間だけ
          // 配信対象クエリから漏れる。
          notify_utc_hour: notifyUtcHour(undefined, undefined),
        },
        { merge: true },
      );

    console.log(`Initial quota set for user ${user.uid}`);
  });
