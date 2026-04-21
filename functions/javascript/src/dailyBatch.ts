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
 * 全登録単語に適用する。
 */
const P_DECAY_PER_DAY = 0.001;
const P_DECAY_MIN = 0.0;
const BATCH_LIMIT = 500;

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
        await resetQuota(userDoc);
        await decayUvmP(userDoc);
      })
    );
  }

  await cleanOldSentences();
  console.log('dailyBatch completed');
}

/** tierに応じて remaining_sentences / remaining_quizzes を日次リセット */
export async function resetQuota(
  userDoc: FirebaseFirestore.QueryDocumentSnapshot
): Promise<void> {
  const userData = userDoc.data() || {};
  const tier: string = userData.tier || 'free';
  const isPremium = tier === 'premium';
  const sentenceResetValue = isPremium ?
    PREMIUM_DAILY_SENTENCES :
    FREE_DAILY_SENTENCES;
  const quizResetValue = isPremium ?
    PREMIUM_DAILY_QUIZZES :
    FREE_DAILY_QUIZZES;
  const currentRemainingSentences =
    typeof userData.remaining_sentences === 'number' ?
      userData.remaining_sentences :
      0;
  const currentRemainingQuizzes =
    typeof userData.remaining_quizzes === 'number' ?
      userData.remaining_quizzes :
      0;
  const shouldPreserveInitialBonus = userData.is_first_generation === true;
  const shouldPreserveInitialQuizBonus =
    userData.is_first_quiz_generation === true;
  const remainingSentences = shouldPreserveInitialBonus ?
    Math.max(currentRemainingSentences, sentenceResetValue) :
    sentenceResetValue;
  const remainingQuizzes = shouldPreserveInitialQuizBonus ?
    Math.max(currentRemainingQuizzes, quizResetValue) :
    quizResetValue;

  await db.collection('users').doc(userDoc.id).set(
    {
      remaining_sentences: remainingSentences,
      remaining_quizzes: remainingQuizzes,
      daily_sentence_generated: false,
    },
    { merge: true }
  );
}

/** 全登録 UVM 語に対し P 減衰を適用（batch上限500件ずつcommit） */
async function decayUvmP(
  userDoc: FirebaseFirestore.QueryDocumentSnapshot,
): Promise<void> {
  const uvmRef = db.collection('users').doc(userDoc.id).collection('uvm');
  const uvmSnapshot = await uvmRef.get();
  if (uvmSnapshot.empty) return;

  let batch = db.batch();
  let writeCount = 0;
  let totalCount = 0;

  for (const doc of uvmSnapshot.docs) {
    const p: number = (doc.data() || {}).p ?? 0;
    if (p <= P_DECAY_MIN) continue;

    const newP = Math.max(P_DECAY_MIN, p - P_DECAY_PER_DAY);
    batch.update(doc.ref, { p: newP });
    writeCount++;
    totalCount++;

    if (writeCount >= BATCH_LIMIT) {
      await batch.commit();
      batch = db.batch();
      writeCount = 0;
    }
  }

  if (writeCount > 0) {
    await batch.commit();
  }

  if (totalCount > 0) {
    console.log(`decayUvmP: uid=${userDoc.id}, updated ${totalCount} word(s)`);
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

/** JST 12:00 にクォータのみリセット（P減衰・古い例文削除はなし） */
async function noonResetHandler() {
  console.log('noonReset started');

  const usersSnapshot = await db.collection('users').get();
  if (usersSnapshot.empty) {
    console.log('No users found');
    return;
  }

  const users = usersSnapshot.docs;
  for (let i = 0; i < users.length; i += CONCURRENCY) {
    const chunk = users.slice(i, i + CONCURRENCY);
    await Promise.allSettled(chunk.map((userDoc) => resetQuota(userDoc)));
  }

  console.log('noonReset completed');
}

/** dev: HTTPトリガー / tester・prod: Cloud Scheduler (JST 12:00) */
export const noonReset = isDevOnly()
  ? functions.https.onRequest({
    region: 'asia-northeast1',
    timeoutSeconds: 300,
  }, async (_req, res) => {
    await noonResetHandler();
    res.status(200).send('ok');
  })
  : functions.scheduler.onSchedule(
    {
      schedule: '0 12 * * *', // JST 12:00
      region: 'asia-northeast1',
      timeZone: 'Asia/Tokyo',
      timeoutSeconds: 300,
    },
    async () => {
      await noonResetHandler();
    }
  );
