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

      if (platform === 'android') {
        // --- Android（Google Play）の購入検証 ---
        const packageName =
          process.env.ANDROID_PACKAGE_NAME || defaultAndroidPackageName;
        // Google Play Developer API v3 で購入トークンを検証
        const result = await verifyPlayPurchase(packageName, product_id, purchase_token);

        // 検証結果を Firestore に保存
        // status が 'expired' の場合は tier を 'free' に戻す
        const isExpired = result.status === 'expired';
        await userRef.set(
          {
            tier: isExpired ? 'free' : 'premium',
            remaining_sentences: isExpired ? FREE_DAILY_SENTENCES : PREMIUM_DAILY_SENTENCES,
            remaining_quizzes: isExpired ? FREE_DAILY_QUIZZES : PREMIUM_DAILY_QUIZZES,
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

        return {
          plan: result.status === 'expired' ? 'free' : 'premium',
          expires_at: result.expiresAt?.toISOString() ?? null,
          status: result.status,
        };
      } else {
        // --- iOS（App Store）の購入検証 ---
        // purchase_token は iOS では transactionId として扱う
        const result = await verifyAppStorePurchase(purchase_token);

        // 検証結果を Firestore に保存
        const isExpiredIos = result.status === 'expired';
        await userRef.set(
          {
            tier: isExpiredIos ? 'free' : 'premium',
            remaining_sentences: isExpiredIos ? FREE_DAILY_SENTENCES : PREMIUM_DAILY_SENTENCES,
            remaining_quizzes: isExpiredIos ? FREE_DAILY_QUIZZES : PREMIUM_DAILY_QUIZZES,
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

        return {
          plan: result.status === 'expired' ? 'free' : 'premium',
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
