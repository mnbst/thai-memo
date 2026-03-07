/**
 * sendNotifications.ts — 今日のタイ語例文の FCM 配信
 *
 * 「まいにちタイ語」アプリでは、深夜バッチ（dailyBatch）で生成された
 * review_queue のエントリから例文を1つ選び、FCM（Firebase Cloud Messaging）で
 * ユーザーにプッシュ通知を配信する。
 *
 * 通知にはタイ語例文（タイ文・発音・日本語訳）が含まれ、
 * タップするとアプリの例文詳細画面に遷移して内容を確認できる。
 * この機能は完全無料で提供される。
 *
 * 【処理フロー】
 * 1. review_queue から未送信（sent=false）のエントリを取得
 *    - dev環境: 未送信すべて / tester・prod環境: 当日分のみ
 * 2. 各エントリのユーザーの fcm_token と notification_enabled を確認
 *    - トークン未設定 or 通知無効 → スキップ（sent=true に更新）
 * 3. エントリからランダムに1つ例文を選び、FCM でプッシュ通知を送信
 *    - 成功時: sent=true に更新
 *    - トークン無効エラー時: fcm_token を削除してスキップ
 *
 * 【環境別動作】
 * - dev環境: HTTPリクエストで手動実行
 * - tester/prod環境: Cloud Scheduler で JST 8:00〜20:00 の間30分ごとに実行
 *
 * リージョン: asia-northeast1（東京）
 */
import * as functions from 'firebase-functions/v2';
import * as admin from 'firebase-admin';
import { isDev, isDevOnly } from './config/environment';
import { formatDate, nowJST } from './utils/formatDate';

/** Firestore インスタンス */
const db = admin.firestore();

/**
 * sendNotificationsHandler - 復習通知のFCM配信メイン処理
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
  // JST基準の現在日付を取得
  const jstNow = nowJST();
  const today = formatDate(jstNow);

  console.log(`sendNotifications started: date=${today}`);

  // review_queue から未送信のエントリを取得
  // dev環境: 日付を問わず未送信すべて / 他環境: 当日分のみ（スケジューラで毎日実行されるため）
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

  let sentCount = 0;   // 送信成功数
  let failCount = 0;   // 送信失敗数

  // 各 review_queue エントリに対してFCM通知を送信
  for (const queueDoc of queueSnapshot.docs) {
    const data = queueDoc.data();

    try {
      // ユーザーの情報を取得（FCMトークン、通知設定）
      const userDoc = await db.collection('users').doc(data.uid).get();
      const userData = userDoc.data();

      // FCMトークンが未設定のユーザーはスキップ（アプリ未起動など）
      if (!userData?.fcm_token) {
        console.log(`Skipped: uid=${data.uid} has no fcm_token`);
        await queueDoc.ref.update({ sent: true });
        continue;
      }

      // 通知が無効化されているユーザーはスキップ（設定画面でオフにした場合）
      if (!userData.notification_enabled) {
        console.log(`Skipped: uid=${data.uid} has notifications disabled`);
        await queueDoc.ref.update({ sent: true });
        continue;
      }

      // クイズの問題数を取得（通知のデータペイロードに含める）
      const questionCount = data.question_count || 0;

      // FCM メッセージを構築
      const messageData: admin.messaging.Message = {
        token: userData.fcm_token,
        // 通知本体（ユーザーに表示されるタイトルと本文）
        notification: {
          title: 'まいにちタイ語',
          body: '復習クイズが届きました📝 クイズタブからチャレンジ！',
        },
        // データペイロード（アプリ側で受信して処理に使う）
        data: {
          type: 'review',
          question_count: String(questionCount),
        },
        // iOS(APNs)固有の設定: 通知音を有効化
        apns: {
          payload: { aps: { sound: 'default' } },
        },
        // Android固有の設定: 通知音と通知チャンネルを指定
        android: {
          notification: {
            sound: 'default',
            channelId: 'review_notifications',
          },
        },
      };

      // FCM でプッシュ通知を送信
      await admin.messaging().send(messageData);
      // 送信成功時は sent=true に更新して再送を防ぐ
      await queueDoc.ref.update({ sent: true });
      sentCount++;
    } catch (error: any) {
      // FCMトークンが無効（アプリ削除、端末変更など）の場合は、
      // Firestore から fcm_token を削除して次回以降スキップされるようにする
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

/**
 * sendNotifications — Cloud Function のエクスポート
 *
 * 環境によって実行方法が異なる:
 * - dev環境: HTTP トリガー（手動で curl 等で実行）
 * - tester/prod環境: Cloud Scheduler で JST 8:00〜20:00 の間30分ごとに自動実行
 *   ユーザーのアクティブな時間帯に通知を届けるため、朝8時から夜8時まで配信する
 */
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
