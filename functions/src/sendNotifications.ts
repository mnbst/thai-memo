import * as functions from 'firebase-functions/v2';
import * as admin from 'firebase-admin';
import { isDev, isDevOnly } from './config/environment';

const db = admin.firestore();

/**
 * 通知配信: notification_queue から該当時刻分を取得しFCM送信
 * dev環境: onRequest（HTTP）で手動実行
 * tester/prod環境: onSchedule（Cloud Scheduler）で毎時実行（JST 8:00〜18:00）
 */
async function sendNotificationsHandler() {
    const now = new Date();
    const jstHour = (now.getUTCHours() + 9) % 24;
    const jstMinute = now.getUTCMinutes();
    const scheduledMinute = jstMinute >= 30 ? 30 : 0;
    const jstNow = new Date(now.getTime() + 9 * 60 * 60 * 1000);
    const today = formatDate(jstNow);

    console.log(`sendNotifications started: date=${today}, hour=${jstHour}, minute=${scheduledMinute}`);

    // dev: 未送信キューをすべて取得（即時送信）/ 他環境: 該当時刻分のみ
    let query = db.collection('notification_queue')
      .where('sent', '==', false);
    if (!isDev()) {
      query = query
        .where('scheduled_date', '==', today)
        .where('scheduled_hour', '==', jstHour)
        .where('scheduled_minute', '==', scheduledMinute);
    }
    const queueSnapshot = await query.get();

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

        if (!userData?.fcm_token) {
          console.log(`Skipped: uid=${data.uid} has no fcm_token`);
          await queueDoc.ref.update({ sent: true, skipped: true });
          continue;
        }

        const messageData: admin.messaging.Message = {
          token: userData.fcm_token,
          data: {
            type: 'review',
            thai_text: data.thai_text || '',
            pronunciation: data.pronunciation || '',
            japanese_translation: data.japanese_translation || '',
            review_notes: data.review_notes || '',
          },
        };

        // 通知ONの場合のみ表示通知を付与
        if (userData.notification_enabled) {
          messageData.notification = {
            title: data.title,
            body: data.body,
          };
          messageData.apns = {
            payload: {
              aps: { sound: 'default' },
            },
          };
          messageData.android = {
            notification: {
              sound: 'default',
              channelId: 'review_notifications',
            },
          };
        } else {
          // 通知OFF: サイレントでデータのみ配信
          messageData.apns = {
            payload: {
              aps: { 'content-available': 1 },
            },
          };
          messageData.android = {
            priority: 'high' as any,
          };
        }

        await admin.messaging().send(messageData);

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

// dev: HTTP手動実行 / tester・prod: Cloud Scheduler定期実行
export const sendNotifications = isDevOnly()
  ? functions.https.onRequest({ region: 'asia-northeast1' }, async (_req, res) => {
      await sendNotificationsHandler();
      res.status(200).send('ok');
    })
  : functions.scheduler.onSchedule(
      {
        schedule: '0,30 6-20 * * *', // JST 6:00-20:00（30分ごと）
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
