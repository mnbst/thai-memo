import * as functions from 'firebase-functions/v2';
import * as admin from 'firebase-admin';
import { isDevOnly } from './config/environment';
import { formatDate, nowJST } from './utils/formatDate';
import { DEFAULT_SENTENCES } from './constants/defaultQuizQuestions';

const db = admin.firestore();

const SRS_DAYS = [1, 3, 7, 30];

const MAX_REVIEW_SENTENCES = 20;
const MAX_PER_INTERVAL = 5;
const CONCURRENCY = 5;

/**
 * notificationBatchHandler - 深夜バッチ（JST 0:00）
 *
 * 全ユーザーのreview_queueを再生成する。
 * 1. review_queueコレクションを全削除
 * 2. 全ユーザーを5件ずつ並行処理（processUser）
 * 3. 30日以上前の例文をFirestoreから削除（cleanOldSentences）
 *
 * スケジュール: JST 0:00（prod/tester） / HTTP手動実行（dev）
 * タイムアウト: 1800秒
 */
async function notificationBatchHandler() {
  console.log('notificationBatch started');

  await deleteCollection('review_queue');

  const usersSnapshot = await db.collection('users').get();

  if (usersSnapshot.empty) {
    console.log('No users found');
    return;
  }

  const jstNow = nowJST();
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

  await cleanOldSentences();

  console.log(`notificationBatch completed: users_queued=${totalQueued}`);
}

/**
 * processUser - ユーザー単位のreview_queue生成
 *
 * selectSentencesBySRSで例文を選出し、review_queueに1ドキュメント保存。
 * 選出0件の場合はスキップ（false返却）。
 */
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

/**
 * selectSentencesBySRS - SRSベースの例文選出（最大20件）
 *
 * ユーザーの全例文を取得し、以下のロジックで最大20件を選出:
 *   SRS各間隔（1,3,7,30日）ごとに:
 *     1. ジャスト該当日（±0日）から最大5件取得
 *     2. 5件未満なら±1日の範囲からランダム補填して5件にする
 *   全間隔合計で20件未満なら:
 *     3. 上記に該当しないユーザー例文からランダム補充
 *     4. デフォルト例文（21件）からランダム補充
 */

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

  // 各経過日数を事前計算（JST基準）
  const jstNowMs = jstNow.getTime();
  const docsWithDays = allSentencesSnapshot.docs.map(doc => {
    const createdAt = doc.data().created_at?.toDate();
    let diffDays = -1;
    if (createdAt) {
      const jstCreated = new Date(createdAt.toLocaleString('en-US', { timeZone: 'Asia/Tokyo' }));
      diffDays = Math.floor((jstNowMs - jstCreated.getTime()) / (24 * 60 * 60 * 1000));
    }
    return { doc, diffDays };
  });

  // SRS各間隔: ジャスト該当日から最大5件 → 不足分は±1日からランダム補填
  for (const days of SRS_DAYS) {
    if (selected.length >= MAX_REVIEW_SENTENCES) break;

    // ジャスト該当日（±0日）
    const exact = docsWithDays.filter(d =>
      !usedIds.has(d.doc.id) && d.diffDays === days
    );
    const take = Math.min(MAX_PER_INTERVAL, exact.length, MAX_REVIEW_SENTENCES - selected.length);
    for (let i = 0; i < take; i++) {
      selected.push({ id: exact[i].doc.id, data: exact[i].doc.data(), srsInterval: days });
      usedIds.add(exact[i].doc.id);
    }

    // 5件未満なら±1日の範囲からランダム補填
    const needed = Math.min(MAX_PER_INTERVAL - take, MAX_REVIEW_SENTENCES - selected.length);
    if (needed > 0) {
      const nearby = docsWithDays
        .filter(d => !usedIds.has(d.doc.id) && d.diffDays >= days - 1 && d.diffDays <= days + 1)
        .sort(() => Math.random() - 0.5);
      for (let i = 0; i < Math.min(needed, nearby.length); i++) {
        selected.push({ id: nearby[i].doc.id, data: nearby[i].doc.data(), srsInterval: days });
        usedIds.add(nearby[i].doc.id);
      }
    }
  }

  // 優先度5: ユーザー例文からランダム補充
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

  // 優先度6: デフォルト例文から補充
  if (selected.length < MAX_REVIEW_SENTENCES) {
    const defaults = [...DEFAULT_SENTENCES]
      .sort(() => Math.random() - 0.5);

    for (const s of defaults) {
      if (selected.length >= MAX_REVIEW_SENTENCES) break;
      if (usedIds.has(s.sentence_id)) continue;
      selected.push({
        id: s.sentence_id,
        data: {
          thai_text: s.thai_text,
          pronunciation: s.pronunciation,
          japanese_translation: s.japanese_translation,
          word_breakdown: [],
        },
        srsInterval: 0,
      });
      usedIds.add(s.sentence_id);
    }
  }

  return selected;
}

/**
 * cleanOldSentences - 30日以上前の例文をFirestoreから一括削除
 */
async function cleanOldSentences(): Promise<void> {
  // JST基準で30日前の0:00をUTCに変換してFirestoreクエリ
  const jstNow = nowJST();
  const thirtyDaysAgo = new Date(jstNow);
  thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 30);
  thirtyDaysAgo.setHours(0, 0, 0, 0);
  // JST 0:00 = UTC前日15:00 なのでUTCに変換
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
