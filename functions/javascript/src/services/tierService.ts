/**
 * tierService.ts — tier 手動付与の中核ロジック
 *
 * setUserTier（管理者用 callable）から使用。将来のクーポン／キャンペーン
 * 引き換え（ユーザー自身がコードを入力して premium になる導線）も、
 * コードを検証したうえで applyTier を呼ぶだけで済むよう分離してある。
 *
 * ストア購入由来の subscription は上書きしない（force 指定時のみ許可）。
 * premium 付与は expires_at を必ず持たせ、subscriptionStatus / dailyBatch の
 * 既存の期限切れ処理でそのまま free に戻るようにする（無期限は days=0 のみ）。
 */
import * as admin from 'firebase-admin';
import {
  FREE_DAILY_SENTENCES,
  FREE_DAILY_QUIZZES,
  PREMIUM_DAILY_SENTENCES,
  PREMIUM_DAILY_QUIZZES,
} from '../constants/quota';

const db = admin.firestore();

/** 手動付与の subscription.platform 値（ストア購入と区別する） */
export const MANUAL_PLATFORM = 'manual';

/** premium 付与時のデフォルト期間 */
export const DEFAULT_GRANT_DAYS = 30;

export type Tier = 'free' | 'premium';

export interface ApplyTierParams {
  /** 対象ユーザーの uid */
  uid: string;
  tier: Tier;
  /** premium 付与期間（日）。0 で無期限。free 指定時は無視 */
  durationDays?: number;
  /** 付与の出所。'admin' / 'coupon:<code>' など */
  source: string;
  /** 実行者の uid（監査ログ用）。バッチ等で不在なら null */
  actor: string | null;
  /** 監査ログに残す任意メモ */
  reason?: string;
  /** ストア購入由来の subscription を上書きしてよいか */
  force?: boolean;
}

export interface ApplyTierResult {
  uid: string;
  tier: Tier;
  previousTier: Tier;
  expiresAt: string | null;
}

export class TierError extends Error {
  constructor(
    readonly code: 'not-found' | 'failed-precondition',
    message: string
  ) {
    super(message);
  }
}

/**
 * ユーザーの tier を書き換え、監査ログを tier_grants に残す。
 * tier が変わった場合のみクォータをリセットする（既存 CF と同じ方針）。
 */
export async function applyTier(
  params: ApplyTierParams
): Promise<ApplyTierResult> {
  const { uid, tier, source, actor, reason, force = false } = params;
  const durationDays = params.durationDays ?? DEFAULT_GRANT_DAYS;

  const userRef = db.collection('users').doc(uid);
  const userDoc = await userRef.get();
  if (!userDoc.exists) {
    throw new TierError('not-found', `ユーザーが存在しません: ${uid}`);
  }

  const userData = userDoc.data() || {};
  const previousTier: Tier = userData.tier === 'premium' ? 'premium' : 'free';
  const subscription = userData.subscription ?? {};
  const isStoreSubscription =
    subscription.platform === 'ios' || subscription.platform === 'android';
  const isStoreActive =
    isStoreSubscription &&
    (subscription.status === 'active' ||
      subscription.status === 'grace_period');

  if (isStoreActive && !force) {
    throw new TierError(
      'failed-precondition',
      `ストア購入が有効なユーザーです（platform=${subscription.platform}, ` +
        `status=${subscription.status}）。上書きするには force=true を指定してください`
    );
  }

  const tierChanged = previousTier !== tier;
  const quotaUpdate = tierChanged ?
    {
      remaining_sentences: tier === 'premium' ?
        PREMIUM_DAILY_SENTENCES :
        FREE_DAILY_SENTENCES,
      remaining_quizzes: tier === 'premium' ?
        PREMIUM_DAILY_QUIZZES :
        FREE_DAILY_QUIZZES,
    } :
    {};

  const expiresAt =
    tier === 'premium' && durationDays > 0 ?
      admin.firestore.Timestamp.fromMillis(
        Date.now() + durationDays * 24 * 60 * 60 * 1000
      ) :
      null;

  // ストア購入の subscription は触らない（force 時のみ手動値で上書き）。
  // merge:true はネストしたマップもフィールド単位でマージするため、
  // purchase_token / original_transaction_id は保持される。
  const subscriptionUpdate =
    isStoreSubscription && !force ?
      {} :
      {
        subscription: {
          platform: MANUAL_PLATFORM,
          product_id: null,
          source,
          status: tier === 'premium' ? 'active' : 'expired',
          expires_at: expiresAt,
          auto_renewing: false,
          updated_at: admin.firestore.FieldValue.serverTimestamp(),
        },
      };

  await userRef.set(
    {
      tier,
      ...quotaUpdate,
      ...subscriptionUpdate,
    },
    { merge: true }
  );

  await db.collection('tier_grants').add({
    uid,
    tier,
    previous_tier: previousTier,
    duration_days: tier === 'premium' ? durationDays : null,
    expires_at: expiresAt,
    source,
    actor,
    reason: reason ?? null,
    forced: force,
    created_at: admin.firestore.FieldValue.serverTimestamp(),
  });

  console.log(
    `applyTier: uid=${uid} ${previousTier}->${tier} source=${source} ` +
      `actor=${actor ?? 'none'} expires_at=${expiresAt?.toDate().toISOString() ?? 'none'}`
  );

  return {
    uid,
    tier,
    previousTier,
    expiresAt: expiresAt?.toDate().toISOString() ?? null,
  };
}
