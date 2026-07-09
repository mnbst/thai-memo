/**
 * verifySubscription.ts — サブスクリプション購入検証
 *
 * 「まいにちタイ語」アプリのアプリ内課金（サブスクリプション）を検証する Cloud Function。
 * クライアント（iOS/Android）から購入トークンまたはレシートを受け取り、
 * 各ストア API（App Store Server API / Google Play Developer API）で
 * 購入の正当性を検証したうえで、Firestore にサブスクリプション状態を保存する。
 *
 * 【対応プラットフォーム】
 * - android: Google Play Developer API v3 で検証（verifyPlayPurchase）
 * - ios: App Store Server API v1 で検証（verifyAppStorePurchase）
 *
 * 【Firestore に保存されるデータ】
 * - tier: 'premium' または 'free'（クイズ生成回数の制限に使用）
 * - subscription: プラットフォーム固有の購入情報（トークン、有効期限、自動更新状態など）
 *
 * リージョン: asia-northeast1（東京）
 * タイムアウト: 30秒
 */
import * as functions from 'firebase-functions/v2';
import * as admin from 'firebase-admin';
import { verifyPlayPurchase } from './services/playBilling';
import { verifyAppStorePurchase } from './services/appStoreServer';
import {
  FREE_DAILY_SENTENCES, FREE_DAILY_QUIZZES,
  PREMIUM_DAILY_SENTENCES, PREMIUM_DAILY_QUIZZES,
} from './constants/quota';

/** Firestore インスタンス */
const db = admin.firestore();
const defaultAndroidPackageName = 'com.thaimemo.thai_memo';

/**
 * 同一サブスクリプションを保持する他ユーザーの doc から premium を剥奪する。
 *
 * 匿名ユーザーの再インストール等で uid が変わると、旧 uid の doc に
 * premium とサブスク情報が残ったままになる。放置するとストア通知の
 * ユーザー検索が旧 doc にヒットし、現役 doc の解約処理が漏れて
 * premium が永久に残る。サブスクは常に最後に検証した uid のみに紐づける。
 */
async function releaseSubscriptionFromOtherUsers(
  identifierField:
    | 'subscription.original_transaction_id'
    | 'subscription.purchase_token',
  identifierValue: string,
  currentUid: string
): Promise<void> {
  const snapshot = await db
    .collection('users')
    .where(identifierField, '==', identifierValue)
    .get();

  for (const doc of snapshot.docs) {
    if (doc.id === currentUid) continue;
    await doc.ref.update({
      tier: 'free',
      remaining_sentences: FREE_DAILY_SENTENCES,
      remaining_quizzes: FREE_DAILY_QUIZZES,
      subscription: admin.firestore.FieldValue.delete(),
    });
    console.log(
      `Released subscription from user ${doc.id} (now owned by ${currentUid})`
    );
  }
}

/**
 * verifySubscription - サブスクリプション購入の検証
 *
 * クライアントから購入トークン/レシートを受け取り、
 * 各ストアAPIで検証後、Firestoreにサブスクリプション状態を保存する。
 *
 * @param request.data.platform - プラットフォーム（'android' | 'ios'）
 * @param request.data.purchase_token - 購入トークン（Android）またはトランザクションID（iOS）
 * @param request.data.product_id - 商品ID（サブスクリプションの識別子）
 * @returns plan（'premium' | 'free'）、expires_at（有効期限）、status（状態）
 */
export const verifySubscription = functions.https.onCall(
  {
    region: 'asia-northeast1',
    timeoutSeconds: 30,
  },
  async (request) => {
    // Firebase Auth 認証チェック
    const uid = request.auth?.uid;
    if (!uid) {
      throw new functions.https.HttpsError('unauthenticated', '認証が必要です');
    }

    // プレミアムはサインイン（Google/Apple連携済み）時のみ利用可能。
    // 匿名 uid は再インストールで失われ premium の所有権が迷子になるため、
    // 匿名ユーザーへの付与自体をサーバー側で拒否する
    if (request.auth?.token?.firebase?.sign_in_provider === 'anonymous') {
      throw new functions.https.HttpsError(
        'failed-precondition',
        'プレミアムのご利用にはサインインが必要です'
      );
    }

    // リクエストパラメータの取得とバリデーション
    const { platform, purchase_token, product_id } = request.data as {
      platform?: string;
      purchase_token?: string;
      product_id?: string;
    };

    // 必須パラメータのチェック
    if (!platform || !purchase_token || !product_id) {
      throw new functions.https.HttpsError(
        'invalid-argument',
        'platform, purchase_token, product_id は必須です'
      );
    }

    // プラットフォームのバリデーション
    if (platform !== 'android' && platform !== 'ios') {
      throw new functions.https.HttpsError(
        'invalid-argument',
        'platform は android または ios を指定してください'
      );
    }

    try {
      const userRef = db.collection('users').doc(uid);
      const userDoc = await userRef.get();
      const currentTier: string = userDoc.data()?.tier ?? 'free';

      if (platform === 'android') {
        // --- Android（Google Play）の購入検証 ---
        const packageName =
          process.env.ANDROID_PACKAGE_NAME || defaultAndroidPackageName;
        // Google Play Developer API v3 で購入トークンを検証
        const result = await verifyPlayPurchase(packageName, product_id, purchase_token);

        const isExpired = result.status === 'expired';
        const newTier = isExpired ? 'free' : 'premium';
        const tierChanged = currentTier !== newTier;

        // クォータはティアが変わる時のみリセット（復元検証で誤リセットしない）
        const quotaUpdate = tierChanged ? {
          remaining_sentences: newTier === 'premium' ? PREMIUM_DAILY_SENTENCES : FREE_DAILY_SENTENCES,
          remaining_quizzes: newTier === 'premium' ? PREMIUM_DAILY_QUIZZES : FREE_DAILY_QUIZZES,
        } : {};

        await userRef.set(
          {
            tier: newTier,
            ...quotaUpdate,
            subscription: {
              product_id,
              platform: 'android',
              purchase_token,                              // RTDN（Google Play通知）での検索に使用
              status: result.status,                       // active / canceled / expired / grace_period
              expires_at: result.expiresAt
                ? admin.firestore.Timestamp.fromDate(result.expiresAt)
                : null,
              auto_renewing: result.autoRenewing,          // 自動更新が有効かどうか
              updated_at: admin.firestore.FieldValue.serverTimestamp(),
            },
          },
          { merge: true }
        );

        await releaseSubscriptionFromOtherUsers(
          'subscription.purchase_token',
          purchase_token,
          uid
        );

        return {
          plan: newTier,
          expires_at: result.expiresAt?.toISOString() ?? null,
          status: result.status,
        };
      } else {
        // --- iOS（App Store）の購入検証 ---
        // purchase_token は iOS では transactionId として扱う
        const result = await verifyAppStorePurchase(purchase_token);

        const isExpiredIos = result.status === 'expired';
        const newTierIos = isExpiredIos ? 'free' : 'premium';
        const tierChangedIos = currentTier !== newTierIos;

        // クォータはティアが変わる時のみリセット（復元検証で誤リセットしない）
        const quotaUpdateIos = tierChangedIos ? {
          remaining_sentences: newTierIos === 'premium' ? PREMIUM_DAILY_SENTENCES : FREE_DAILY_SENTENCES,
          remaining_quizzes: newTierIos === 'premium' ? PREMIUM_DAILY_QUIZZES : FREE_DAILY_QUIZZES,
        } : {};

        await userRef.set(
          {
            tier: newTierIos,
            ...quotaUpdateIos,
            subscription: {
              product_id,
              platform: 'ios',
              original_transaction_id: result.originalTransactionId,  // App Store通知での検索に使用
              status: result.status,
              expires_at: result.expiresAt
                ? admin.firestore.Timestamp.fromDate(result.expiresAt)
                : null,
              auto_renewing: result.autoRenewing,
              updated_at: admin.firestore.FieldValue.serverTimestamp(),
            },
          },
          { merge: true }
        );

        await releaseSubscriptionFromOtherUsers(
          'subscription.original_transaction_id',
          result.originalTransactionId,
          uid
        );

        return {
          plan: newTierIos,
          expires_at: result.expiresAt?.toISOString() ?? null,
          status: result.status,
        };
      }
    } catch (error) {
      console.error('Subscription verification failed:', error);
      throw new functions.https.HttpsError(
        'internal',
        'サブスクリプションの検証に失敗しました'
      );
    }
  }
);
