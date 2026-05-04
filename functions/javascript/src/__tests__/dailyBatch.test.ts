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
      }),
      { merge: true }
    );
  });
});
