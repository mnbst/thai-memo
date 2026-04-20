import {
  computeDefaultSentenceWordLimit,
  DEFAULT_SENTENCES,
  DefaultSentence,
  getDefaultQuizDifficulty,
  isDefaultSentenceMatchingDifficulty,
} from '../constants/defaultQuizQuestions';

function makeSentence(overrides: Partial<DefaultSentence> = {}): DefaultSentence {
  return {
    sentence_id: 'default_test_1',
    thai_text: 'ฉันกินข้าว',
    pronunciation: 'chǎn kin khâao',
    japanese_translation: '私はご飯を食べます',
    word_count: 3,
    key_word: 'กิน',
    key_word_pronunciation: 'kin',
    rank: 50,
    ...overrides,
  };
}

describe('default quiz difficulty filters', () => {
  test('mirrors prompts.py vocabulary levels', () => {
    expect(getDefaultQuizDifficulty(100).label).toBe('入門');
    expect(getDefaultQuizDifficulty(101).label).toBe('初級');
    expect(getDefaultQuizDifficulty(300).label).toBe('初級');
    expect(getDefaultQuizDifficulty(301).label).toBe('初中級');
    expect(getDefaultQuizDifficulty(600).label).toBe('初中級');
    expect(getDefaultQuizDifficulty(601).label).toBe('中級');
    expect(getDefaultQuizDifficulty(1500).label).toBe('中級');
    expect(getDefaultQuizDifficulty(1501).label).toBe('上級');
  });

  test('mirrors prompts.py sentence length hints as numeric limits', () => {
    expect(computeDefaultSentenceWordLimit(0)).toBe(5);
    expect(computeDefaultSentenceWordLimit(100)).toBe(5);
    expect(computeDefaultSentenceWordLimit(300)).toBe(6);
    expect(computeDefaultSentenceWordLimit(600)).toBe(8);
    expect(computeDefaultSentenceWordLimit(1499)).toBe(12);
    expect(computeDefaultSentenceWordLimit(1500)).toBeNull();
  });

  test('rejects default sentences outside vocabulary level or word limit', () => {
    expect(isDefaultSentenceMatchingDifficulty(
      makeSentence({ rank: 100, word_count: 5 }),
      100,
    )).toBe(true);
    expect(isDefaultSentenceMatchingDifficulty(
      makeSentence({ rank: 101, word_count: 5 }),
      100,
    )).toBe(false);
    expect(isDefaultSentenceMatchingDifficulty(
      makeSentence({ rank: 100, word_count: 6 }),
      100,
    )).toBe(false);
  });

  test('adds word counts to generated default sentence records', () => {
    expect(DEFAULT_SENTENCES.length).toBeGreaterThan(0);
    for (const sentence of DEFAULT_SENTENCES) {
      expect(sentence.word_count).toBeGreaterThan(0);
    }
  });
});
