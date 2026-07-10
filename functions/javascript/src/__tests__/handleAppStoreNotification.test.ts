/**
 * handleAppStoreNotification.test.ts
 *
 * App Store Server Notifications V2 ハンドラのテスト。
 *
 * テスト戦略:
 * - parseNotificationPayload（署名検証）はモック化して、ハンドラ内の
 *   ビジネスロジック（tier/status 判定・Firestore 更新）に集中する。
 * - Firestore はモック化して実際の DB アクセスを排除する。
 * - firebase-functions/v2 はモック化して Cloud Function ラッパーを透過し、
 *   ハンドラ関数を直接呼び出せるようにする。
 */

// ============================================================
// モック定義
// NOTE: jest.mock はファイル先頭にホイストされるため、
//       変数名が "mock" で始まるものだけがファクトリ内で参照可能（Jest の仕様）
// ============================================================

/** Firestore .get() のモック（クエリ結果を per-test で制御） */
const mockFirestoreGet = jest.fn();
/** Firestore userRef.set() のモック（書き込み内容を検証） */
const mockFirestoreSet = jest.fn();
/** parseNotificationPayload のモック（Apple JWS 検証をスキップ） */
const mockParseNotificationPayload = jest.fn();

/**
 * firebase-functions/v2 モック
 * onRequest(config, handler) → handler を返すことで、
 * Cloud Function ラッパーを素通りしてハンドラを直接テスト可能にする
 */
jest.mock('firebase-functions/v2', () => ({
  https: {
    onRequest: (_config: unknown, handler: unknown) => handler,
    onCall: (_config: unknown, handler: unknown) => handler,
    HttpsError: class HttpsError extends Error {
      code: string;
      constructor(code: string, message: string) {
        super(message);
        this.code = code;
        this.name = 'HttpsError';
      }
    },
  },
}));

/**
 * firebase-admin モック
 * const db = admin.firestore() がモジュール初期化時に呼ばれるため、
 * モジュールインポート前にモックを定義する必要がある。
 *
 * Firestore チェーン: collection → where → get
 * ユーザー書き込み:  userRef.set(data, { merge: true })
 */
jest.mock('firebase-admin', () => ({
  firestore: Object.assign(
    jest.fn(() => ({
      collection: jest.fn(() => ({
        where: jest.fn(() => ({
          // get はテストごとに mockResolvedValueOnce で戻り値を制御する
          get: mockFirestoreGet,
        })),
      })),
    })),
    {
      // Timestamp.fromDate: Date → Firestore Timestamp 変換
      // テストでは _seconds フィールドで存在確認する
      Timestamp: {
        fromDate: jest.fn((d: Date) => ({
          _seconds: Math.floor(d.getTime() / 1000),
          toDate: () => d,
        })),
      },
      // FieldValue.serverTimestamp: サーバー側で現在時刻を使うマーカー
      FieldValue: {
        serverTimestamp: jest.fn(() => 'SERVER_TIMESTAMP'),
      },
    }
  ),
  apps: [],
}));

/**
 * appStoreServer モック
 * parseNotificationPayload をモック化して JWS 署名検証を除外し、
 * ビジネスロジックのみをテストする
 */
jest.mock('../services/appStoreServer', () => ({
  parseNotificationPayload: mockParseNotificationPayload,
}));

// ============================================================
// テスト本体
// ============================================================
import { handleAppStoreNotification } from '../handleAppStoreNotification';
import {
  FREE_DAILY_SENTENCES,
  FREE_DAILY_QUIZZES,
  PREMIUM_DAILY_SENTENCES,
  PREMIUM_DAILY_QUIZZES,
} from '../constants/quota';


// ──────────────────────────────────────────────────────────
// テスト用ヘルパー
// ──────────────────────────────────────────────────────────

/** モック HTTP リクエストを作成 */
function makeReq(body: Record<string, unknown> = {}, method = 'POST') {
  return { method, body } as unknown as Parameters<typeof handleAppStoreNotification>[0];
}

/**
 * モック HTTP レスポンスを作成
 * res.status(code).send(body) のチェーンに対応するため
 * status() は自分自身を返す（mockReturnThis）
 */
function makeRes() {
  const res = {
    status: jest.fn(),
    send: jest.fn(),
  };
  (res.status as jest.Mock).mockReturnValue(res);
  return res;
}

/**
 * Firestore ユーザースナップショット（ユーザーあり）を作成
 * docs[0].ref.set が mockFirestoreSet を参照する
 * currentTier: Firestore に現在保存されている tier 値（quota リセット判定に使用）
 */
function makeUserSnapshot(userId = 'user123', currentTier?: string) {
  return {
    empty: false,
    docs: [{
      id: userId,
      ref: { update: mockFirestoreSet },
      data: jest.fn(() => ({ tier: currentTier })),
    }],
  };
}

/** Firestore スナップショット（ユーザーなし） */
const EMPTY_SNAPSHOT = { empty: true, docs: [] };

/**
 * subscription フィールドを取得するヘルパー
 * 実装は userRef.update() + ドット記法キー（'subscription.status' 等）を使うため、
 * ここでドット記法キーからネストオブジェクト形式に変換する
 */
function getSubscription(data: Record<string, unknown> | null) {
  if (!data) return null;
  return {
    status: data['subscription.status'],
    expires_at: data['subscription.expires_at'],
    auto_renewing: data['subscription.auto_renewing'],
    updated_at: data['subscription.updated_at'],
  };
}

// テスト共通のトランザクション情報（Apple JWS デコード後の構造）
const FUTURE_TIMESTAMP = Date.now() + 86_400_000; // 24時間後（有効なサブスク）
const BASE_TX_INFO = {
  originalTransactionId: 'orig_tx_123',
  transactionId: 'tx_123',
  productId: 'com.thaimemo.monthly',
  expiresDate: FUTURE_TIMESTAMP,
  type: 'Auto-Renewable Subscription',
  environment: 'Sandbox',
};
// 自動更新 ON の renewalInfo
const RENEWAL_INFO_ON = {
  autoRenewStatus: 1,
  originalTransactionId: 'orig_tx_123',
  productId: 'com.thaimemo.monthly',
};
// 自動更新 OFF（キャンセル済み）の renewalInfo
const RENEWAL_INFO_OFF = {
  autoRenewStatus: 0,
  originalTransactionId: 'orig_tx_123',
  productId: 'com.thaimemo.monthly',
};

// ──────────────────────────────────────────────────────────
// テストスイート
// ──────────────────────────────────────────────────────────

// firebase-functions モックが onRequest の第2引数ハンドラを返すため、
// キャストを1か所にまとめて型付きで使用する
const handler = handleAppStoreNotification as unknown as (
  req: { method: string; body: Record<string, unknown> },
  res: { status: jest.Mock; send: jest.Mock }
) => Promise<void>;

describe('handleAppStoreNotification', () => {
  // 各テスト前にモックをリセットして相互干渉を防ぐ
  beforeEach(() => {
    jest.clearAllMocks();
    mockFirestoreSet.mockResolvedValue(undefined);
    // デフォルト: ユーザーが見つかる状態（個別テストで上書き可能）
    mockFirestoreGet.mockResolvedValue(makeUserSnapshot());
  });

  // ──────────────────────────────────────────────────────────
  // エラーハンドリング（Firestore障害）
  // Apple は 200 以外を受け取るとリトライするため、Firestore 障害でも 200 を返す
  // ──────────────────────────────────────────────────────────
  describe('Firestore 障害時のエラーハンドリング', () => {
    test('Firestore get が失敗した場合も 200 を返す（Apple のリトライ防止）', async () => {
      mockParseNotificationPayload.mockResolvedValueOnce({
        notificationType: 'DID_RENEW',
        transactionInfo: BASE_TX_INFO,
        renewalInfo: RENEWAL_INFO_ON,
      });
      mockFirestoreGet.mockRejectedValueOnce(new Error('Firestore unavailable'));

      const req = makeReq({ signedPayload: 'test.jws.sig' });
      const res = makeRes();
      await handler(req, res);

      expect(res.status).toHaveBeenCalledWith(200);
      expect(mockFirestoreSet).not.toHaveBeenCalled();
    });

    test('Firestore set が失敗した場合も 200 を返す（Apple のリトライ防止）', async () => {
      mockParseNotificationPayload.mockResolvedValueOnce({
        notificationType: 'DID_RENEW',
        transactionInfo: BASE_TX_INFO,
        renewalInfo: RENEWAL_INFO_ON,
      });
      mockFirestoreSet.mockRejectedValueOnce(new Error('Firestore write failed'));

      const req = makeReq({ signedPayload: 'test.jws.sig' });
      const res = makeRes();
      await handler(req, res);

      expect(res.status).toHaveBeenCalledWith(200);
    });
  });

  // ──────────────────────────────────────────────────────────
  // HTTPメソッド・リクエスト検証
  // ──────────────────────────────────────────────────────────
  describe('HTTPメソッドとリクエスト検証', () => {
    test('POST 以外のリクエスト（GET など）は 405 Method Not Allowed を返す', async () => {
      // Apple 以外のクローラーや誤ったエンドポイント呼び出しへの対応
      const req = makeReq({}, 'GET');
      const res = makeRes();
      await handler(req, res);
      expect(res.status).toHaveBeenCalledWith(405);
    });

    test('body に signedPayload が存在しない場合は 400 Bad Request を返す', async () => {
      // Apple は必ず signedPayload を含めるため、存在しない場合は不正なリクエスト
      const req = makeReq({ unrelated: 'field' });
      const res = makeRes();
      await handler(req, res);
      expect(res.status).toHaveBeenCalledWith(400);
      // 400 の場合は Firestore を更新しない
      expect(mockFirestoreSet).not.toHaveBeenCalled();
    });
  });

  // ──────────────────────────────────────────────────────────
  // 署名検証
  // ──────────────────────────────────────────────────────────
  describe('署名検証', () => {
    test('署名検証失敗時でも 200 を返す（Apple のリトライを防ぐため）', async () => {
      // 偽造された通知（x5c チェーン不正など）が来た場合、
      // 200 以外を返すと Apple が同じ通知を繰り返し送信する仕様のため 200 を返す
      mockParseNotificationPayload.mockRejectedValueOnce(
        new Error('Certificate chain verification failed at index 0')
      );
      const req = makeReq({ signedPayload: 'forged.jws.token' });
      const res = makeRes();
      await handler(req, res);
      expect(res.status).toHaveBeenCalledWith(200);
      // 不正な通知なので Firestore は更新しない
      expect(mockFirestoreSet).not.toHaveBeenCalled();
    });
  });

  // ──────────────────────────────────────────────────────────
  // ユーザー検索
  // ──────────────────────────────────────────────────────────
  describe('ユーザー検索', () => {
    test('original_transaction_id に対応するユーザーが見つからない場合は 200 を返す', async () => {
      // SUBSCRIBED 通知が来る前に他の通知が届いた場合など
      // Firestore に original_transaction_id が登録されていない状態
      mockParseNotificationPayload.mockResolvedValueOnce({
        notificationType: 'DID_RENEW',
        transactionInfo: BASE_TX_INFO,
        renewalInfo: RENEWAL_INFO_ON,
      });
      mockFirestoreGet.mockResolvedValueOnce(EMPTY_SNAPSHOT);

      const req = makeReq({ signedPayload: 'test.jws.sig' });
      const res = makeRes();
      await handler(req, res);

      expect(res.status).toHaveBeenCalledWith(200);
      // ユーザー不在なので Firestore 書き込みはしない
      expect(mockFirestoreSet).not.toHaveBeenCalled();
    });
  });

  // ──────────────────────────────────────────────────────────
  // 通知タイプ別の Firestore 更新
  // 各通知タイプに対して tier と status が正しく設定されることを検証する
  // ──────────────────────────────────────────────────────────
  describe('通知タイプ別の Firestore 更新', () => {
    /**
     * 通知を処理して Firestore の書き込みデータを返すヘルパー
     * @returns Firestore.set() に渡されたデータオブジェクト、または null（書き込みなし）
     */
    async function processNotification(
      notificationType: string,
      options: {
        subtype?: string;
        renewalInfo?: typeof RENEWAL_INFO_ON;
        txInfo?: typeof BASE_TX_INFO;
      } = {}
    ): Promise<Record<string, unknown> | null> {
      const { subtype, renewalInfo = RENEWAL_INFO_ON, txInfo = BASE_TX_INFO } = options;
      mockParseNotificationPayload.mockResolvedValueOnce({
        notificationType,
        subtype,
        transactionInfo: txInfo,
        renewalInfo,
      });
      const req = makeReq({ signedPayload: 'test.jws.sig' });
      const res = makeRes();
      await handler(req, res);
      expect(res.status).toHaveBeenCalledWith(200);
      // Firestore.set() に渡された第1引数（書き込みデータ）を返す
      return (mockFirestoreSet.mock.calls[0]?.[0] ?? null) as Record<string, unknown> | null;
    }

    test('同一 original_transaction_id の doc が複数ある場合は全件更新される', async () => {
      // 匿名ユーザーの再インストール等で同一サブスクの doc が複数残るケース
      const mockUpdate1 = jest.fn().mockResolvedValue(undefined);
      const mockUpdate2 = jest.fn().mockResolvedValue(undefined);
      mockFirestoreGet.mockResolvedValueOnce({
        empty: false,
        docs: [
          { id: 'old_anon_uid', ref: { update: mockUpdate1 }, data: () => ({ tier: 'premium' }) },
          { id: 'current_uid', ref: { update: mockUpdate2 }, data: () => ({ tier: 'premium' }) },
        ],
      });
      mockParseNotificationPayload.mockResolvedValueOnce({
        notificationType: 'EXPIRED',
        transactionInfo: BASE_TX_INFO,
        renewalInfo: RENEWAL_INFO_OFF,
      });

      await handler(makeReq({ signedPayload: 'test.jws.sig' }), makeRes());

      // 両方の doc が free に落とされる
      expect(mockUpdate1).toHaveBeenCalledTimes(1);
      expect(mockUpdate2).toHaveBeenCalledTimes(1);
      expect((mockUpdate1.mock.calls[0][0] as Record<string, unknown>).tier).toBe('free');
      expect((mockUpdate2.mock.calls[0][0] as Record<string, unknown>).tier).toBe('free');
    });

    test('DID_RENEW → tier=premium / status=active（定期購読の自動更新成功）', async () => {
      const data = await processNotification('DID_RENEW');
      expect(data?.tier).toBe('premium');
      expect(getSubscription(data)?.status).toBe('active');
    });

    test('BILLING_RECOVERY → tier=premium / status=active（猶予期間後の課金回復）', async () => {
      // DID_FAIL_TO_RENEW → GRACE_PERIOD 後に支払い方法が更新され課金が成功した場合
      const data = await processNotification('BILLING_RECOVERY');
      expect(data?.tier).toBe('premium');
      expect(getSubscription(data)?.status).toBe('active');
    });

    test('EXPIRED → tier=free / status=expired（有効期限切れ）', async () => {
      // 猶予期間も終了してサブスクリプションが完全に失効した場合
      const data = await processNotification('EXPIRED');
      expect(data?.tier).toBe('free');
      expect(getSubscription(data)?.status).toBe('expired');
    });

    test('REVOKE → tier=free / status=expired（ファミリー共有メンバーのアクセス取消）', async () => {
      // ファミリー共有の共有者がサブスクを解約・共有メンバーが削除された場合
      const data = await processNotification('REVOKE');
      expect(data?.tier).toBe('free');
      expect(getSubscription(data)?.status).toBe('expired');
    });

    test('REFUND → tier=free / status=expired（返金処理）', async () => {
      // Apple による返金処理が完了した場合、即座に free に戻す
      const data = await processNotification('REFUND');
      expect(data?.tier).toBe('free');
      expect(getSubscription(data)?.status).toBe('expired');
    });

    test('DID_CHANGE_RENEWAL_STATUS autoRenewStatus=0 → tier=premium / status=canceled（自動更新 OFF）', async () => {
      // ユーザーが自動更新をキャンセルした場合:
      // 現在の期限日まで premium を維持し、その後 EXPIRED 通知で free に切り替わる
      const data = await processNotification('DID_CHANGE_RENEWAL_STATUS', {
        renewalInfo: RENEWAL_INFO_OFF,
      });
      expect(data?.tier).toBe('premium');
      expect(getSubscription(data)?.status).toBe('canceled');
    });

    test('DID_CHANGE_RENEWAL_STATUS autoRenewStatus=1 → tier=premium / status=active（自動更新 ON に再設定）', async () => {
      // キャンセルを撤回して自動更新を再度 ON にした場合
      const data = await processNotification('DID_CHANGE_RENEWAL_STATUS', {
        renewalInfo: RENEWAL_INFO_ON,
      });
      expect(data?.tier).toBe('premium');
      expect(getSubscription(data)?.status).toBe('active');
    });

    test('DID_FAIL_TO_RENEW subtype=GRACE_PERIOD → tier=premium / status=grace_period（猶予期間中）', async () => {
      // 更新失敗だが Apple が猶予期間を設けた場合:
      // ユーザーは支払い方法を更新する機会があるため premium を維持する
      const data = await processNotification('DID_FAIL_TO_RENEW', { subtype: 'GRACE_PERIOD' });
      expect(data?.tier).toBe('premium');
      expect(getSubscription(data)?.status).toBe('grace_period');
    });

    test('DID_FAIL_TO_RENEW subtype なし → tier=free / status=expired（猶予期間なし）', async () => {
      // 猶予期間なしで更新が失敗した場合、即座に free に戻す
      const data = await processNotification('DID_FAIL_TO_RENEW');
      expect(data?.tier).toBe('free');
      expect(getSubscription(data)?.status).toBe('expired');
    });

    test('GRACE_PERIOD_EXPIRED → tier=free / status=expired（猶予期間終了）', async () => {
      // 猶予期間中も支払いが回復せず期間が終了した場合
      const data = await processNotification('GRACE_PERIOD_EXPIRED');
      expect(data?.tier).toBe('free');
      expect(getSubscription(data)?.status).toBe('expired');
    });

    test('SUBSCRIBED → tier=premium / status=active（新規サブスクリプション登録）', async () => {
      // 初めてサブスクを購入した場合（verifySubscription と重複するが通知でも更新する）
      const data = await processNotification('SUBSCRIBED');
      expect(data?.tier).toBe('premium');
      expect(getSubscription(data)?.status).toBe('active');
    });

    test('DID_CHANGE_RENEWAL_INFO → tier=premium / status=active（更新情報変更）', async () => {
      // プランの変更やオファーの適用など更新情報が変わった場合
      const data = await processNotification('DID_CHANGE_RENEWAL_INFO');
      expect(data?.tier).toBe('premium');
      expect(getSubscription(data)?.status).toBe('active');
    });

    test('未知の通知タイプはスキップして 200 を返す（Firestore 更新なし）', async () => {
      // Apple が将来追加する可能性のある未知の通知タイプへの対応
      // 200 を返して Apple のリトライを防ぐが Firestore は更新しない
      await processNotification('CONSUMPTION_REQUEST');
      expect(mockFirestoreSet).not.toHaveBeenCalled();
    });
  });

  // ──────────────────────────────────────────────────────────
  // クォータ更新（tier 変化時のみリセット）
  // DID_RENEW など tier が変わらない通知では quota を上書きしない。
  // tier が切り替わる通知（EXPIRED, SUBSCRIBED など）のみリセットする。
  // ──────────────────────────────────────────────────────────
  describe('クォータ更新', () => {
    test('DID_RENEW: premium→premium は quota フィールドを更新しない', async () => {
      // 同一 tier 内の通知でユーザーが当日消費した quota を誤ってリセットしないことを保証する
      mockFirestoreGet.mockResolvedValueOnce(makeUserSnapshot('user123', 'premium'));
      mockParseNotificationPayload.mockResolvedValueOnce({
        notificationType: 'DID_RENEW',
        transactionInfo: BASE_TX_INFO,
        renewalInfo: RENEWAL_INFO_ON,
      });
      const req = makeReq({ signedPayload: 'test.jws.sig' });
      const res = makeRes();
      await handler(req, res);

      const data = mockFirestoreSet.mock.calls[0][0] as Record<string, unknown>;
      expect(data.remaining_sentences).toBeUndefined();
      expect(data.remaining_quizzes).toBeUndefined();
    });

    test('EXPIRED: premium→free は FREE クォータ値にリセットされる', async () => {
      mockFirestoreGet.mockResolvedValueOnce(makeUserSnapshot('user123', 'premium'));
      mockParseNotificationPayload.mockResolvedValueOnce({
        notificationType: 'EXPIRED',
        transactionInfo: BASE_TX_INFO,
        renewalInfo: RENEWAL_INFO_ON,
      });
      const req = makeReq({ signedPayload: 'test.jws.sig' });
      const res = makeRes();
      await handler(req, res);

      const data = mockFirestoreSet.mock.calls[0][0] as Record<string, unknown>;
      expect(data.remaining_sentences).toBe(FREE_DAILY_SENTENCES);
      expect(data.remaining_quizzes).toBe(FREE_DAILY_QUIZZES);
    });

    test('SUBSCRIBED: free→premium は PREMIUM クォータ値にリセットされる', async () => {
      mockFirestoreGet.mockResolvedValueOnce(makeUserSnapshot('user123', 'free'));
      mockParseNotificationPayload.mockResolvedValueOnce({
        notificationType: 'SUBSCRIBED',
        transactionInfo: BASE_TX_INFO,
        renewalInfo: RENEWAL_INFO_ON,
      });
      const req = makeReq({ signedPayload: 'test.jws.sig' });
      const res = makeRes();
      await handler(req, res);

      const data = mockFirestoreSet.mock.calls[0][0] as Record<string, unknown>;
      expect(data.remaining_sentences).toBe(PREMIUM_DAILY_SENTENCES);
      expect(data.remaining_quizzes).toBe(PREMIUM_DAILY_QUIZZES);
    });

    test('REFUND: premium→free は FREE クォータ値にリセットされる', async () => {
      mockFirestoreGet.mockResolvedValueOnce(makeUserSnapshot('user123', 'premium'));
      mockParseNotificationPayload.mockResolvedValueOnce({
        notificationType: 'REFUND',
        transactionInfo: BASE_TX_INFO,
        renewalInfo: RENEWAL_INFO_ON,
      });
      const req = makeReq({ signedPayload: 'test.jws.sig' });
      const res = makeRes();
      await handler(req, res);

      const data = mockFirestoreSet.mock.calls[0][0] as Record<string, unknown>;
      expect(data.remaining_sentences).toBe(FREE_DAILY_SENTENCES);
      expect(data.remaining_quizzes).toBe(FREE_DAILY_QUIZZES);
    });

    test('BILLING_RECOVERY: premium→premium は quota フィールドを更新しない', async () => {
      mockFirestoreGet.mockResolvedValueOnce(makeUserSnapshot('user123', 'premium'));
      mockParseNotificationPayload.mockResolvedValueOnce({
        notificationType: 'BILLING_RECOVERY',
        transactionInfo: BASE_TX_INFO,
        renewalInfo: RENEWAL_INFO_ON,
      });
      const req = makeReq({ signedPayload: 'test.jws.sig' });
      const res = makeRes();
      await handler(req, res);

      const data = mockFirestoreSet.mock.calls[0][0] as Record<string, unknown>;
      expect(data.remaining_sentences).toBeUndefined();
      expect(data.remaining_quizzes).toBeUndefined();
    });
  });

  // ──────────────────────────────────────────────────────────
  // Firestore 書き込みフィールド詳細
  // ──────────────────────────────────────────────────────────
  describe('Firestore 書き込みフィールド詳細', () => {
    test('renewalInfo.autoRenewStatus=1 の場合 auto_renewing=true が保存される', async () => {
      // 自動更新 ON → autoRenewing: true
      mockParseNotificationPayload.mockResolvedValueOnce({
        notificationType: 'DID_RENEW',
        transactionInfo: BASE_TX_INFO,
        renewalInfo: { ...RENEWAL_INFO_ON, autoRenewStatus: 1 },
      });
      const req = makeReq({ signedPayload: 'test.jws.sig' });
      const res = makeRes();
      await handler(req, res);

      const data = mockFirestoreSet.mock.calls[0][0] as Record<string, unknown>;
      expect(getSubscription(data)?.auto_renewing).toBe(true);
    });

    test('renewalInfo.autoRenewStatus=0 の場合 auto_renewing=false が保存される', async () => {
      // 自動更新 OFF → autoRenewing: false
      mockParseNotificationPayload.mockResolvedValueOnce({
        notificationType: 'DID_CHANGE_RENEWAL_STATUS',
        transactionInfo: BASE_TX_INFO,
        renewalInfo: { ...RENEWAL_INFO_OFF, autoRenewStatus: 0 },
      });
      const req = makeReq({ signedPayload: 'test.jws.sig' });
      const res = makeRes();
      await handler(req, res);

      const data = mockFirestoreSet.mock.calls[0][0] as Record<string, unknown>;
      expect(getSubscription(data)?.auto_renewing).toBe(false);
    });

    test('expiresDate が存在する場合は Timestamp に変換して expires_at に保存される', async () => {
      // Apple の expiresDate（ミリ秒）→ Date → Firestore Timestamp の変換を確認
      const expiresDate = Date.now() + 86_400_000;
      mockParseNotificationPayload.mockResolvedValueOnce({
        notificationType: 'DID_RENEW',
        transactionInfo: { ...BASE_TX_INFO, expiresDate },
        renewalInfo: RENEWAL_INFO_ON,
      });
      const req = makeReq({ signedPayload: 'test.jws.sig' });
      const res = makeRes();
      await handler(req, res);

      // Timestamp.fromDate が呼ばれた結果（モック実装: _seconds フィールドを持つオブジェクト）
      const data = mockFirestoreSet.mock.calls[0][0] as Record<string, unknown>;
      expect(getSubscription(data)?.expires_at).not.toBeNull();
      expect(getSubscription(data)?.expires_at).toHaveProperty('_seconds');
    });

    test('expiresDate が存在しない場合は expires_at=null が保存される', async () => {
      // REVOKE など有効期限がないトランザクションの場合
      mockParseNotificationPayload.mockResolvedValueOnce({
        notificationType: 'REVOKE',
        transactionInfo: { ...BASE_TX_INFO, expiresDate: undefined },
        renewalInfo: RENEWAL_INFO_ON,
      });
      const req = makeReq({ signedPayload: 'test.jws.sig' });
      const res = makeRes();
      await handler(req, res);

      const data = mockFirestoreSet.mock.calls[0][0] as Record<string, unknown>;
      expect(getSubscription(data)?.expires_at).toBeNull();
    });

    test('Firestore.update() が呼ばれる（ドット記法で他フィールドを保持）', async () => {
      // update() + ドット記法キー（'subscription.status' 等）により
      // original_transaction_id, product_id など通知で更新しないフィールドが削除されないことを保証する
      mockParseNotificationPayload.mockResolvedValueOnce({
        notificationType: 'DID_RENEW',
        transactionInfo: BASE_TX_INFO,
        renewalInfo: RENEWAL_INFO_ON,
      });
      const req = makeReq({ signedPayload: 'test.jws.sig' });
      const res = makeRes();
      await handler(req, res);

      expect(mockFirestoreSet).toHaveBeenCalledWith(expect.any(Object));
    });

    test('updated_at に serverTimestamp が設定される', async () => {
      // updated_at はサーバー側の現在時刻を使うため FieldValue.serverTimestamp() を使用
      mockParseNotificationPayload.mockResolvedValueOnce({
        notificationType: 'DID_RENEW',
        transactionInfo: BASE_TX_INFO,
        renewalInfo: RENEWAL_INFO_ON,
      });
      const req = makeReq({ signedPayload: 'test.jws.sig' });
      const res = makeRes();
      await handler(req, res);

      const data = mockFirestoreSet.mock.calls[0][0] as Record<string, unknown>;
      expect(getSubscription(data)?.updated_at).toBe('SERVER_TIMESTAMP');
    });
  });
});
