import * as functions from 'firebase-functions/v2';
import * as admin from 'firebase-admin';
import { verifyPlayPurchase } from './services/playBilling';

const db = admin.firestore();


interface RTDNMessage {
  subscriptionNotification?: {
    version: string;
    notificationType: number;
    purchaseToken: string;
    subscriptionId: string;
  };
  packageName: string;
}

/**
 * handlePlayNotification - Google Play RTDN Pub/Subハンドラ
 *
 * Google PlayからPub/Sub経由でサブスクリプション通知を受け取り、
 * Play Developer APIで再検証後、Firestoreを更新する。
 */
export const handlePlayNotification = functions.pubsub.onMessagePublished(
  {
    topic: 'play-subscription-notifications',
    region: 'asia-northeast1',
  },
  async (event) => {
    const messageData = event.data.message.data
      ? JSON.parse(Buffer.from(event.data.message.data, 'base64').toString()) as RTDNMessage
      : null;

    if (!messageData?.subscriptionNotification) {
      console.log('Non-subscription notification, skipping');
      return;
    }

    const { notificationType, purchaseToken, subscriptionId } =
      messageData.subscriptionNotification;
    const packageName = messageData.packageName;

    console.log(
      `RTDN: type=${notificationType}, subscriptionId=${subscriptionId}`
    );

    // purchaseToken でユーザーを検索
    const usersSnapshot = await db
      .collection('users')
      .where('subscription.purchase_token', '==', purchaseToken)
      .limit(1)
      .get();

    if (usersSnapshot.empty) {
      console.warn('No user found for purchaseToken');
      return;
    }

    const userDoc = usersSnapshot.docs[0];
    const userRef = userDoc.ref;

    // Google Play API で最新状態を取得
    try {
      const result = await verifyPlayPurchase(
        packageName,
        subscriptionId,
        purchaseToken
      );

      const tier = result.status === 'expired' ? 'free' : 'premium';

      await userRef.set(
        {
          tier,
          subscription: {
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

      console.log(
        `Updated user ${userDoc.id}: tier=${tier}, status=${result.status}`
      );
    } catch (error) {
      console.error('Failed to verify Play purchase on RTDN:', error);
    }
  }
);
