/**
 * dailyBatch.ts — 深夜バッチ処理
 *
 * 毎日 JST 0:00 に実行され、以下を行う:
 *   1. ユーザーごとの日次クォータをリセット
 *   2. UVM の P 値を減衰（estimated_vocab ± 20 帯域内のみ）
 *   3. 30日以上前の古い例文を削除
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

/**
 * UVM P値減衰の定数
 *
 * 例文選定では estimated_vocab ± 10 帯域内で P が最も低い語を選出する。
 * 新規（未登録）語は P=0.02 で扱うため、露出済みだが復習されていない語の
 * P を毎日 0.01 ずつ減衰させることで、放置された語が新語より優先されるようにする。
 * 減衰対象は estimated_vocab ± 20 に絞り、帯域外の語には影響しない。
 */
const DECAY_BAND_HALF = 20;
const P_DECAY_PER_DAY = 0.01;
const P_DECAY_MIN = 0.0;

/** GCSからfreq_rankを読み込みキャッシュする */
let freqRankCache: Record<string, number> | null = null;
async function getFreqRank(): Promise<Record<string, number>> {
  if (freqRankCache) return freqRankCache;
  const projectId = process.env.GCLOUD_PROJECT || process.env.GCP_PROJECT || '';
  const bucket = admin.storage().bucket(`${projectId}-uvm-data`);
  const [content] = await bucket.file('freq_rank_top10000.json').download();
  freqRankCache = JSON.parse(content.toString());
  return freqRankCache!;
}

/** freq_rank の逆引き (rank → word) を帯域内で生成 */
function getRankToWords(
  freqRank: Record<string, number>,
  bandLow: number,
  bandHigh: number,
): Set<string> {
  const words = new Set<string>();
  for (const [word, rank] of Object.entries(freqRank)) {
    if (rank >= bandLow && rank <= bandHigh) {
      words.add(word);
    }
  }
  return words;
}

async function dailyBatchHandler() {
  console.log('dailyBatch started');

  const usersSnapshot = await db.collection('users').get();
  if (usersSnapshot.empty) {
    console.log('No users found');
    return;
  }

  const freqRank = await getFreqRank();

  // CONCURRENCY件ずつ並行処理。allSettledで一部失敗しても継続
  const users = usersSnapshot.docs;
  for (let i = 0; i < users.length; i += CONCURRENCY) {
    const chunk = users.slice(i, i + CONCURRENCY);
    await Promise.allSettled(
      chunk.map(async (userDoc) => {
        await resetQuota(userDoc);
        await decayUvmP(userDoc, freqRank);
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
      daily_sentence_generated: false,
    },
    { merge: true }
  );
}

/** estimated_vocab ± 20 帯域内の UVM 語に対し、経過日数 × 0.01 の P 減衰を適用 */
async function decayUvmP(
  userDoc: FirebaseFirestore.QueryDocumentSnapshot,
  freqRank: Record<string, number>,
): Promise<void> {
  const userData = userDoc.data() || {};
  const estimatedVocab: number = userData.estimated_vocab ?? 0;

  const bandLow = Math.max(0, estimatedVocab - DECAY_BAND_HALF);
  const bandHigh = estimatedVocab + DECAY_BAND_HALF;
  const bandWords = getRankToWords(freqRank, bandLow, bandHigh);

  if (bandWords.size === 0) return;

  const uvmRef = db.collection('users').doc(userDoc.id).collection('uvm');

  const batch = db.batch();
  let writeCount = 0;

  for (const word of bandWords) {
    const docRef = uvmRef.doc(word);
    const snap = await docRef.get();
    if (!snap.exists) continue;

    const p: number = (snap.data() || {}).p ?? 0;
    if (p <= P_DECAY_MIN) continue;

    const newP = Math.max(P_DECAY_MIN, p - P_DECAY_PER_DAY);
    batch.update(docRef, { p: newP });
    writeCount++;
  }

  if (writeCount > 0) {
    await batch.commit();
    console.log(`decayUvmP: uid=${userDoc.id}, updated ${writeCount} word(s), band=[${bandLow},${bandHigh}]`);
  }
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
