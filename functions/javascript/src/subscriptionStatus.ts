/**
 * subscriptionStatus.ts — サブスクリプション期限切れバッチ
 *
 * 1日1回実行し、有効期限が過ぎた premium ユーザーを free に更新する。
 * Apple / Google Play の通知が遅延・未着だった場合のフォールバック処理。
 *
 * 対象: tier='premium' かつ subscription.expires_at < now
 *       かつ subscription.status が 'active' / 'canceled'、または
 *       'grace_period' で期限から GRACE_PERIOD_MAX_MS を過ぎたもの
 *
 * dev環境: HTTPトリガー / tester・prod環境: Cloud Scheduler (毎日0時0分)
 * リージョン: asia-northeast1（東京）
 */
import * as functions from 'firebase-functions/v2';
import * as admin from 'firebase-admin';
import { isDevOnly } from './config/environment';
import { GRACE_PERIOD_MAX_MS } from './constants/subscription';

const db = admin.firestore();

const CONCURRENCY = 5;

async function subscriptionStatusHandler() {
  console.log('subscriptionStatus started');

  const now = admin.firestore.Timestamp.now();

  // 期限切れ対象: premium かつ expires_at が過去
  const snapshot = await db
    .collection('users')
    .where('tier', '==', 'premium')
    .where('subscription.expires_at', '<', now)
    .get();

  if (snapshot.empty) {
    console.log('No expired subscriptions found');
    return;
  }

  console.log(`Found ${snapshot.size} expired users`);

  const users = snapshot.docs;
  let updatedCount = 0;

  for (let i = 0; i < users.length; i += CONCURRENCY) {
    const chunk = users.slice(i, i + CONCURRENCY);
    const results = await Promise.allSettled(
      chunk.map(async (userDoc) => {
        const subscription = userDoc.data()?.subscription ?? {};
        const status = subscription.status;
        if (status === 'grace_period') {
          // 猶予期間は期限超過が前提。通知を取りこぼした場合に premium が
          // 永久に残らないよう、猶予の上限を過ぎたものだけ落とす
          const expiresAtMs: number | undefined =
            subscription.expires_at?.toMillis?.();
          if (
            typeof expiresAtMs !== 'number' ||
            Date.now() - expiresAtMs <= GRACE_PERIOD_MAX_MS
          ) {
            return;
          }
        } else if (status !== 'active' && status !== 'canceled') {
          return;
        }

        await userDoc.ref.set(
          {
            tier: 'free',
            subscription: {
              status: 'expired',
              updated_at: admin.firestore.FieldValue.serverTimestamp(),
            },
          },
          { merge: true }
        );
        updatedCount++;
        console.log(`Expired: uid=${userDoc.id}, status=${status}`);
      })
    );

    results.forEach((r, idx) => {
      if (r.status === 'rejected') {
        console.error(`Failed to update uid=${chunk[idx].id}:`, r.reason);
      }
    });
  }

  console.log(`subscriptionStatus completed: updated=${updatedCount}`);
}

/** dev: HTTPトリガー / tester・prod: Cloud Scheduler (毎日0時0分) */
export const subscriptionStatus = isDevOnly()
  ? functions.https.onRequest(
    {
      region: 'asia-northeast1',
      timeoutSeconds: 300,
    },
    async (_req, res) => {
      await subscriptionStatusHandler();
      res.status(200).send('ok');
    }
  )
  : functions.scheduler.onSchedule(
    {
      schedule: '0 0 * * *', // 毎日0時0分
      region: 'asia-northeast1',
      timeZone: 'Asia/Tokyo',
      timeoutSeconds: 300,
    },
    async () => {
      await subscriptionStatusHandler();
    }
  );
