import * as functions from 'firebase-functions/v2';
import * as admin from 'firebase-admin';
import { isDevOnly } from './config/environment';
import { formatDate } from './utils/formatDate';

const db = admin.firestore();

const SRS_INTERVALS = [
  { days: 1, tolerance: 0, priority: 1 },
  { days: 3, tolerance: 1, priority: 2 },
  { days: 7, tolerance: 1, priority: 3 },
  { days: 30, tolerance: 1, priority: 4 },
];

const MAX_REVIEW_SENTENCES = 5;
const CONCURRENCY = 5;

/**
 * 深夜バッチ（JST 0:00）: SRS例文選出 → review_queue保存
 */
async function notificationBatchHandler() {
  console.log('notificationBatch started');

  await deleteCollection('review_queue');

  const usersSnapshot = await db.collection('users').get();

  if (usersSnapshot.empty) {
    console.log('No users found');
    return;
  }

  const now = new Date();
  const jstNow = new Date(now.getTime() + 9 * 60 * 60 * 1000);
  const today = formatDate(jstNow);

  let totalQueued = 0;

  const users = usersSnapshot.docs;
  for (let i = 0; i < users.length; i += CONCURRENCY) {
    const chunk = users.slice(i, i + CONCURRENCY);
    const results = await Promise.allSettled(
      chunk.map(userDoc => processUser(userDoc.id, jstNow, today))
    );
    for (const r of results) {
      if (r.status === 'fulfilled' && r.value) totalQueued++;
    }
  }

  await cleanOldSentences(jstNow);

  console.log(`notificationBatch completed: users_queued=${totalQueued}`);
}

async function processUser(
  uid: string,
  jstNow: Date,
  today: string,
): Promise<boolean> {
  try {
    const selectedSentences = await selectSentencesBySRS(uid, jstNow);

    if (selectedSentences.length === 0) {
      return false;
    }

    await db.collection('review_queue').doc().set({
      uid,
      scheduled_date: today,
      sentences: selectedSentences.map(s => ({
        thai_text: s.data.thai_text,
        pronunciation: s.data.pronunciation,
        japanese_translation: s.data.japanese_translation,
        word_breakdown: s.data.word_breakdown || [],
      })),
      sentence_ids: selectedSentences.map(s => s.id),
      srs_intervals: selectedSentences.map(s => s.srsInterval),
      question_count: selectedSentences.length,
      sent: false,
      created_at: admin.firestore.FieldValue.serverTimestamp(),
    });

    return true;
  } catch (error) {
    console.error(`Error processing user ${uid}:`, error);
    return false;
  }
}

// --- SRS選出ロジック ---

interface SelectedSentence {
  id: string;
  data: FirebaseFirestore.DocumentData;
  srsInterval: number;
}

async function selectSentencesBySRS(
  uid: string,
  jstNow: Date
): Promise<SelectedSentence[]> {
  const selected: SelectedSentence[] = [];
  const usedIds = new Set<string>();

  const allSentencesSnapshot = await db
    .collection('users').doc(uid)
    .collection('sentences')
    .orderBy('created_at', 'desc')
    .get();

  if (allSentencesSnapshot.empty) return [];

  // 優先度1-4: SRS間隔
  for (const interval of SRS_INTERVALS) {
    if (selected.length >= MAX_REVIEW_SENTENCES) break;

    const candidates = allSentencesSnapshot.docs.filter(doc => {
      if (usedIds.has(doc.id)) return false;
      const createdAt = doc.data().created_at?.toDate();
      if (!createdAt) return false;
      const jstCreated = new Date(createdAt.getTime() + 9 * 60 * 60 * 1000);
      const diffDays = Math.floor(
        (jstNow.getTime() - jstCreated.getTime()) / (24 * 60 * 60 * 1000)
      );
      return diffDays >= interval.days - interval.tolerance &&
             diffDays <= interval.days + interval.tolerance;
    });

    const shuffled = candidates.sort(() => Math.random() - 0.5);
    const take = interval.priority === 1
      ? Math.max(Math.min(1, shuffled.length), Math.min(shuffled.length, MAX_REVIEW_SENTENCES - selected.length))
      : Math.min(shuffled.length, MAX_REVIEW_SENTENCES - selected.length);

    for (let i = 0; i < take && selected.length < MAX_REVIEW_SENTENCES; i++) {
      selected.push({ id: shuffled[i].id, data: shuffled[i].data(), srsInterval: interval.days });
      usedIds.add(shuffled[i].id);
    }
  }

  // 優先度5: ランダム補充
  if (selected.length < MAX_REVIEW_SENTENCES) {
    const remaining = allSentencesSnapshot.docs
      .filter(doc => !usedIds.has(doc.id))
      .sort(() => Math.random() - 0.5);

    for (const doc of remaining) {
      if (selected.length >= MAX_REVIEW_SENTENCES) break;
      selected.push({ id: doc.id, data: doc.data(), srsInterval: -1 });
      usedIds.add(doc.id);
    }
  }

  return selected;
}

async function cleanOldSentences(jstNow: Date): Promise<void> {
  const thirtyDaysAgo = new Date(jstNow);
  thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 30);
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

export const notificationBatch = isDevOnly()
  ? functions.https.onRequest({
      region: 'asia-northeast1',
      timeoutSeconds: 1800,
    }, async (_req, res) => {
      await notificationBatchHandler();
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
        await notificationBatchHandler();
      }
    );

async function deleteCollection(collectionPath: string): Promise<void> {
  const snapshot = await db.collection(collectionPath).get();
  if (snapshot.empty) return;

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
