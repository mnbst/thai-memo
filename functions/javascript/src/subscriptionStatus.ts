/**
 * subscriptionStatus.ts — サブスクリプション状態の取得
 *
 * 「まいにちタイ語」アプリのクライアントから呼び出され、
 * ユーザーの現在のサブスクリプション状態（free/premium）を返却する。
 *
 * Firestore に保存されたサブスクリプション情報を読み取り、
 * 有効期限が過ぎている場合は自動的に 'expired' に更新してから結果を返す。
 * これにより、ストア通知が遅延した場合でもアプリ側で正確な状態を取得できる。
 *
 * リージョン: asia-northeast1（東京）
 */
import * as functions from 'firebase-functions/v2';
import * as admin from 'firebase-admin';

/** Firestore インスタンス */
const db = admin.firestore();

/**
 * subscriptionStatus - サブスクリプション状態の取得
 *
 * Firestoreからサブスク状態を読み取り、有効期限チェック後に返却する。
 * 期限切れの場合はFirestoreも自動更新する。
 *
 * @returns plan（'premium' | 'free'）、expires_at（有効期限のISO文字列 or null）
 */
export const subscriptionStatus = functions.https.onCall(
  {
    region: 'asia-northeast1',
  },
  async (request) => {
    // App Check 検証（dev環境はスキップ）
    if (process.env.GCLOUD_PROJECT !== 'thai-memo-dev' && !request.app) {
      throw new functions.https.HttpsError('unauthenticated', 'App Checkの検証に失敗しました');
    }

    // Firebase Auth 認証チェック
    const uid = request.auth?.uid;
    if (!uid) {
      throw new functions.https.HttpsError('unauthenticated', '認証が必要です');
    }

    // Firestore からユーザーのサブスクリプション情報を取得
    const userRef = db.collection('users').doc(uid);
    const userDoc = await userRef.get();
    const userData = userDoc.data();

    // サブスクリプション情報が存在しない場合は free として返却
    if (!userData?.subscription) {
      return { plan: 'free', expires_at: null };
    }

    const subscription = userData.subscription;
    const expiresAt = subscription.expires_at?.toDate() as Date | undefined;
    const now = new Date();

    // 期限切れチェック: status が 'active' だが有効期限が過ぎている場合
    // ストア通知（App Store / Google Play）が遅延した場合のフォールバック処理
    // Firestore の status を 'expired'、tier を 'free' に自動更新する
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

    // 通常の状態返却
    const plan = userData.tier === 'premium' ? 'premium' : 'free';
    return {
      plan,
      expires_at: expiresAt?.toISOString() ?? null,
    };
  }
);
