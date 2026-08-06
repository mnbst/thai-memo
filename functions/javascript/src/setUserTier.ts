/**
 * setUserTier.ts — 管理者が任意ユーザーの tier を切り替える callable
 *
 * 用途: サポート対応・キャンペーン手動付与・検証。
 * 呼び出せるのは custom claim `admin: true` を持つユーザー、または
 * 環境変数 ADMIN_UIDS（カンマ区切り）に含まれる uid のみ。
 * tier はクライアントから直接書けない（firestore.rules で禁止）ため、
 * 切り替えは必ずこの関数を通す。
 *
 * リクエスト: { uid? , email?, tier: 'free'|'premium', duration_days?, reason?, force? }
 *   uid か email のどちらか必須。duration_days 省略時は 30 日、0 で無期限。
 * レスポンス: { uid, tier, previous_tier, expires_at }
 */
import * as functions from 'firebase-functions/v2';
import * as admin from 'firebase-admin';
import { applyTier, TierError, Tier, DEFAULT_GRANT_DAYS } from './services/tierService';

/** 環境変数 ADMIN_UIDS（カンマ区切り）の許可リスト */
function adminUids(): string[] {
  return (process.env.ADMIN_UIDS || '')
    .split(',')
    .map((s) => s.trim())
    .filter((s) => s.length > 0);
}

function assertAdmin(auth: { uid: string; token: Record<string, unknown> } | undefined): string {
  if (!auth?.uid) {
    throw new functions.https.HttpsError('unauthenticated', '認証が必要です');
  }
  const isAdmin = auth.token?.admin === true || adminUids().includes(auth.uid);
  if (!isAdmin) {
    console.warn(`setUserTier: 権限のない呼び出し uid=${auth.uid}`);
    throw new functions.https.HttpsError('permission-denied', '管理者権限が必要です');
  }
  return auth.uid;
}

export const setUserTier = functions.https.onCall(
  {
    region: 'asia-northeast1',
    timeoutSeconds: 60,
    memory: '256MiB',
  },
  async (request) => {
    const actor = assertAdmin(request.auth);

    const {
      uid: rawUid,
      email,
      tier,
      duration_days: durationDays,
      reason,
      force,
    } = request.data as {
      uid?: string;
      email?: string;
      tier?: string;
      duration_days?: number;
      reason?: string;
      force?: boolean;
    };

    if (tier !== 'free' && tier !== 'premium') {
      throw new functions.https.HttpsError(
        'invalid-argument',
        'tier は free または premium を指定してください'
      );
    }
    if (!rawUid && !email) {
      throw new functions.https.HttpsError(
        'invalid-argument',
        'uid または email が必要です'
      );
    }
    if (
      durationDays !== undefined &&
      (typeof durationDays !== 'number' || durationDays < 0 || durationDays > 3650)
    ) {
      throw new functions.https.HttpsError(
        'invalid-argument',
        'duration_days は 0〜3650 の数値で指定してください'
      );
    }

    // email 指定はサポート対応用（問い合わせはメールアドレスで来る）
    let uid = rawUid;
    if (!uid && email) {
      try {
        uid = (await admin.auth().getUserByEmail(email)).uid;
      } catch {
        throw new functions.https.HttpsError(
          'not-found',
          `該当ユーザーが見つかりません: ${email}`
        );
      }
    }

    try {
      const result = await applyTier({
        uid: uid as string,
        tier: tier as Tier,
        durationDays: durationDays ?? DEFAULT_GRANT_DAYS,
        source: 'admin',
        actor,
        reason,
        force: force === true,
      });
      return {
        uid: result.uid,
        tier: result.tier,
        previous_tier: result.previousTier,
        expires_at: result.expiresAt,
      };
    } catch (e) {
      if (e instanceof TierError) {
        throw new functions.https.HttpsError(e.code, e.message);
      }
      console.error('setUserTier failed', e);
      throw new functions.https.HttpsError('internal', 'tier の更新に失敗しました');
    }
  }
);
