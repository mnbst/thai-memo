import * as functions from 'firebase-functions/v2';
import * as admin from 'firebase-admin';
import { GeminiService } from './services/geminiService';
import { getGeminiApiKey } from './services/secretManager';
import { isDevOnly } from './config/environment';

const db = admin.firestore();

/**
 * 深夜バッチ: 復習通知キューを生成
 * dev環境: onRequest（HTTP）で手動実行
 * tester/prod環境: onSchedule（Cloud Scheduler）で定期実行（JST 0:00）
 */
async function notificationBatchHandler() {
  console.log('notificationBatch started');

    // 1. notification_queue を全削除
    await deleteCollection('notification_queue');

    // 2. 通知有効ユーザーを取得
    const usersSnapshot = await db.collection('users')
      .where('notification_enabled', '==', true)
      .get();

    if (usersSnapshot.empty) {
      console.log('No users with notifications enabled');
      return;
    }

    const now = new Date();
    const jstNow = new Date(now.getTime() + 9 * 60 * 60 * 1000);
    const today = formatDate(jstNow);

    // 前日（JST）
    const yesterday = new Date(jstNow);
    yesterday.setDate(yesterday.getDate() - 1);

    // 7日前（JST）
    const sevenDaysAgo = new Date(jstNow);
    sevenDaysAgo.setDate(sevenDaysAgo.getDate() - 7);

    // Gemini API初期化
    const apiKey = await getGeminiApiKey();
    const geminiService = new GeminiService(apiKey);

    let totalQueued = 0;
    let totalCleaned = 0;

    for (const userDoc of usersSnapshot.docs) {
      const uid = userDoc.id;

      try {
        // 直近7日分の sentences を取得（利用時間帯推定用）
        const sentencesSnapshot = await db
          .collection('users').doc(uid)
          .collection('sentences')
          .where('created_at', '>=', admin.firestore.Timestamp.fromDate(
            new Date(sevenDaysAgo.getTime() - 9 * 60 * 60 * 1000) // UTC に戻す
          ))
          .orderBy('created_at', 'desc')
          .get();

        if (sentencesSnapshot.empty) continue;

        // 利用時間帯を推定
        const { hour: scheduledHour, minute: scheduledMinute } = estimateActiveTime(sentencesSnapshot.docs);

        // 前日生成分の例文をフィルタ
        const yesterdaySentences = sentencesSnapshot.docs.filter(doc => {
          const createdAt = doc.data().created_at?.toDate();
          if (!createdAt) return false;
          const jstCreated = new Date(createdAt.getTime() + 9 * 60 * 60 * 1000);
          return formatDate(jstCreated) === formatDate(yesterday);
        });

        // 前日の例文がなければスキップ
        if (yesterdaySentences.length === 0) continue;

        // 前日分からランダムに最大3件を選択
        const shuffled = yesterdaySentences.sort(() => Math.random() - 0.5);
        const targets = shuffled.slice(0, 3);
        const batch = db.batch();

        // LLMで補足解説を並列生成
        const reviewNotesResults = await Promise.all(
          targets.map(doc => {
            const d = doc.data();
            return geminiService.generateReviewNotes({
              thai_text: d.thai_text,
              pronunciation: d.pronunciation,
              japanese_translation: d.japanese_translation,
            });
          })
        );

        for (let i = 0; i < targets.length; i++) {
          const data = targets[i].data();
          const queueRef = db.collection('notification_queue').doc();
          batch.set(queueRef, {
            uid,
            scheduled_hour: scheduledHour,
            scheduled_minute: scheduledMinute,
            scheduled_date: today,
            title: '昨日の復習',
            body: `${data.thai_text}\n${data.japanese_translation}`,
            thai_text: data.thai_text,
            pronunciation: data.pronunciation,
            japanese_translation: data.japanese_translation,
            review_notes: JSON.stringify(reviewNotesResults[i]),
            sentence_id: targets[i].id,
            sent: false,
            created_at: admin.firestore.FieldValue.serverTimestamp(),
          });
          totalQueued++;
        }

        await batch.commit();

        // 7日超過の sentences を削除
        const oldSentences = await db
          .collection('users').doc(uid)
          .collection('sentences')
          .where('created_at', '<', admin.firestore.Timestamp.fromDate(
            new Date(sevenDaysAgo.getTime() - 9 * 60 * 60 * 1000)
          ))
          .get();

        if (!oldSentences.empty) {
          const deleteBatch = db.batch();
          for (const doc of oldSentences.docs) {
            deleteBatch.delete(doc.ref);
            totalCleaned++;
          }
          await deleteBatch.commit();
        }
      } catch (error) {
        console.error(`Error processing user ${uid}:`, error);
      }
    }

    console.log(`notificationBatch completed: queued=${totalQueued}, cleaned=${totalCleaned}`);
}

/**
 * created_at の JST 時刻を集計し、最頻時間帯を30分単位に丸めて返す
 * 例: 17:40 → { hour: 17, minute: 30 }
 * 6:00-22:00の範囲に丸め、データ不足時はデフォルト12:00
 */
function estimateActiveTime(
  docs: FirebaseFirestore.QueryDocumentSnapshot[]
): { hour: number; minute: number } {
  // 30分スロット（0=0:00, 1=0:30, 2=1:00, ...）ごとにカウント
  const slotCounts = new Map<number, number>();

  for (const doc of docs) {
    const createdAt = doc.data().created_at?.toDate();
    if (!createdAt) continue;
    const jstHour = (createdAt.getUTCHours() + 9) % 24;
    const jstMinute = createdAt.getUTCMinutes();
    const slot = jstHour * 2 + (jstMinute >= 30 ? 1 : 0);
    slotCounts.set(slot, (slotCounts.get(slot) || 0) + 1);
  }

  if (slotCounts.size === 0) return { hour: 12, minute: 0 };

  // 最頻スロットを取得
  let maxSlot = 24; // 12:00
  let maxCount = 0;
  for (const [slot, count] of slotCounts) {
    if (count > maxCount) {
      maxCount = count;
      maxSlot = slot;
    }
  }

  let hour = Math.floor(maxSlot / 2);
  const minute = (maxSlot % 2) * 30;

  // 6:00-20:00の範囲に丸め
  if (hour < 6) { hour = 6; return { hour, minute: 0 }; }
  if (hour >= 20) { hour = 20; return { hour, minute: 0 }; }

  return { hour, minute };
}

function formatDate(date: Date): string {
  const y = date.getFullYear();
  const m = String(date.getMonth() + 1).padStart(2, '0');
  const d = String(date.getDate()).padStart(2, '0');
  return `${y}-${m}-${d}`;
}

// dev: HTTP手動実行 / tester・prod: Cloud Scheduler定期実行
export const notificationBatch = isDevOnly()
  ? functions.https.onRequest({ region: 'asia-northeast1' }, async (_req, res) => {
      await notificationBatchHandler();
      res.status(200).send('ok');
    })
  : functions.scheduler.onSchedule(
      {
        schedule: '0 15 * * *', // UTC 15:00 = JST 0:00
        region: 'asia-northeast1',
        timeZone: 'Asia/Tokyo',
      },
      async () => {
        await notificationBatchHandler();
      }
    );

async function deleteCollection(collectionPath: string): Promise<void> {
  const snapshot = await db.collection(collectionPath).get();
  if (snapshot.empty) return;

  // Firestore batch は最大500件
  const batchSize = 500;
  const docs = snapshot.docs;

  for (let i = 0; i < docs.length; i += batchSize) {
    const batch = db.batch();
    const chunk = docs.slice(i, i + batchSize);
    for (const doc of chunk) {
      batch.delete(doc.ref);
    }
    await batch.commit();
  }
}
