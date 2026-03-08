/**
 * dailyBatch.ts — 深夜バッチ処理（復習キュー生成 + 古い例文削除）
 *
 * 毎日 JST 0:00 に実行され、以下を行う:
 *   1. review_queue を全削除→SRSベースで再生成
 *   2. 30日以上前の古い例文を削除
 *
 * dev環境: HTTPトリガー / tester・prod環境: Cloud Scheduler
 */
import * as functions from 'firebase-functions/v2';
import * as admin from 'firebase-admin';
import { isDevOnly } from './config/environment';
import { formatDate, nowJST } from './utils/formatDate';
import { DEFAULT_SENTENCES } from './constants/defaultQuizQuestions';
import {
  FREE_DAILY_SENTENCES, FREE_DAILY_QUIZZES,
  PREMIUM_DAILY_SENTENCES, PREMIUM_DAILY_QUIZZES,
} from './constants/quota';

const db = admin.firestore();

/**
 * SRS（Spaced Repetition System / 間隔反復）の復習間隔（日数）
 *
 * 学習した例文を「1日後 → 3日後 → 7日後 → 14日後 → 30日後」に再出題することで
 * 忘却曲線に沿った効率的な定着を狙う。
 * 例: 3/1に学習した例文 → 3/2(1日後), 3/4(3日後), 3/8(7日後), 3/15(14日後), 3/31(30日後) に復習対象
 */
const SRS_DAYS = [1, 3, 7, 14, 30];
/** 1日あたりの復習キュー最大例文数 */
const MAX_REVIEW_SENTENCES = 15;
/** 各SRS間隔から選出する最大例文数（5間隔 × 3問 = 最大15問） */
const MAX_PER_INTERVAL = 3;
const CONCURRENCY = 5;
const DEFAULT_SCHEDULED_TIME = '08:00';
/** 配信可能時間帯（JST） */
const MIN_HOUR = 8;
const MAX_HOUR = 20;

async function dailyBatchHandler() {
  console.log('dailyBatch started');

  await deleteCollection('review_queue');

  const usersSnapshot = await db.collection('users').get();
  if (usersSnapshot.empty) {
    console.log('No users found');
    return;
  }

  const jstNow = nowJST();
  const today = formatDate(jstNow);
  let totalQueued = 0;

  // CONCURRENCY件ずつ並行処理。allSettledで一部失敗しても継続
  const users = usersSnapshot.docs;
  for (let i = 0; i < users.length; i += CONCURRENCY) {
    const chunk = users.slice(i, i + CONCURRENCY);
    const results = await Promise.allSettled(
      chunk.map(async (userDoc) => {
        const queued = await processUser(userDoc.id, jstNow, today); // SRSベースで復習キューを生成
        await updateScheduledTime(userDoc.id); // 次回配信時刻を更新
        await resetQuota(userDoc); // デイリークォータをリセット
        return queued;
      })
    );
    for (const r of results) {
      if (r.status === 'fulfilled' && r.value) totalQueued++;
    }
  }

  await cleanOldSentences();
  console.log(`dailyBatch completed: users_queued=${totalQueued}`);
}

/** SRSで例文を選出し review_queue に保存。0件ならスキップ */
async function processUser(
  uid: string,
  jstNow: Date,
  today: string,
): Promise<boolean> {
  try {
    const selectedSentences = await selectSentencesBySRS(uid, jstNow);
    if (selectedSentences.length === 0) return false;

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
 * SRSベースの例文選出（最大20件）
 * 優先度: SRS該当日(±0) → ±1日補填 → 残り例文ランダム → デフォルト例文
 */
interface SelectedSentence {
  id: string;
  data: FirebaseFirestore.DocumentData;
  /**
   * この例文がどのSRS間隔で選ばれたかを示す値
   * -1: SRS対象外（ランダム補充）
   *  0: デフォルト例文（ユーザー例文が不足する新規ユーザー向け）
   *  1/3/7/30: 該当するSRS間隔（日数）
   */
  srsInterval: number;
}

/**
 * ユーザーの全例文からSRSアルゴリズムに基づいて復習対象を選出する。
 *
 * 選出の優先順位:
 *  ① SRS間隔にジャスト該当する例文（1日前/3日前/7日前/30日前に学習したもの）
 *  ② ①で不足する場合、±1日の範囲からランダム補填（学習日のズレを吸収）
 *  ③ それでも20問に満たない場合、SRS対象外の例文からランダム補充
 *  ④ ユーザーの例文自体が少ない場合、デフォルト例文で補充
 */
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

  // 各例文の作成日からの経過日数を事前計算（SRS間隔との照合に使用）
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

  // ① SRS各間隔ごとに選出（ジャスト該当日 → ②±1日補填）
  for (const days of SRS_DAYS) {
    if (selected.length >= MAX_REVIEW_SENTENCES) break;

    const exact = docsWithDays.filter(d =>
      !usedIds.has(d.doc.id) && d.diffDays === days
    ).sort(() => Math.random() - 0.5);
    const take = Math.min(MAX_PER_INTERVAL, exact.length, MAX_REVIEW_SENTENCES - selected.length);
    for (let i = 0; i < take; i++) {
      selected.push({ id: exact[i].doc.id, data: exact[i].doc.data(), srsInterval: days });
      usedIds.add(exact[i].doc.id);
    }

    // ±1日の範囲からランダム補填
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

  // ③ SRS対象外のユーザー例文からランダム補充
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

  // ④ デフォルト例文から補充（新規ユーザー等で不足する場合）
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

/** コレクションの全ドキュメントを500件ずつバッチ削除 */
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
