import * as functions from 'firebase-functions/v2';
import * as admin from 'firebase-admin';
import { isDev, isDevOnly } from './config/environment';

const db = admin.firestore();

/**
 * クイズ配信: quiz_queue から未送信分を取得しFCM一括送信
 * dev環境: onRequest（HTTP）で手動実行
 * tester/prod環境: onSchedule（JST 6:00 に1回）
 */
async function sendNotificationsHandler() {
  const now = new Date();
  const jstNow = new Date(now.getTime() + 9 * 60 * 60 * 1000);
  const today = formatDate(jstNow);

  console.log(`sendNotifications started: date=${today}`);

  // dev: 未送信すべて / 他環境: 当日分のみ
  let query = db.collection('quiz_queue')
    .where('sent', '==', false);
  if (!isDev()) {
    query = query.where('scheduled_date', '==', today);
  }
  const queueSnapshot = await query.get();

  if (queueSnapshot.empty) {
    console.log('No quiz to send');
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
        await queueDoc.ref.update({ sent: true, skipped: true });
        continue;
      }

      const questions = data.questions || [];

      const messageData: admin.messaging.Message = {
        token: userData.fcm_token,
        data: {
          type: 'quiz',
          quiz_queue_id: queueDoc.id,
          questions: JSON.stringify(questions),
        },
      };

      if (userData.notification_enabled) {
        messageData.notification = {
          title: '今日のクイズ',
          body: `${questions.length}問の穴埋めクイズが届きました`,
        };
        messageData.apns = {
          payload: { aps: { sound: 'default' } },
        };
        messageData.android = {
          notification: {
            sound: 'default',
            channelId: 'review_notifications',
          },
        };
      } else {
        messageData.apns = {
          payload: { aps: { 'content-available': 1 } },
        };
        messageData.android = {
          priority: 'high' as any,
        };
      }

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
        schedule: '0 6 * * *', // JST 6:00（1日1回一律配信）
        region: 'asia-northeast1',
        timeZone: 'Asia/Tokyo',
      },
      async () => {
        await sendNotificationsHandler();
      }
    );

function formatDate(date: Date): string {
  const y = date.getFullYear();
  const m = String(date.getMonth() + 1).padStart(2, '0');
  const d = String(date.getDate()).padStart(2, '0');
  return `${y}-${m}-${d}`;
}
