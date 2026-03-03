import * as functions from 'firebase-functions/v2';
import * as admin from 'firebase-admin';
import { isDev, isDevOnly } from './config/environment';
import { formatDate, nowJST } from './utils/formatDate';

const db = admin.firestore();

/**
 * sendNotificationsHandler - 復習通知のFCM配信
 *
 * review_queueから未送信（sent=false）のエントリを取得し、FCMで一括送信する。
 * 1. dev: 未送信すべて / tester・prod: 当日分のみ
 * 2. ユーザーのfcm_tokenとnotification_enabledを確認、無効ならスキップ
 * 3. FCM送信成功時にsent=trueに更新
 * 4. トークン無効エラー時はfcm_tokenを削除してスキップ
 *
 * スケジュール: JST 8:00〜20:00の間30分ごと（prod/tester） / HTTP手動実行（dev）
 */
async function sendNotificationsHandler() {
  const jstNow = nowJST();
  const today = formatDate(jstNow);

  console.log(`sendNotifications started: date=${today}`);

  // dev: 未送信すべて / 他環境: 当日分のみ
  let query = db.collection('review_queue')
    .where('sent', '==', false);
  if (!isDev()) {
    query = query.where('scheduled_date', '==', today);
  }
  const queueSnapshot = await query.get();

  if (queueSnapshot.empty) {
    console.log('No reviews to notify');
    return;
  }

  let sentCount = 0;
  let failCount = 0;

  for (const queueDoc of queueSnapshot.docs) {
    const data = queueDoc.data();

    try {
      const userDoc = await db.collection('users').doc(data.uid).get();
      const userData = userDoc.data();

      if (!userData?.fcm_token) {
        console.log(`Skipped: uid=${data.uid} has no fcm_token`);
        await queueDoc.ref.update({ sent: true });
        continue;
      }

      if (!userData.notification_enabled) {
        console.log(`Skipped: uid=${data.uid} has notifications disabled`);
        await queueDoc.ref.update({ sent: true });
        continue;
      }

      const questionCount = data.question_count || 0;

      const messageData: admin.messaging.Message = {
        token: userData.fcm_token,
        notification: {
          title: 'まいにちタイ語',
          body: '復習クイズが届きました📝 クイズタブからチャレンジ！',
        },
        data: {
          type: 'review',
          question_count: String(questionCount),
        },
        apns: {
          payload: { aps: { sound: 'default' } },
        },
        android: {
          notification: {
            sound: 'default',
            channelId: 'review_notifications',
          },
        },
      };

      await admin.messaging().send(messageData);
      await queueDoc.ref.update({ sent: true });
      sentCount++;
    } catch (error: any) {
      if (
        error?.code === 'messaging/invalid-registration-token' ||
        error?.code === 'messaging/registration-token-not-registered'
      ) {
        await db.collection('users').doc(data.uid).update({
          fcm_token: admin.firestore.FieldValue.delete(),
        });
        await queueDoc.ref.update({ sent: true });
      }

      console.error(`Failed to send to ${data.uid}:`, error);
      failCount++;
    }
  }

  console.log(`sendNotifications completed: sent=${sentCount}, failed=${failCount}`);
}

export const sendNotifications = isDevOnly()
  ? functions.https.onRequest({ region: 'asia-northeast1' }, async (_req, res) => {
    await sendNotificationsHandler();
    res.status(200).send('ok');
  })
  : functions.scheduler.onSchedule(
    {
      schedule: '*/30 8-20 * * *', // JST 8:00〜20:00 の間30分ごとに配信
      region: 'asia-northeast1',
      timeZone: 'Asia/Tokyo',
    },
    async () => {
      await sendNotificationsHandler();
    }
  );
