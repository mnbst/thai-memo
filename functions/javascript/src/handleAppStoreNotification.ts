/**
 * handleAppStoreNotification.ts — App Store Server Notifications V2 ハンドラ
 *
 * Apple の App Store Server Notifications V2 からのサーバー間通知を受信し、
 * サブスクリプション状態の変更を Firestore に反映する Cloud Function。
 *
 * Apple は App Store Connect で設定した URL に対して HTTP POST で通知を送信する。
 * 通知ペイロードは JWS（JSON Web Signature）形式で署名されている。
 *
 * 【対応する通知タイプ】
 * - SUBSCRIBED              : 新規サブスクリプション登録 → premium / active
 * - DID_RENEW               : 自動更新成功 → premium / active
 * - DID_CHANGE_RENEWAL_INFO : 更新情報変更 → premium / active
 * - DID_CHANGE_RENEWAL_STATUS: 自動更新ステータス変更
 *   - autoRenewStatus=0 → premium / canceled（期限まで premium 維持）
 *   - autoRenewStatus=1 → premium / active
 * - EXPIRED                 : サブスクリプション期限切れ → free / expired
 * - REVOKE                  : 返金・取消 → free / expired
 * - DID_FAIL_TO_RENEW       : 更新失敗
 *   - GRACE_PERIOD → premium / grace_period
 *   - その他 → free / expired
 * - GRACE_PERIOD_EXPIRED    : 猶予期間終了 → free / expired
 *
 * 【重要】Apple は 200 レスポンスを期待するため、処理エラーでも 200 を返す。
 * エラー時に 200 以外を返すとリトライが発生し、通知が重複処理される可能性がある。
 *
 * リージョン: asia-northeast1（東京）
 */
import * as functions from 'firebase-functions/v2';
import * as admin from 'firebase-admin';
import { parseNotificationPayload } from './services/appStoreServer';

/** Firestore インスタンス */
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
    // POST メソッド以外は拒否
    if (req.method !== 'POST') {
      res.status(405).send('Method Not Allowed');
      return;
    }

    try {
      // Apple から送信される JWS 署名付きペイロードを取得
      const { signedPayload } = req.body as { signedPayload?: string };
      if (!signedPayload) {
        console.warn('Missing signedPayload');
        res.status(400).send('Missing signedPayload');
        return;
      }

      // JWS ペイロードをデコードして通知タイプとトランザクション情報を取得
      const { notificationType, subtype, transactionInfo, renewalInfo } =
        parseNotificationPayload(signedPayload);

      console.log(
        `App Store Notification: type=${notificationType}, subtype=${subtype ?? 'none'}, ` +
          `originalTxId=${transactionInfo.originalTransactionId}`
      );

      // originalTransactionId でユーザーを検索
      // verifySubscription で保存した original_transaction_id と照合する
      const usersSnapshot = await db
        .collection('users')
        .where(
          'subscription.original_transaction_id',
          '==',
          transactionInfo.originalTransactionId
        )
        .limit(1)
        .get();

      // 該当ユーザーが見つからない場合（初回購入前の通知など）
      if (usersSnapshot.empty) {
        console.warn(
          `No user found for originalTransactionId: ${transactionInfo.originalTransactionId}`
        );
        res.status(200).send('OK');
        return;
      }

      const userDoc = usersSnapshot.docs[0];
      const userRef = userDoc.ref;

      // --- 通知タイプに応じてサブスクリプション状態を決定 ---
      let tier: string;      // 'premium' or 'free'
      let status: string;    // 'active', 'canceled', 'expired', 'grace_period'
      let autoRenewing = renewalInfo?.autoRenewStatus === 1;  // 1=自動更新ON, 0=OFF
      const expiresAt = transactionInfo.expiresDate
        ? new Date(transactionInfo.expiresDate)
        : null;

      switch (notificationType) {
        // 自動更新成功 → premium を継続
        case 'DID_RENEW':
          tier = 'premium';
          status = 'active';
          break;

        // 期限切れまたは返金・取消 → free に戻す
        case 'EXPIRED':
        case 'REVOKE':
          tier = 'free';
          status = 'expired';
          break;

        // 自動更新ステータス変更
        case 'DID_CHANGE_RENEWAL_STATUS':
          // autoRenewStatus で判定
          if (renewalInfo?.autoRenewStatus === 0) {
            // 自動更新OFF → 現在の期限まで premium を維持、期限後に free になる
            tier = 'premium';
            status = 'canceled';
          } else {
            // 自動更新ON（キャンセル取消など）
            tier = 'premium';
            status = 'active';
          }
          break;

        // 猶予期間終了 → free に戻す
        case 'GRACE_PERIOD_EXPIRED':
          tier = 'free';
          status = 'expired';
          break;

        // 更新失敗
        case 'DID_FAIL_TO_RENEW':
          if (subtype === 'GRACE_PERIOD') {
            // 猶予期間中 → まだ premium を維持（支払い回復の可能性あり）
            tier = 'premium';
            status = 'grace_period';
          } else {
            // 猶予期間なし → free に戻す
            tier = 'free';
            status = 'expired';
          }
          break;

        // 新規登録または更新情報変更 → premium / active
        case 'SUBSCRIBED':
        case 'DID_CHANGE_RENEWAL_INFO':
          tier = 'premium';
          status = 'active';
          break;

        // 未対応の通知タイプはログに記録してスキップ
        default:
          console.log(`Unhandled notification type: ${notificationType}`);
          res.status(200).send('OK');
          return;
      }

      // Firestore のユーザードキュメントを更新
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
      // エラーでも200を返す（Apple のリトライを防ぐため）
      res.status(200).send('OK');
    }
  }
);
