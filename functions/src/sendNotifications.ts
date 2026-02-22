import * as functions from 'firebase-functions/v2';
import * as admin from 'firebase-admin';
import { isDev } from './config/environment';

const db = admin.firestore();

/**
 * 毎時配信（JST 8:00〜18:00）: notification_queue から該当時刻分を取得しFCM送信
 */
export const sendNotifications = functions.scheduler.onSchedule(
  {
    schedule: '0 8-18 * * *', // JST 8:00-18:00（毎時）
    region: 'asia-northeast1',
    timeZone: 'Asia/Tokyo',
  },
  async () => {
    const now = new Date();
    const jstHour = (now.getUTCHours() + 9) % 24;
    const jstNow = new Date(now.getTime() + 9 * 60 * 60 * 1000);
    const today = formatDate(jstNow);

    console.log(`sendNotifications started: date=${today}, hour=${jstHour}`);

    // 該当時刻の未送信キューを取得
    const queueSnapshot = await db.collection('notification_queue')
      .where('scheduled_date', '==', today)
      .where('scheduled_hour', '==', jstHour)
      .where('sent', '==', false)
      .get();

    if (queueSnapshot.empty) {
      console.log('No notifications to send');
      return;
    }

    let sentCount = 0;
    let failCount = 0;

    for (const queueDoc of queueSnapshot.docs) {
      const data = queueDoc.data();

      try {
        // ユーザーのFCMトークンを取得
        const userDoc = await db.collection('users').doc(data.uid).get();
        const userData = userDoc.data();

        if (!userData?.fcm_token || !userData?.notification_enabled) {
          await queueDoc.ref.update({ sent: true });
          continue;
        }

        // dev環境ではFCM実送信をスキップ
        if (isDev()) {
          console.log(`[DEV] Skipping FCM send to ${data.uid}: ${data.title} - ${data.body}`);
        } else {
          await admin.messaging().send({
            token: userData.fcm_token,
            notification: {
              title: data.title,
              body: data.body,
            },
            data: {
              type: 'review',
              thai_text: data.thai_text || '',
              pronunciation: data.pronunciation || '',
              japanese_translation: data.japanese_translation || '',
              review_notes: data.review_notes || '',
            },
            apns: {
              payload: {
                aps: { sound: 'default' },
              },
            },
            android: {
              notification: {
                sound: 'default',
                channelId: 'review_notifications',
              },
            },
          });
        }

        await queueDoc.ref.update({ sent: true });
        sentCount++;
      } catch (error: any) {
        // 無効なトークンの場合はトークンを削除
        if (
          error?.code === 'messaging/invalid-registration-token' ||
          error?.code === 'messaging/registration-token-not-registered'
        ) {
          await db.collection('users').doc(data.uid).update({
            fcm_token: admin.firestore.FieldValue.delete(),
          });
          await queueDoc.ref.update({ sent: true });
        }

        console.error(`Failed to send notification to ${data.uid}:`, error);
        failCount++;
      }
    }

    console.log(`sendNotifications completed: sent=${sentCount}, failed=${failCount}`);
  }
);

function formatDate(date: Date): string {
  const y = date.getFullYear();
  const m = String(date.getMonth() + 1).padStart(2, '0');
  const d = String(date.getDate()).padStart(2, '0');
  return `${y}-${m}-${d}`;
}
