/**
 * dailyBatch.ts — 深夜バッチ処理（クォータリセット + 古い例文削除）
 *
 * 毎日 JST 0:00 に実行され、以下を行う:
 *   1. ユーザーごとの日次クォータをリセット
 *   2. ユーザーの利用時間帯を分析して scheduled_time を更新
 *   3. 30日以上前の古い例文を削除
 *
 * ※ SRSベースの復習例文選出は generateQuiz でリアルタイムに実行される
 *
 * dev環境: HTTPトリガー / tester・prod環境: Cloud Scheduler
 */
import * as functions from 'firebase-functions/v2';
import * as admin from 'firebase-admin';
import { isDevOnly } from './config/environment';
import { nowJST } from './utils/formatDate';
import {
  FREE_DAILY_SENTENCES, FREE_DAILY_QUIZZES,
  PREMIUM_DAILY_SENTENCES, PREMIUM_DAILY_QUIZZES,
} from './constants/quota';

const db = admin.firestore();

const CONCURRENCY = 5;
const DEFAULT_SCHEDULED_TIME = '08:00';
/** 配信可能時間帯（JST） */
const MIN_HOUR = 8;
const MAX_HOUR = 20;

async function dailyBatchHandler() {
  console.log('dailyBatch started');

  const usersSnapshot = await db.collection('users').get();
  if (usersSnapshot.empty) {
    console.log('No users found');
    return;
  }

  // CONCURRENCY件ずつ並行処理。allSettledで一部失敗しても継続
  const users = usersSnapshot.docs;
  for (let i = 0; i < users.length; i += CONCURRENCY) {
    const chunk = users.slice(i, i + CONCURRENCY);
    await Promise.allSettled(
      chunk.map(async (userDoc) => {
        await updateScheduledTime(userDoc.id);
        await resetQuota(userDoc);
      })
    );
  }

  await cleanOldSentences();
  console.log('dailyBatch completed');
}

/** tierに応じて remaining_sentences / remaining_quizzes を日次リセット */
async function resetQuota(
  userDoc: FirebaseFirestore.QueryDocumentSnapshot
): Promise<void> {
  const userData = userDoc.data() || {};
  const tier: string = userData.tier || 'free';
  const isPremium = tier === 'premium';

  await db.collection('users').doc(userDoc.id).set(
    {
      remaining_sentences: isPremium ? PREMIUM_DAILY_SENTENCES : FREE_DAILY_SENTENCES,
      remaining_quizzes: isPremium ? PREMIUM_DAILY_QUIZZES : FREE_DAILY_QUIZZES,
    },
    { merge: true }
  );
}

/** 例文生成履歴から最頻利用時間帯を30分単位で算出し scheduled_time に保存 */
async function updateScheduledTime(uid: string): Promise<void> {
  const sentencesSnapshot = await db
    .collection('users').doc(uid)
    .collection('sentences')
    .orderBy('created_at', 'desc')
    .limit(50)
    .get();

  let scheduledTime = DEFAULT_SCHEDULED_TIME;

  if (!sentencesSnapshot.empty) {
    const slotCounts = new Map<string, number>();

    for (const doc of sentencesSnapshot.docs) {
      const createdAt = doc.data().created_at?.toDate();
      if (!createdAt) continue;

      const jstStr = createdAt.toLocaleString('en-US', { timeZone: 'Asia/Tokyo' });
      const jstDate = new Date(jstStr);
      const hour = jstDate.getHours();
      const minute = jstDate.getMinutes() < 30 ? 0 : 30;

      const slot = `${String(hour).padStart(2, '0')}:${String(minute).padStart(2, '0')}`;
      slotCounts.set(slot, (slotCounts.get(slot) || 0) + 1);
    }

    if (slotCounts.size > 0) {
      let maxSlot = DEFAULT_SCHEDULED_TIME;
      let maxCount = 0;
      for (const [slot, count] of slotCounts) {
        if (count > maxCount) {
          maxCount = count;
          maxSlot = slot;
        }
      }

      const slotHour = parseInt(maxSlot.split(':')[0], 10);
      if (slotHour < MIN_HOUR) {
        scheduledTime = `${String(MIN_HOUR).padStart(2, '0')}:00`;
      } else if (slotHour >= MAX_HOUR) {
        scheduledTime = `${String(MAX_HOUR).padStart(2, '0')}:00`;
      } else {
        scheduledTime = maxSlot;
      }
    }
  }

  await db.collection('users').doc(uid).set(
    { scheduled_time: scheduledTime },
    { merge: true }
  );
}

/** 30日以上前の例文を全ユーザーからバッチ削除 */
async function cleanOldSentences(): Promise<void> {
  const jstNow = nowJST();
  const thirtyDaysAgo = new Date(jstNow);
  thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 30);
  thirtyDaysAgo.setHours(0, 0, 0, 0);
  // JST→UTC変換（Firestoreクエリ用）
  const cutoffUtc = new Date(thirtyDaysAgo.getTime() - 9 * 60 * 60 * 1000);

  const usersSnapshot = await db.collection('users').get();

  for (const userDoc of usersSnapshot.docs) {
    const oldSentences = await db
      .collection('users').doc(userDoc.id)
      .collection('sentences')
      .where('created_at', '<', admin.firestore.Timestamp.fromDate(cutoffUtc))
      .get();

    if (oldSentences.empty) continue;

    const batch = db.batch();
    for (const doc of oldSentences.docs) {
      batch.delete(doc.ref);
    }
    await batch.commit();
  }
}

/** dev: HTTPトリガー / tester・prod: Cloud Scheduler (JST 0:00) */
export const dailyBatch = isDevOnly()
  ? functions.https.onRequest({
    region: 'asia-northeast1',
    timeoutSeconds: 1800,
  }, async (_req, res) => {
    await dailyBatchHandler();
    res.status(200).send('ok');
  })
  : functions.scheduler.onSchedule(
    {
      schedule: '0 0 * * *', // JST 0:00
      region: 'asia-northeast1',
      timeZone: 'Asia/Tokyo',
      timeoutSeconds: 1800,
    },
    async () => {
      await dailyBatchHandler();
    }
  );
