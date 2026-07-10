/**
 * handlePlayNotification.ts — Google Play RTDN（リアルタイム開発者通知）ハンドラ
 *
 * Google Play Console で設定した Cloud Pub/Sub テーマに配信される
 * サブスクリプション通知（RTDN: Real-time Developer Notifications）を受信し、
 * Google Play Developer API で最新のサブスクリプション状態を再検証したうえで、
 * Firestore のユーザーデータを更新する Cloud Function。
 *
 * 【処理フロー】
 * 1. Pub/Sub メッセージから RTDN データをデコード
 * 2. subscriptionNotification が含まれていない場合はスキップ（テスト通知など）
 * 3. purchaseToken で Firestore からユーザーを検索
 * 4. Google Play Developer API v3 で購入状態を再検証
 * 5. 検証結果に基づいて tier と subscription 情報を Firestore に保存
 *
 * 【RTDN の notificationType 一覧（一部）】
 * - 1: 復旧（RECOVERED）
 * - 2: 更新（RENEWED）
 * - 3: キャンセル（CANCELED）
 * - 4: 購入（PURCHASED）
 * - 12: 失効（EXPIRED）
 * - 13: 期限切れ（EXPIRED）
 * ※ 本関数では notificationType に関わらず Play API で再検証するため、
 *   個別の通知タイプごとの処理は行わない
 *
 * Pub/Sub テーマ: play-subscription-notifications
 * リージョン: asia-northeast1（東京）
 */
import * as functions from 'firebase-functions/v2';
import * as admin from 'firebase-admin';
import { verifyPlayPurchase } from './services/playBilling';
import {
  FREE_DAILY_SENTENCES, FREE_DAILY_QUIZZES,
  PREMIUM_DAILY_SENTENCES, PREMIUM_DAILY_QUIZZES,
} from './constants/quota';

/** Firestore インスタンス */
const db = admin.firestore();

/**
 * RTDN（Real-time Developer Notifications）メッセージの型定義
 *
 * Google Play から Pub/Sub 経由で送信される通知メッセージの構造。
 * subscriptionNotification が含まれない場合はテスト通知等のため処理をスキップする。
 */
interface RTDNMessage {
  /** サブスクリプション通知データ（テスト通知の場合は undefined） */
  subscriptionNotification?: {
    /** RTDN バージョン */
    version: string;
    /** 通知タイプ（1=復旧, 2=更新, 3=キャンセル, 4=購入, 12=失効, 13=期限切れ など） */
    notificationType: number;
    /** Google Play の購入トークン（ユーザー検索に使用） */
    purchaseToken: string;
    /** サブスクリプション ID（商品 ID） */
    subscriptionId: string;
  };
  /** アプリのパッケージ名 */
  packageName: string;
}

/**
 * handlePlayNotification - Google Play RTDN Pub/Sub ハンドラ
 *
 * Google Play から Pub/Sub 経由でサブスクリプション通知を受け取り、
 * Play Developer API で再検証後、Firestore を更新する。
 */
export const handlePlayNotification = functions.pubsub.onMessagePublished(
  {
    topic: 'play-subscription-notifications',
    region: 'asia-northeast1',
  },
  async (event) => {
    // Pub/Sub メッセージのデータ部分を Base64 デコードして JSON パース
    const messageData = event.data.message.data
      ? JSON.parse(Buffer.from(event.data.message.data, 'base64').toString()) as RTDNMessage
      : null;

    // subscriptionNotification がない場合はテスト通知等のためスキップ
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

    // purchaseToken で Firestore からユーザーを検索
    // verifySubscription で保存した purchase_token と照合する
    // 匿名ユーザーの再インストール等で同一サブスクの doc が複数残る可能性が
    // あるため limit(1) にせず、該当する全 doc を更新する
    const usersSnapshot = await db
      .collection('users')
      .where('subscription.purchase_token', '==', purchaseToken)
      .get();

    // 該当ユーザーが見つからない場合（初回購入前の通知など）
    if (usersSnapshot.empty) {
      console.warn('No user found for purchaseToken');
      return;
    }

    // Google Play Developer API v3 で最新のサブスクリプション状態を取得
    try {
      const result = await verifyPlayPurchase(
        packageName,
        subscriptionId,
        purchaseToken
      );

      // 検証結果に基づいて tier を決定（expired なら free、それ以外は premium）
      const tier = result.status === 'expired' ? 'free' : 'premium';
      const isFree = tier === 'free';

      for (const userDoc of usersSnapshot.docs) {
        const tierChanged = userDoc.data()?.tier !== tier;

        // Firestore のユーザードキュメントを更新
        // ドット記法で subscription のサブフィールドのみ更新し、purchase_token 等を保持する
        const updateData: Record<string, unknown> = {
          tier,
          'subscription.status': result.status,
          'subscription.expires_at': result.expiresAt
            ? admin.firestore.Timestamp.fromDate(result.expiresAt)
            : null,
          'subscription.auto_renewing': result.autoRenewing,
          'subscription.updated_at': admin.firestore.FieldValue.serverTimestamp(),
        };

        // クォータはティアが変わる時のみリセット（更新通知で誤リセットしない）
        if (tierChanged) {
          updateData.remaining_sentences = isFree ? FREE_DAILY_SENTENCES : PREMIUM_DAILY_SENTENCES;
          updateData.remaining_quizzes = isFree ? FREE_DAILY_QUIZZES : PREMIUM_DAILY_QUIZZES;
        }

        await userDoc.ref.update(updateData);

        console.log(
          `Updated user ${userDoc.id}: tier=${tier}, status=${result.status}`
        );
      }
    } catch (error) {
      console.error('Failed to verify Play purchase on RTDN:', error);
    }
  }
);
