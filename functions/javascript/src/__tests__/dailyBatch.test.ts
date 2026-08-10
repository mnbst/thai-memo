/**
 * dailyBatch.test.ts
 *
 * dailyBatch のクォータリセットロジックを検証する。
 */

const mockUserDocSet = jest.fn();
const mockUserDocRef = jest.fn(() => ({
  set: mockUserDocSet,
}));
const mockCollection = jest.fn(() => ({
  doc: mockUserDocRef,
}));

jest.mock('firebase-functions/v2', () => ({
  https: {
    onRequest: (_config: unknown, handler: unknown) => handler,
  },
  scheduler: {
    onSchedule: (_config: unknown, handler: unknown) => handler,
  },
}));

jest.mock('firebase-admin', () => ({
  firestore: Object.assign(
    jest.fn(() => ({
      collection: mockCollection,
    })),
    {
      Timestamp: {
        fromDate: jest.fn((d: Date) => ({
          _seconds: Math.floor(d.getTime() / 1000),
          toDate: () => d,
        })),
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
  apps: [],
}));

import { duplicateTokenUids, resetQuota } from '../dailyBatch';
import {
  FREE_DAILY_QUIZZES,
  FREE_DAILY_SENTENCES,
  PREMIUM_DAILY_QUIZZES,
  PREMIUM_DAILY_SENTENCES,
} from '../constants/quota';

const LEGACY_BONUS_REMAINING = 10;

function makeUserDoc(
  data: Record<string, unknown>,
  id = 'user-1'
): FirebaseFirestore.QueryDocumentSnapshot {
  return {
    id,
    data: jest.fn(() => data),
  } as unknown as FirebaseFirestore.QueryDocumentSnapshot;
}

/** Firestore Timestamp 相当のモック */
function makeTimestamp(ms: number) {
  return { toMillis: () => ms };
}

describe('resetQuota', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockUserDocSet.mockResolvedValue(undefined);
  });

  test('初回例文フラグが残っていてもfree回数へリセットする', async () => {
    await resetQuota(makeUserDoc({
      tier: 'free',
      is_first_generation: true,
      remaining_sentences: LEGACY_BONUS_REMAINING,
    }));

    expect(mockUserDocSet).toHaveBeenCalledWith(
      {
        remaining_sentences: FREE_DAILY_SENTENCES,
        remaining_quizzes: FREE_DAILY_QUIZZES,
        daily_sentence_generated: false,
        notify_utc_hour: 1,
      },
      { merge: true }
    );
  });

  test('初回クイズフラグが残っていてもfree回数へリセットする', async () => {
    await resetQuota(makeUserDoc({
      tier: 'free',
      is_first_quiz_generation: true,
      remaining_quizzes: LEGACY_BONUS_REMAINING,
    }));

    expect(mockUserDocSet).toHaveBeenCalledWith(
      expect.objectContaining({
        remaining_sentences: FREE_DAILY_SENTENCES,
        remaining_quizzes: FREE_DAILY_QUIZZES,
        daily_sentence_generated: false,
        notify_utc_hour: 1,
      }),
      { merge: true }
    );
  });

  test('初回フラグがないfreeユーザーは通常のfree回数へリセットする', async () => {
    await resetQuota(makeUserDoc({
      tier: 'free',
      remaining_sentences: LEGACY_BONUS_REMAINING,
    }));

    expect(mockUserDocSet).toHaveBeenCalledWith(
      expect.objectContaining({
        remaining_sentences: FREE_DAILY_SENTENCES,
        remaining_quizzes: FREE_DAILY_QUIZZES,
        daily_sentence_generated: false,
        notify_utc_hour: 1,
      }),
      { merge: true }
    );
  });

  test('premiumユーザーは通常のpremium回数へリセットする', async () => {
    await resetQuota(makeUserDoc({
      tier: 'premium',
      remaining_sentences: 0,
    }));

    expect(mockUserDocSet).toHaveBeenCalledWith(
      expect.objectContaining({
        remaining_sentences: PREMIUM_DAILY_SENTENCES,
        remaining_quizzes: PREMIUM_DAILY_QUIZZES,
        daily_sentence_generated: false,
        notify_utc_hour: 1,
      }),
      { merge: true }
    );
  });

  test('期限を24時間以上過ぎたpremiumはfreeに降格しfree回数へリセットする', async () => {
    // ストア通知の取りこぼしで premium が残留したケース
    await resetQuota(makeUserDoc({
      tier: 'premium',
      subscription: {
        status: 'canceled',
        expires_at: makeTimestamp(Date.now() - 25 * 60 * 60 * 1000),
      },
    }));

    expect(mockUserDocSet).toHaveBeenCalledWith(
      expect.objectContaining({
        tier: 'free',
        remaining_sentences: FREE_DAILY_SENTENCES,
        remaining_quizzes: FREE_DAILY_QUIZZES,
        subscription: { status: 'expired' },
      }),
      { merge: true }
    );
  });

  test('期限切れから24時間以内のpremiumは降格しない（更新通知の遅延を許容）', async () => {
    await resetQuota(makeUserDoc({
      tier: 'premium',
      subscription: {
        status: 'active',
        expires_at: makeTimestamp(Date.now() - 60 * 60 * 1000), // 1時間前
      },
    }));

    const writeData = mockUserDocSet.mock.calls[0][0] as Record<string, unknown>;
    expect(writeData.tier).toBeUndefined();
    expect(writeData.remaining_sentences).toBe(PREMIUM_DAILY_SENTENCES);
  });

  test('猶予期間中（grace_period）のpremiumは期限が過ぎていても降格しない', async () => {
    await resetQuota(makeUserDoc({
      tier: 'premium',
      subscription: {
        status: 'grace_period',
        expires_at: makeTimestamp(Date.now() - 48 * 60 * 60 * 1000),
      },
    }));

    const writeData = mockUserDocSet.mock.calls[0][0] as Record<string, unknown>;
    expect(writeData.tier).toBeUndefined();
    expect(writeData.remaining_sentences).toBe(PREMIUM_DAILY_SENTENCES);
  });

  test('猶予期間の上限（30日）を過ぎたgrace_periodは降格する', async () => {
    // GRACE_PERIOD_EXPIRED / EXPIRED 通知を取りこぼしたケース
    await resetQuota(makeUserDoc({
      tier: 'premium',
      subscription: {
        status: 'grace_period',
        platform: 'ios',
        expires_at: makeTimestamp(Date.now() - 31 * 24 * 60 * 60 * 1000),
      },
    }));

    expect(mockUserDocSet).toHaveBeenCalledWith(
      expect.objectContaining({
        tier: 'free',
        remaining_sentences: FREE_DAILY_SENTENCES,
        subscription: { status: 'expired' },
      }),
      { merge: true }
    );
  });

  test('expires_atがないストア購入のpremiumは降格する（期限判定が効かないため）', async () => {
    await resetQuota(makeUserDoc({
      tier: 'premium',
      subscription: { status: 'active', platform: 'android' },
    }));

    expect(mockUserDocSet).toHaveBeenCalledWith(
      expect.objectContaining({
        tier: 'free',
        subscription: { status: 'expired' },
      }),
      { merge: true }
    );
  });

  test('expires_atがない手動付与のpremium（無期限）は降格しない', async () => {
    await resetQuota(makeUserDoc({
      tier: 'premium',
      subscription: { status: 'active', platform: 'manual' },
    }));

    const writeData = mockUserDocSet.mock.calls[0][0] as Record<string, unknown>;
    expect(writeData.tier).toBeUndefined();
    expect(writeData.remaining_sentences).toBe(PREMIUM_DAILY_SENTENCES);
  });

  test('subscriptionフィールドがないpremium（dev手動設定等）は降格しない', async () => {
    await resetQuota(makeUserDoc({
      tier: 'premium',
    }));

    const writeData = mockUserDocSet.mock.calls[0][0] as Record<string, unknown>;
    expect(writeData.tier).toBeUndefined();
    expect(writeData.remaining_sentences).toBe(PREMIUM_DAILY_SENTENCES);
  });

  test('体験トライアル中のfreeはpremiumと同じ回数にリセットする', async () => {
    await resetQuota(makeUserDoc({
      premium_trial_expires_at: makeTimestamp(Date.now() + 24 * 60 * 60 * 1000),
    }));

    const writeData = mockUserDocSet.mock.calls[0][0] as Record<string, unknown>;
    expect(writeData.remaining_sentences).toBe(PREMIUM_DAILY_SENTENCES);
    expect(writeData.remaining_quizzes).toBe(PREMIUM_DAILY_QUIZZES);
    // 何も失っていないので終了は刻まない
    expect(writeData.premium_trial_ended_at).toBeUndefined();
  });

  test('体験が切れた最初のリセットでfreeに戻し、終了時刻を刻む', async () => {
    await resetQuota(makeUserDoc({
      premium_trial_expires_at: makeTimestamp(Date.now() - 60 * 60 * 1000),
    }));

    const writeData = mockUserDocSet.mock.calls[0][0] as Record<string, unknown>;
    expect(writeData.remaining_sentences).toBe(FREE_DAILY_SENTENCES);
    expect(writeData.premium_trial_ended_at).toBeDefined();
  });

  test('体験中の半端な期限はJST 0:00へ切り上げて揃える', async () => {
    // JST 2026-08-12 14:00 = UTC 05:00
    const midDay = Date.UTC(2026, 7, 12, 5, 0, 0);
    await resetQuota(makeUserDoc({
      premium_trial_expires_at: makeTimestamp(midDay),
    }));

    const writeData = mockUserDocSet.mock.calls[0][0] as Record<string, unknown>;
    const aligned = writeData.premium_trial_expires_at as { toDate: () => Date };
    // JST 2026-08-13 00:00 = UTC 2026-08-12 15:00
    expect(aligned.toDate().getTime()).toBe(Date.UTC(2026, 7, 12, 15, 0, 0));
  });

  test('既にJST 0:00に揃っている期限は書き換えない', async () => {
    await resetQuota(makeUserDoc({
      premium_trial_expires_at: makeTimestamp(Date.UTC(2026, 7, 12, 15, 0, 0)),
    }));

    const writeData = mockUserDocSet.mock.calls[0][0] as Record<string, unknown>;
    expect(writeData.premium_trial_expires_at).toBeUndefined();
  });

  test('終了時刻が既にあれば刻み直さない（ダイアログの二重表示を防ぐ）', async () => {
    await resetQuota(makeUserDoc({
      premium_trial_expires_at: makeTimestamp(Date.now() - 60 * 60 * 1000),
      premium_trial_ended_at: makeTimestamp(Date.now() - 30 * 60 * 1000),
    }));

    const writeData = mockUserDocSet.mock.calls[0][0] as Record<string, unknown>;
    expect(writeData.premium_trial_ended_at).toBeUndefined();
  });
});

describe('duplicateTokenUids', () => {
  const user = (
    id: string,
    fcm_token?: string,
    lastActiveMs?: number
  ) => ({
    id,
    data: {
      ...(fcm_token ? { fcm_token } : {}),
      ...(lastActiveMs ? { last_active_at: makeTimestamp(lastActiveMs) } : {}),
    } as Record<string, unknown>,
  });

  test('同じトークンなら最終アクティブが最新の1件だけ残す', () => {
    expect(duplicateTokenUids([
      user('anon-1', 'tok-A', 1000),
      user('linked', 'tok-A', 3000),
      user('anon-2', 'tok-A', 2000),
    ])).toEqual(['anon-2', 'anon-1']);
  });

  test('トークンが違うユーザー同士は掃除しない', () => {
    expect(duplicateTokenUids([
      user('a', 'tok-A', 1000),
      user('b', 'tok-B', 2000),
      user('c'),
    ])).toEqual([]);
  });

  test('アクティブ日時が無いdocは掃除される側になる', () => {
    expect(duplicateTokenUids([
      user('no-activity', 'tok-A'),
      user('active', 'tok-A', 1000),
    ])).toEqual(['no-activity']);
  });
});
