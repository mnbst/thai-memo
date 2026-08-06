/**
 * setUserTier.test.ts
 *
 * 管理者による tier 手動切り替え callable のテスト。
 * Firestore / Auth をモックし、権限チェック・バリデーション・
 * 書き込み内容（tier / クォータ / subscription / 監査ログ）を検証する。
 */

const mockDocGet = jest.fn();
const mockDocSet = jest.fn();
const mockCollectionAdd = jest.fn();
const mockGetUserByEmail = jest.fn();

jest.mock('firebase-functions/v2', () => ({
  https: {
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

jest.mock('firebase-admin', () => ({
  firestore: Object.assign(
    jest.fn(() => ({
      collection: jest.fn(() => ({
        doc: jest.fn(() => ({
          get: mockDocGet,
          set: mockDocSet,
        })),
        add: mockCollectionAdd,
      })),
    })),
    {
      Timestamp: {
        fromMillis: jest.fn((ms: number) => ({
          _seconds: Math.floor(ms / 1000),
          toDate: () => new Date(ms),
        })),
      },
      FieldValue: {
        serverTimestamp: jest.fn(() => 'SERVER_TIMESTAMP'),
      },
    }
  ),
  auth: jest.fn(() => ({ getUserByEmail: mockGetUserByEmail })),
  apps: [],
}));

import { setUserTier } from '../setUserTier';
import {
  FREE_DAILY_SENTENCES,
  FREE_DAILY_QUIZZES,
  PREMIUM_DAILY_SENTENCES,
  PREMIUM_DAILY_QUIZZES,
} from '../constants/quota';

const handler = setUserTier as unknown as (req: unknown) => Promise<{
  uid: string;
  tier: string;
  previous_tier: string;
  expires_at: string | null;
}>;

/** 管理者 claim 付きリクエスト */
function adminRequest(data: Record<string, unknown>) {
  return { auth: { uid: 'admin-uid', token: { admin: true } }, data };
}

/** 対象ユーザーの Firestore ドキュメントをモックに仕込む */
function setUserDoc(data: Record<string, unknown> | null) {
  mockDocGet.mockResolvedValue({
    exists: data !== null,
    data: () => data ?? undefined,
  });
}

/** doc().set() に渡された書き込み内容 */
function writtenData(): Record<string, any> {
  return mockDocSet.mock.calls[0][0];
}

beforeEach(() => {
  jest.clearAllMocks();
  delete process.env.ADMIN_UIDS;
  mockDocSet.mockResolvedValue(undefined);
  mockCollectionAdd.mockResolvedValue({ id: 'grant-1' });
});

describe('権限チェック', () => {
  it('未認証は unauthenticated', async () => {
    await expect(
      handler({ auth: null, data: { uid: 'u1', tier: 'premium' } })
    ).rejects.toMatchObject({ code: 'unauthenticated' });
  });

  it('管理者でないユーザーは permission-denied', async () => {
    await expect(
      handler({ auth: { uid: 'u1', token: {} }, data: { uid: 'u1', tier: 'premium' } })
    ).rejects.toMatchObject({ code: 'permission-denied' });
  });

  it('ADMIN_UIDS に含まれる uid は実行できる', async () => {
    process.env.ADMIN_UIDS = 'other-uid, allowed-uid';
    setUserDoc({ tier: 'free' });
    const result = await handler({
      auth: { uid: 'allowed-uid', token: {} },
      data: { uid: 'target', tier: 'premium' },
    });
    expect(result.tier).toBe('premium');
  });
});

describe('バリデーション', () => {
  it('不正な tier は invalid-argument', async () => {
    await expect(
      handler(adminRequest({ uid: 'u1', tier: 'gold' }))
    ).rejects.toMatchObject({ code: 'invalid-argument' });
  });

  it('uid も email もなければ invalid-argument', async () => {
    await expect(
      handler(adminRequest({ tier: 'premium' }))
    ).rejects.toMatchObject({ code: 'invalid-argument' });
  });

  it('duration_days が範囲外なら invalid-argument', async () => {
    await expect(
      handler(adminRequest({ uid: 'u1', tier: 'premium', duration_days: -1 }))
    ).rejects.toMatchObject({ code: 'invalid-argument' });
  });

  it('存在しないユーザーは not-found', async () => {
    setUserDoc(null);
    await expect(
      handler(adminRequest({ uid: 'ghost', tier: 'premium' }))
    ).rejects.toMatchObject({ code: 'not-found' });
  });
});

describe('premium 付与', () => {
  it('tier とクォータと subscription を書き込む', async () => {
    setUserDoc({ tier: 'free' });
    const result = await handler(
      adminRequest({ uid: 'target', tier: 'premium', duration_days: 7 })
    );

    const data = writtenData();
    expect(data.tier).toBe('premium');
    expect(data.remaining_sentences).toBe(PREMIUM_DAILY_SENTENCES);
    expect(data.remaining_quizzes).toBe(PREMIUM_DAILY_QUIZZES);
    expect(data.subscription.platform).toBe('manual');
    expect(data.subscription.status).toBe('active');
    expect(data.subscription.expires_at).not.toBeNull();
    expect(result.previous_tier).toBe('free');
    expect(result.expires_at).not.toBeNull();
  });

  it('duration_days=0 は無期限（expires_at なし）', async () => {
    setUserDoc({ tier: 'free' });
    const result = await handler(
      adminRequest({ uid: 'target', tier: 'premium', duration_days: 0 })
    );
    expect(writtenData().subscription.expires_at).toBeNull();
    expect(result.expires_at).toBeNull();
  });

  it('tier が変わらない場合はクォータをリセットしない', async () => {
    setUserDoc({ tier: 'premium' });
    await handler(adminRequest({ uid: 'target', tier: 'premium' }));
    expect(writtenData()).not.toHaveProperty('remaining_sentences');
  });

  it('監査ログを tier_grants に残す', async () => {
    setUserDoc({ tier: 'free' });
    await handler(
      adminRequest({ uid: 'target', tier: 'premium', reason: 'キャンペーン' })
    );
    expect(mockCollectionAdd).toHaveBeenCalledWith(
      expect.objectContaining({
        uid: 'target',
        tier: 'premium',
        previous_tier: 'free',
        source: 'admin',
        actor: 'admin-uid',
        reason: 'キャンペーン',
      })
    );
  });

  it('email 指定なら uid を解決する', async () => {
    mockGetUserByEmail.mockResolvedValue({ uid: 'resolved-uid' });
    setUserDoc({ tier: 'free' });
    const result = await handler(
      adminRequest({ email: 'a@example.com', tier: 'premium' })
    );
    expect(result.uid).toBe('resolved-uid');
  });
});

describe('ストア購入との衝突', () => {
  it('有効なストア購入がある場合は failed-precondition', async () => {
    setUserDoc({
      tier: 'premium',
      subscription: { platform: 'ios', status: 'active' },
    });
    await expect(
      handler(adminRequest({ uid: 'target', tier: 'free' }))
    ).rejects.toMatchObject({ code: 'failed-precondition' });
  });

  it('force=true なら上書きできる', async () => {
    setUserDoc({
      tier: 'premium',
      subscription: { platform: 'ios', status: 'active' },
    });
    await handler(adminRequest({ uid: 'target', tier: 'free', force: true }));
    const data = writtenData();
    expect(data.tier).toBe('free');
    expect(data.remaining_sentences).toBe(FREE_DAILY_SENTENCES);
    expect(data.remaining_quizzes).toBe(FREE_DAILY_QUIZZES);
    expect(data.subscription.status).toBe('expired');
  });

  it('期限切れストア購入の subscription は書き換えない', async () => {
    setUserDoc({
      tier: 'free',
      subscription: { platform: 'ios', status: 'expired' },
    });
    await handler(adminRequest({ uid: 'target', tier: 'premium' }));
    const data = writtenData();
    expect(data.tier).toBe('premium');
    expect(data).not.toHaveProperty('subscription');
  });
});
