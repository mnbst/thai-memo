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
      },
    }
  ),
  apps: [],
}));

import { resetQuota } from '../dailyBatch';
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

  /** Firestore Timestamp 相当のモック */
  function makeTimestamp(ms: number) {
    return { toMillis: () => ms };
  }

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

  test('subscriptionフィールドがないpremium（dev手動設定等）は降格しない', async () => {
    await resetQuota(makeUserDoc({
      tier: 'premium',
    }));

    const writeData = mockUserDocSet.mock.calls[0][0] as Record<string, unknown>;
    expect(writeData.tier).toBeUndefined();
    expect(writeData.remaining_sentences).toBe(PREMIUM_DAILY_SENTENCES);
  });
});
