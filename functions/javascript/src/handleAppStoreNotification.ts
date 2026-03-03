import * as functions from 'firebase-functions/v2';
import * as admin from 'firebase-admin';
import { parseNotificationPayload } from './services/appStoreServer';

const db = admin.firestore();

/**
 * handleAppStoreNotification - App Store Server Notifications V2 ハンドラ
 *
 * Appleからのサーバー通知を受信し、サブスクリプション状態をFirestoreに反映する。
 * Apple は 200 レスポンスを期待するため、処理エラーでもログに記録して 200 を返す。
 */
export const handleAppStoreNotification = functions.https.onRequest(
  {
    region: 'asia-northeast1',
  },
  async (req, res) => {
    if (req.method !== 'POST') {
      res.status(405).send('Method Not Allowed');
      return;
    }

    try {
      const { signedPayload } = req.body as { signedPayload?: string };
      if (!signedPayload) {
        console.warn('Missing signedPayload');
        res.status(400).send('Missing signedPayload');
        return;
      }

      const { notificationType, subtype, transactionInfo, renewalInfo } =
        parseNotificationPayload(signedPayload);

      console.log(
        `App Store Notification: type=${notificationType}, subtype=${subtype ?? 'none'}, ` +
          `originalTxId=${transactionInfo.originalTransactionId}`
      );

      // originalTransactionId でユーザーを検索
      const usersSnapshot = await db
        .collection('users')
        .where(
          'subscription.original_transaction_id',
          '==',
          transactionInfo.originalTransactionId
        )
        .limit(1)
        .get();

      if (usersSnapshot.empty) {
        console.warn(
          `No user found for originalTransactionId: ${transactionInfo.originalTransactionId}`
        );
        res.status(200).send('OK');
        return;
      }

      const userDoc = usersSnapshot.docs[0];
      const userRef = userDoc.ref;

      // 通知タイプに応じてステータスを決定
      let tier: string;
      let status: string;
      let autoRenewing = renewalInfo?.autoRenewStatus === 1;
      const expiresAt = transactionInfo.expiresDate
        ? new Date(transactionInfo.expiresDate)
        : null;

      switch (notificationType) {
        case 'DID_RENEW':
          tier = 'premium';
          status = 'active';
          break;

        case 'EXPIRED':
        case 'REVOKE':
          tier = 'free';
          status = 'expired';
          break;

        case 'DID_CHANGE_RENEWAL_STATUS':
          // autoRenewStatus で判定
          if (renewalInfo?.autoRenewStatus === 0) {
            // 自動更新OFF → 期限まではpremium維持
            tier = 'premium';
            status = 'canceled';
          } else {
            tier = 'premium';
            status = 'active';
          }
          break;

        case 'GRACE_PERIOD_EXPIRED':
          tier = 'free';
          status = 'expired';
          break;

        case 'DID_FAIL_TO_RENEW':
          if (subtype === 'GRACE_PERIOD') {
            tier = 'premium';
            status = 'grace_period';
          } else {
            tier = 'free';
            status = 'expired';
          }
          break;

        case 'SUBSCRIBED':
        case 'DID_CHANGE_RENEWAL_INFO':
          tier = 'premium';
          status = 'active';
          break;

        default:
          console.log(`Unhandled notification type: ${notificationType}`);
          res.status(200).send('OK');
          return;
      }

      await userRef.set(
        {
          tier,
          subscription: {
            status,
            expires_at: expiresAt
              ? admin.firestore.Timestamp.fromDate(expiresAt)
              : null,
            auto_renewing: autoRenewing,
            updated_at: admin.firestore.FieldValue.serverTimestamp(),
          },
        },
        { merge: true }
      );

      console.log(
        `Updated user ${userDoc.id}: tier=${tier}, status=${status}`
      );

      res.status(200).send('OK');
    } catch (error) {
      console.error('Error processing App Store notification:', error);
      // Apple expects 200 even on errors to avoid retries
      res.status(200).send('OK');
    }
  }
);
