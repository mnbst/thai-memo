import * as functions from 'firebase-functions/v2';
import * as admin from 'firebase-admin';
import { GeminiService } from './services/geminiService';
import { getGeminiApiKey } from './services/secretManager';

const db = admin.firestore();

/**
 * 深夜バッチ（JST 3:00）: 復習通知キューを生成
 * 1. notification_queue を全削除（洗い替え）
 * 2. 各ユーザーの直近7日分の sentences.created_at から利用時間帯を推定
 * 3. 前日生成分の例文を対象に通知内容を作成
 * 4. notification_queue に書き込み
 * 5. 7日超過の sentences ドキュメントを削除
 */
export const notificationBatch = functions.scheduler.onSchedule(
  {
    schedule: '0 15 * * *', // UTC 15:00 = JST 0:00
    region: 'asia-northeast1',
    timeZone: 'Asia/Tokyo',
  },
  async () => {
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
        const scheduledHour = estimateActiveHour(sentencesSnapshot.docs);

        // 前日生成分の例文をフィルタ
        const yesterdaySentences = sentencesSnapshot.docs.filter(doc => {
          const createdAt = doc.data().created_at?.toDate();
          if (!createdAt) return false;
          const jstCreated = new Date(createdAt.getTime() + 9 * 60 * 60 * 1000);
          return formatDate(jstCreated) === formatDate(yesterday);
        });

        // 前日の例文がなければスキップ
        if (yesterdaySentences.length === 0) continue;

        // 通知キューに書き込み（最大3件）
        const targets = yesterdaySentences.slice(0, 3);
        const batch = db.batch();

        for (const sentenceDoc of targets) {
          const data = sentenceDoc.data();

          // LLMで補足解説を生成
          const reviewNotes = await geminiService.generateReviewNotes({
            thai_text: data.thai_text,
            pronunciation: data.pronunciation,
            japanese_translation: data.japanese_translation,
          });

          const queueRef = db.collection('notification_queue').doc();
          batch.set(queueRef, {
            uid,
            scheduled_hour: scheduledHour,
            scheduled_date: today,
            title: '復習タイム',
            body: `${data.thai_text}\n${data.japanese_translation}`,
            thai_text: data.thai_text,
            pronunciation: data.pronunciation,
            japanese_translation: data.japanese_translation,
            review_notes: reviewNotes,
            sentence_id: sentenceDoc.id,
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
);

/**
 * created_at の JST 時刻を集計し、最頻時間帯の2時間後を送信時刻として返す
 * 6-18の範囲に丸め、データ不足時はデフォルト12:00
 */
function estimateActiveHour(
  docs: FirebaseFirestore.QueryDocumentSnapshot[]
): number {
  const hourCounts = new Map<number, number>();

  for (const doc of docs) {
    const createdAt = doc.data().created_at?.toDate();
    if (!createdAt) continue;
    const jstHour = (createdAt.getUTCHours() + 9) % 24;
    hourCounts.set(jstHour, (hourCounts.get(jstHour) || 0) + 1);
  }

  if (hourCounts.size === 0) return 12;

  // 最頻時間帯を取得
  let maxHour = 12;
  let maxCount = 0;
  for (const [hour, count] of hourCounts) {
    if (count > maxCount) {
      maxCount = count;
      maxHour = hour;
    }
  }

  // 2時間後を送信時刻に（6-18の範囲に丸め）
  const sendHour = maxHour + 2;
  return Math.max(6, Math.min(18, sendHour));
}

function formatDate(date: Date): string {
  const y = date.getFullYear();
  const m = String(date.getMonth() + 1).padStart(2, '0');
  const d = String(date.getDate()).padStart(2, '0');
  return `${y}-${m}-${d}`;
}

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
