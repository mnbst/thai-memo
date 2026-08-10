import * as functions from 'firebase-functions/v1';
import * as admin from 'firebase-admin';
import {
  PREMIUM_DAILY_SENTENCES,
  PREMIUM_DAILY_QUIZZES,
  PREMIUM_TRIAL_DAYS,
  PREMIUM_TRIAL_SENTENCES,
} from './constants/quota';
import { notifyUtcHour } from './utils/notifyUtcHour';
import { trialExpiresAtMsFrom } from './utils/premium';

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
          // 登録直後はプレミアム体験トライアル中なので、初日から premium の回数を出す。
          remaining_sentences: PREMIUM_DAILY_SENTENCES,
          remaining_quizzes: PREMIUM_DAILY_QUIZZES,
          daily_sentence_generated: false,
          // 期限はクォータのリセット境界（JST 0:00）に揃える。実質2〜3日になる。
          premium_trial_expires_at: admin.firestore.Timestamp.fromMillis(
            trialExpiresAtMsFrom(Date.now(), PREMIUM_TRIAL_DAYS),
          ),
          // 旧クライアント（〜1.3.14）がテーマを消さないための凍結値。減らさない。
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
