/**
 * verifySubscription.test.ts
 *
 * サブスクリプション購入検証 Cloud Function のテスト。
 *
 * テスト戦略:
 * - verifyAppStorePurchase / verifyPlayPurchase はモック化して
 *   ストア API への実際の呼び出しを排除する。
 * - Firestore はモック化して DB アクセスを排除する。
 * - ビジネスロジック（tier 判定・クォータリセット・Firestore 書き込み内容）を検証する。
 */

// ============================================================
// モック定義
// ============================================================

/** App Store 購入検証のモック */
const mockVerifyAppStorePurchase = jest.fn();
/** Google Play 購入検証のモック */
const mockVerifyPlayPurchase = jest.fn();
/**
 * Firestore doc().get() のモック
 * 現在の tier を取得するために使用
 */
const mockDocGet = jest.fn();
/**
 * Firestore doc().set() のモック
 * サブスクリプション情報の書き込みを検証するために使用
 */
const mockDocSet = jest.fn();

/**
 * firebase-functions/v2 モック
 * onCall(config, handler) → handler を返すことでハンドラを直接テスト可能にする
 * HttpsError はエラーコードを持つカスタム例外クラスとして実装する
 */
jest.mock('firebase-functions/v2', () => ({
  https: {
    onRequest: (_config: unknown, handler: unknown) => handler,
    onCall: (_config: unknown, handler: unknown) => handler,
    // HttpsError: code プロパティを持つエラークラス
    // テストでは rejects.toMatchObject({ code: '...' }) で検証する
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
 * verifySubscription が使う Firestore チェーン:
 *   db.collection('users').doc(uid).get()   → 現在 tier 取得
 *   db.collection('users').doc(uid).set(data, { merge: true })  → 書き込み
 */
jest.mock('firebase-admin', () => ({
  firestore: Object.assign(
    jest.fn(() => ({
      collection: jest.fn(() => ({
        doc: jest.fn(() => ({
          get: mockDocGet,
          set: mockDocSet,
        })),
      })),
    })),
    {
      Timestamp: {
        fromDate: jest.fn((d: Date) => ({
          _seconds: Math.floor(d.getTime() / 1000),
          toDate: () => d,
        })),
      },
      FieldValue: {
        serverTimestamp: jest.fn(() => 'SERVER_TIMESTAMP'),
      },
    }
  ),
  apps: [],
}));

/** appStoreServer モック */
jest.mock('../services/appStoreServer', () => ({
  verifyAppStorePurchase: mockVerifyAppStorePurchase,
}));

/** playBilling モック */
jest.mock('../services/playBilling', () => ({
  verifyPlayPurchase: mockVerifyPlayPurchase,
}));

// ============================================================
// テスト本体
// ============================================================
import { verifySubscription } from '../verifySubscription';
import {
  FREE_DAILY_SENTENCES,
  FREE_DAILY_QUIZZES,
  PREMIUM_DAILY_SENTENCES,
  PREMIUM_DAILY_QUIZZES,
} from '../constants/quota';

// ──────────────────────────────────────────────────────────
// テスト用ヘルパー
// ──────────────────────────────────────────────────────────

/**
 * onCall リクエストオブジェクトを作成
 * @param data - リクエストデータ（platform, purchase_token, product_id）
 * @param uid - 認証ユーザーID（undefined の場合は未認証）
 */
function makeRequest(data: Record<string, unknown>, uid?: string) {
  return {
    auth: uid ? { uid } : null,
    data,
  };
}

/** Firestore ユーザードキュメント（データあり）を作成 */
function makeUserDoc(tier: 'free' | 'premium' = 'free') {
  return { data: () => ({ tier }) };
}

// テスト共通の App Store 検証結果
const APPSTORE_ACTIVE_RESULT = {
  valid: true,
  originalTransactionId: 'orig_tx_123',
  expiresAt: new Date(Date.now() + 86_400_000), // 24時間後
  autoRenewing: true,
  status: 'active' as const,
};

const APPSTORE_EXPIRED_RESULT = {
  valid: false,
  originalTransactionId: 'orig_tx_123',
  expiresAt: new Date(Date.now() - 86_400_000), // 24時間前（期限切れ）
  autoRenewing: false,
  status: 'expired' as const,
};

// テスト共通の Google Play 検証結果
const PLAY_ACTIVE_RESULT = {
  valid: true,
  expiresAt: new Date(Date.now() + 86_400_000),
  autoRenewing: true,
  status: 'active' as const,
};

const PLAY_EXPIRED_RESULT = {
  valid: false,
  expiresAt: new Date(Date.now() - 86_400_000),
  autoRenewing: false,
  status: 'expired' as const,
};

// ──────────────────────────────────────────────────────────
// テストスイート
// ──────────────────────────────────────────────────────────

// firebase-functions モックが onCall の第2引数ハンドラを返すため、
// キャストを1か所にまとめて型付きで使用する
const handler = verifySubscription as unknown as (
  request: ReturnType<typeof makeRequest>
) => Promise<{ plan: string; expires_at: string | null; status: string }>;

describe('verifySubscription', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockDocSet.mockResolvedValue(undefined);
    // デフォルト: free ユーザーが存在する状態
    mockDocGet.mockResolvedValue(makeUserDoc('free'));
  });

  // ──────────────────────────────────────────────────────────
  // 認証・バリデーション
  // ──────────────────────────────────────────────────────────
  describe('認証・バリデーション', () => {
    test('Firebase Auth 未認証の場合は unauthenticated エラーをスローする', async () => {
      // uid が存在しない場合は認証エラー（auth がない状態でアクセスされた場合）
      await expect(
        handler(makeRequest({
          platform: 'ios',
          purchase_token: 'token',
          product_id: 'prod_id',
        }))
        // uid を渡さない → auth: null
      ).rejects.toMatchObject({ code: 'unauthenticated' });
    });

    test('platform が欠けている場合は invalid-argument エラーをスローする', async () => {
      await expect(
        handler(makeRequest({
          purchase_token: 'token',
          product_id: 'prod_id',
          // platform: なし
        }, 'user_123'))
      ).rejects.toMatchObject({ code: 'invalid-argument' });
    });

    test('purchase_token が欠けている場合は invalid-argument エラーをスローする', async () => {
      await expect(
        handler(makeRequest({
          platform: 'ios',
          product_id: 'prod_id',
          // purchase_token: なし
        }, 'user_123'))
      ).rejects.toMatchObject({ code: 'invalid-argument' });
    });

    test('product_id が欠けている場合は invalid-argument エラーをスローする', async () => {
      await expect(
        handler(makeRequest({
          platform: 'ios',
          purchase_token: 'token',
          // product_id: なし
        }, 'user_123'))
      ).rejects.toMatchObject({ code: 'invalid-argument' });
    });

    test('platform が android/ios 以外の場合は invalid-argument エラーをスローする', async () => {
      // 不正な platform 値（typo や改ざんへの対応）
      await expect(
        handler(makeRequest({
          platform: 'windows',
          purchase_token: 'token',
          product_id: 'prod_id',
        }, 'user_123'))
      ).rejects.toMatchObject({ code: 'invalid-argument' });
    });
  });

  // ──────────────────────────────────────────────────────────
  // Firestore エラーハンドリング
  // ──────────────────────────────────────────────────────────
  describe('Firestore エラーハンドリング', () => {
    test('Firestore get が失敗した場合は internal エラーをスローする', async () => {
      // DB 障害などで現在 tier が取得できない場合
      mockDocGet.mockRejectedValueOnce(new Error('Firestore unavailable'));

      await expect(
        handler(makeRequest({
          platform: 'ios',
          purchase_token: 'ios_token_abc',
          product_id: 'com.thaimemo.monthly',
        }, 'user_123'))
      ).rejects.toMatchObject({ code: 'internal' });

      // Firestore 書き込みは行われない
      expect(mockDocSet).not.toHaveBeenCalled();
    });
  });

  // ──────────────────────────────────────────────────────────
  // iOS（App Store）購入検証
  // ──────────────────────────────────────────────────────────
  describe('iOS（App Store）購入検証', () => {
    test('アクティブなサブスクリプション → tier=premium / status=active で Firestore に保存される', async () => {
      mockVerifyAppStorePurchase.mockResolvedValueOnce(APPSTORE_ACTIVE_RESULT);

      const result = await handler(makeRequest({
        platform: 'ios',
        purchase_token: 'ios_token_abc',
        product_id: 'com.thaimemo.monthly',
      }, 'user_123'));

      // レスポンス確認
      expect(result.plan).toBe('premium');
      expect(result.status).toBe('active');

      // Firestore 書き込み確認
      const writeData = mockDocSet.mock.calls[0][0] as Record<string, unknown>;
      expect(writeData.tier).toBe('premium');
      const sub = writeData.subscription as Record<string, unknown>;
      expect(sub.platform).toBe('ios');
      expect(sub.status).toBe('active');
    });

    test('期限切れサブスクリプション → tier=free / status=expired で保存される', async () => {
      // 既に期限切れの場合（復元やレシート再確認で expired が返る）
      mockVerifyAppStorePurchase.mockResolvedValueOnce(APPSTORE_EXPIRED_RESULT);

      const result = await handler(makeRequest({
        platform: 'ios',
        purchase_token: 'ios_token_abc',
        product_id: 'com.thaimemo.monthly',
      }, 'user_123'));

      expect(result.plan).toBe('free');
      expect(result.status).toBe('expired');

      const writeData = mockDocSet.mock.calls[0][0] as Record<string, unknown>;
      expect(writeData.tier).toBe('free');
    });

    test('free→premium への tier 変化時はクォータをリセットする', async () => {
      // 新規購入直後: free ユーザーが premium になった場合、
      // remaining_sentences と remaining_quizzes を premium 値にリセット
      mockDocGet.mockResolvedValueOnce(makeUserDoc('free')); // 現在 tier=free
      mockVerifyAppStorePurchase.mockResolvedValueOnce(APPSTORE_ACTIVE_RESULT);

      await handler(makeRequest({
        platform: 'ios',
        purchase_token: 'ios_token_abc',
        product_id: 'com.thaimemo.monthly',
      }, 'user_123'));

      const writeData = mockDocSet.mock.calls[0][0] as Record<string, unknown>;
      expect(writeData.remaining_sentences).toBe(PREMIUM_DAILY_SENTENCES);
      expect(writeData.remaining_quizzes).toBe(PREMIUM_DAILY_QUIZZES);
    });

    test('premium→premium（tier 変化なし）の場合はクォータをリセットしない', async () => {
      // サブスク更新や復元検証の場合、tier が変わらなければクォータを触らない
      // （当日分を消費済みの場合に誤ってリセットされるのを防ぐ）
      mockDocGet.mockResolvedValueOnce(makeUserDoc('premium')); // 現在 tier=premium
      mockVerifyAppStorePurchase.mockResolvedValueOnce(APPSTORE_ACTIVE_RESULT);

      await handler(makeRequest({
        platform: 'ios',
        purchase_token: 'ios_token_abc',
        product_id: 'com.thaimemo.monthly',
      }, 'user_123'));

      const writeData = mockDocSet.mock.calls[0][0] as Record<string, unknown>;
      // クォータフィールドが書き込まれていないことを確認
      expect(writeData.remaining_sentences).toBeUndefined();
      expect(writeData.remaining_quizzes).toBeUndefined();
    });

    test('premium→free への tier 変化時（期限切れ）はクォータを free 値にリセットする', async () => {
      // premium が期限切れになった場合、free のクォータ値でリセット
      mockDocGet.mockResolvedValueOnce(makeUserDoc('premium')); // 現在 tier=premium
      mockVerifyAppStorePurchase.mockResolvedValueOnce(APPSTORE_EXPIRED_RESULT);

      await handler(makeRequest({
        platform: 'ios',
        purchase_token: 'ios_token_abc',
        product_id: 'com.thaimemo.monthly',
      }, 'user_123'));

      const writeData = mockDocSet.mock.calls[0][0] as Record<string, unknown>;
      expect(writeData.remaining_sentences).toBe(FREE_DAILY_SENTENCES);
      expect(writeData.remaining_quizzes).toBe(FREE_DAILY_QUIZZES);
    });

    test('original_transaction_id が Firestore subscription に保存される', async () => {
      // App Store 通知ハンドラがユーザーを検索するために必要なフィールド
      mockVerifyAppStorePurchase.mockResolvedValueOnce(APPSTORE_ACTIVE_RESULT);

      await handler(makeRequest({
        platform: 'ios',
        purchase_token: 'ios_token_abc',
        product_id: 'com.thaimemo.monthly',
      }, 'user_123'));

      const sub = (mockDocSet.mock.calls[0][0] as Record<string, unknown>).subscription as Record<string, unknown>;
      expect(sub.original_transaction_id).toBe('orig_tx_123');
    });

    test('expires_at が Firestore Timestamp として保存される', async () => {
      mockVerifyAppStorePurchase.mockResolvedValueOnce(APPSTORE_ACTIVE_RESULT);

      await handler(makeRequest({
        platform: 'ios',
        purchase_token: 'ios_token_abc',
        product_id: 'com.thaimemo.monthly',
      }, 'user_123'));

      const sub = (mockDocSet.mock.calls[0][0] as Record<string, unknown>).subscription as Record<string, unknown>;
      // Timestamp.fromDate の呼び出し結果（モック: _seconds を持つオブジェクト）
      expect(sub.expires_at).toHaveProperty('_seconds');
    });

    test('product_id が subscription に保存される', async () => {
      mockVerifyAppStorePurchase.mockResolvedValueOnce(APPSTORE_ACTIVE_RESULT);

      await handler(makeRequest({
        platform: 'ios',
        purchase_token: 'ios_token_abc',
        product_id: 'com.thaimemo.monthly',
      }, 'user_123'));

      const sub = (mockDocSet.mock.calls[0][0] as Record<string, unknown>).subscription as Record<string, unknown>;
      expect(sub.product_id).toBe('com.thaimemo.monthly');
    });

    test('verifyAppStorePurchase が失敗した場合は internal エラーをスローする', async () => {
      // App Store API の 401 エラーや Secret Manager のアクセス失敗など
      mockVerifyAppStorePurchase.mockRejectedValueOnce(
        new Error('App Store API error: 401')
      );

      await expect(
        handler(makeRequest({
          platform: 'ios',
          purchase_token: 'ios_token_abc',
          product_id: 'com.thaimemo.monthly',
        }, 'user_123'))
      ).rejects.toMatchObject({ code: 'internal' });

      // API 失敗時は Firestore を更新しない
      expect(mockDocSet).not.toHaveBeenCalled();
    });

    test('Firestore.set() は merge:true で呼ばれる', async () => {
      mockVerifyAppStorePurchase.mockResolvedValueOnce(APPSTORE_ACTIVE_RESULT);

      await handler(makeRequest({
        platform: 'ios',
        purchase_token: 'ios_token_abc',
        product_id: 'com.thaimemo.monthly',
      }, 'user_123'));

      expect(mockDocSet).toHaveBeenCalledWith(expect.any(Object), { merge: true });
    });
  });

  // ──────────────────────────────────────────────────────────
  // Android（Google Play）購入検証
  // ──────────────────────────────────────────────────────────
  describe('Android（Google Play）購入検証', () => {
    test('アクティブなサブスクリプション → tier=premium で Firestore に保存される', async () => {
      mockVerifyPlayPurchase.mockResolvedValueOnce(PLAY_ACTIVE_RESULT);

      const result = await handler(makeRequest({
        platform: 'android',
        purchase_token: 'play_token_xyz',
        product_id: 'com.thaimemo.monthly',
      }, 'user_123'));

      expect(result.plan).toBe('premium');

      const writeData = mockDocSet.mock.calls[0][0] as Record<string, unknown>;
      expect(writeData.tier).toBe('premium');
      const sub = writeData.subscription as Record<string, unknown>;
      expect(sub.platform).toBe('android');
    });

    test('purchase_token が subscription に保存される', async () => {
      // Android では purchase_token を使って RTDN（Real-time Developer Notifications）の
      // ユーザー検索を行うため Firestore への保存が必要
      mockVerifyPlayPurchase.mockResolvedValueOnce(PLAY_ACTIVE_RESULT);

      await handler(makeRequest({
        platform: 'android',
        purchase_token: 'play_token_xyz',
        product_id: 'com.thaimemo.monthly',
      }, 'user_123'));

      const sub = (mockDocSet.mock.calls[0][0] as Record<string, unknown>).subscription as Record<string, unknown>;
      expect(sub.purchase_token).toBe('play_token_xyz');
    });

    test('期限切れサブスクリプション → tier=free で保存される', async () => {
      mockVerifyPlayPurchase.mockResolvedValueOnce(PLAY_EXPIRED_RESULT);

      const result = await handler(makeRequest({
        platform: 'android',
        purchase_token: 'play_token_xyz',
        product_id: 'com.thaimemo.monthly',
      }, 'user_123'));

      expect(result.plan).toBe('free');
    });

    test('verifyPlayPurchase が失敗した場合は internal エラーをスローする', async () => {
      mockVerifyPlayPurchase.mockRejectedValueOnce(
        new Error('Google Play API error: 403')
      );

      await expect(
        handler(makeRequest({
          platform: 'android',
          purchase_token: 'play_token_xyz',
          product_id: 'com.thaimemo.monthly',
        }, 'user_123'))
      ).rejects.toMatchObject({ code: 'internal' });
    });

    test('Android では original_transaction_id は保存されない（purchase_token のみ）', async () => {
      // iOS は original_transaction_id で通知を検索するが
      // Android は purchase_token で RTDN 通知のユーザーを検索する
      mockVerifyPlayPurchase.mockResolvedValueOnce(PLAY_ACTIVE_RESULT);

      await handler(makeRequest({
        platform: 'android',
        purchase_token: 'play_token_xyz',
        product_id: 'com.thaimemo.monthly',
      }, 'user_123'));

      const sub = (mockDocSet.mock.calls[0][0] as Record<string, unknown>).subscription as Record<string, unknown>;
      expect(sub.original_transaction_id).toBeUndefined();
    });
  });
});
