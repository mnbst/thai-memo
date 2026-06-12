jest.mock('firebase-functions/logger', () => ({
  error: jest.fn(),
  info: jest.fn(),
  warn: jest.fn(),
}));

jest.mock('firebase-functions/v2', () => ({
  https: {
    onCall: (_config: unknown, handler: unknown) => handler,
    HttpsError: class HttpsError extends Error {
      constructor(public code: string, message: string) {
        super(message);
      }
    },
  },
}));

jest.mock('firebase-admin', () => ({
  firestore: Object.assign(
    jest.fn(() => ({
      collection: jest.fn(),
    })),
    {
      Timestamp: {
        fromDate: jest.fn((d: Date) => ({
          _seconds: Math.floor(d.getTime() / 1000),
          toDate: () => d,
        })),
      },
      FieldValue: {
        increment: jest.fn((n: number) => n),
        serverTimestamp: jest.fn(),
      },
    },
  ),
  apps: [],
}));

import { buildQuizSources, SelectedSentence } from '../generateQuiz';

function makeSelectedSentence(
  id: string,
  keyWord: string,
  srsInterval: number = -1,
): SelectedSentence {
  return {
    id,
    data: {
      thai_text: `ฉัน${keyWord}ข้าว`,
      pronunciation: 'chǎn test khâao',
      japanese_translation: 'テスト文',
      key_word: keyWord,
      key_word_pronunciation: 'test',
      key_word_meaning: 'テスト',
    },
    srsInterval,
  };
}

describe('buildQuizSources', () => {
  test('初回ユーザー（3文のみ）で3問分のソースを生成できる', () => {
    const sentences = [
      makeSelectedSentence('s1', 'กิน'),
      makeSelectedSentence('s2', 'ดื่ม'),
      makeSelectedSentence('s3', 'อ่าน'),
    ];

    const sources = buildQuizSources(sentences);

    expect(sources).toHaveLength(3);
    const ids = sources.map((s) => s.sentenceId).sort();
    expect(ids).toEqual(['s1', 's2', 's3']);
  });

  test('5文以上ある場合は最大5問に切り詰められる', () => {
    const sentences = Array.from({ length: 7 }, (_, i) =>
      makeSelectedSentence(`s${i}`, `word${i}`),
    );

    const sources = buildQuizSources(sentences);

    expect(sources).toHaveLength(5);
  });

  test('1文のみでも1問分のソースを生成できる', () => {
    const sentences = [makeSelectedSentence('s1', 'กิน')];

    const sources = buildQuizSources(sentences);

    expect(sources).toHaveLength(1);
    expect(sources[0].sentenceId).toBe('s1');
  });

  test('0文の場合は空配列を返す', () => {
    const sources = buildQuizSources([]);

    expect(sources).toHaveLength(0);
  });

  test('各ソースにseed情報が正しくマッピングされる', () => {
    const sentences = [makeSelectedSentence('s1', 'กิน', 3)];

    const [source] = buildQuizSources(sentences);

    expect(source.seed.key_word).toBe('กิน');
    expect(source.seed.thai_text).toContain('กิน');
    expect(source.srsInterval).toBe(3);
    expect(source.japaneseTranslation).toBe('テスト文');
  });
});
