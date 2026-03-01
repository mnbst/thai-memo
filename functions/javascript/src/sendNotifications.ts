import * as functions from 'firebase-functions/v2';
import * as admin from 'firebase-admin';
import { isDev, isDevOnly } from './config/environment';
import { formatDate } from './utils/formatDate';

const db = admin.firestore();

/**
 * 復習通知配信: review_queue から未送信分を取得しFCM一括送信
 * dev環境: onRequest（HTTP）で手動実行
 * tester/prod環境: onSchedule（JST 8:00〜20:00 の間30分ごと）
 */
async function sendNotificationsHandler() {
  const now = new Date();
  const jstNow = new Date(now.getTime() + 9 * 60 * 60 * 1000);
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
          title: '今日のクイズ',
          body: `今日は${questionCount}問の復習があります`,
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
