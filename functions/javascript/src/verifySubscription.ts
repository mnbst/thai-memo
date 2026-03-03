import * as functions from 'firebase-functions/v2';
import * as admin from 'firebase-admin';
import { verifyPlayPurchase } from './services/playBilling';
import { verifyAppStorePurchase } from './services/appStoreServer';

const db = admin.firestore();

/**
 * verifySubscription - サブスクリプション購入の検証
 *
 * クライアントから購入トークン/レシートを受け取り、
 * 各ストアAPIで検証後、Firestoreにサブスクリプション状態を保存する。
 */
export const verifySubscription = functions.https.onCall(
  {
    region: 'asia-northeast1',
    timeoutSeconds: 30,
  },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new functions.https.HttpsError('unauthenticated', '認証が必要です');
    }

    const { platform, purchase_token, product_id } = request.data as {
      platform?: string;
      purchase_token?: string;
      product_id?: string;
    };

    if (!platform || !purchase_token || !product_id) {
      throw new functions.https.HttpsError(
        'invalid-argument',
        'platform, purchase_token, product_id は必須です'
      );
    }

    if (platform !== 'android' && platform !== 'ios') {
      throw new functions.https.HttpsError(
        'invalid-argument',
        'platform は android または ios を指定してください'
      );
    }

    try {
      const userRef = db.collection('users').doc(uid);

      if (platform === 'android') {
        const packageName = process.env.ANDROID_PACKAGE_NAME || 'com.gaku.thaimemo';
        const result = await verifyPlayPurchase(packageName, product_id, purchase_token);

        await userRef.set(
          {
            tier: result.status === 'expired' ? 'free' : 'premium',
            subscription: {
              product_id,
              platform: 'android',
              purchase_token,
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
      } else {
        // iOS: purchase_token は transactionId
        const result = await verifyAppStorePurchase(purchase_token);

        await userRef.set(
          {
            tier: result.status === 'expired' ? 'free' : 'premium',
            subscription: {
              product_id,
              platform: 'ios',
              original_transaction_id: result.originalTransactionId,
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
