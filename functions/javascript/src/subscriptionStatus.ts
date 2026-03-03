import * as functions from 'firebase-functions/v2';
import * as admin from 'firebase-admin';

const db = admin.firestore();

/**
 * subscriptionStatus - サブスクリプション状態の取得
 *
 * Firestoreからサブスク状態を読み取り、有効期限チェック後に返却する。
 * 期限切れの場合はFirestoreも自動更新する。
 */
export const subscriptionStatus = functions.https.onCall(
  {
    region: 'asia-northeast1',
  },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new functions.https.HttpsError('unauthenticated', '認証が必要です');
    }

    const userRef = db.collection('users').doc(uid);
    const userDoc = await userRef.get();
    const userData = userDoc.data();

    if (!userData?.subscription) {
      return { plan: 'free', expires_at: null };
    }

    const subscription = userData.subscription;
    const expiresAt = subscription.expires_at?.toDate() as Date | undefined;
    const now = new Date();

    // 期限切れチェック: active だが有効期限が過ぎている場合は expired に更新
    if (
      expiresAt &&
      expiresAt < now &&
      subscription.status === 'active'
    ) {
      await userRef.set(
        {
          tier: 'free',
          subscription: {
            status: 'expired',
            updated_at: admin.firestore.FieldValue.serverTimestamp(),
          },
        },
        { merge: true }
      );

      return { plan: 'free', expires_at: expiresAt.toISOString() };
    }

    const plan = userData.tier === 'premium' ? 'premium' : 'free';
    return {
      plan,
      expires_at: expiresAt?.toISOString() ?? null,
    };
  }
);
