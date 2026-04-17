jest.mock('firebase-functions/logger', () => ({
  error: jest.fn(),
  info: jest.fn(),
  warn: jest.fn(),
}));

import { GeneratedQuizQuestion, sanitizeQuizQuestion } from '../services/quizGenerationService';

type TestGeneratedQuizQuestion = GeneratedQuizQuestion & {
  japanese_translation: string;
  sentence_pronunciation: string;
};

function makeQuestion(
  overrides: Partial<TestGeneratedQuizQuestion> = {},
): TestGeneratedQuizQuestion {
  return {
    source_index: 0,
    thai_text: 'ฉันกินข้าว',
    blank_text: 'ฉันกิน___',
    correct_answer: 'ข้าว',
    choices: ['ข้าว', 'สวย', 'บ้าน', 'กิน'],
    pronunciation: 'khâao',
    explanation: 'กินの目的語として食べ物を表すข้าวが入ります。',
    japanese_translation: '',
    sentence_pronunciation: '',
    dummy_reasons: [
      'สวย（sǔay / 美しい）：目的語に形容詞が入り不自然',
      'บ้าน（bâan / 家）：食べる対象に場所を表す名詞が入り不自然',
      'กิน（gin / 食べる）：目的語の位置に動詞が入り文法上不自然',
    ],
    ...overrides,
  };
}

describe('quiz generation sanitization', () => {
  test('accepts dummy reasons that explain local grammar or word-class mismatch', () => {
    const sanitized = sanitizeQuizQuestion(makeQuestion());

    expect(sanitized).not.toBeNull();
    expect(sanitized?.choices).toHaveLength(4);
    expect(sanitized?.choices).toEqual(expect.arrayContaining(['ข้าว', 'สวย', 'บ้าน', 'กิน']));
    expect(sanitized?.dummy_reasons).toEqual([
      'สวย（sǔay / 美しい）：目的語に形容詞が入り不自然',
      'บ้าน（bâan / 家）：食べる対象に場所を表す名詞が入り不自然',
      'กิน（gin / 食べる）：目的語の位置に動詞が入り文法上不自然',
    ]);
  });

  test('accepts dummy reasons even when they only say the answer does not match the source sentence', () => {
    const sanitized = sanitizeQuizQuestion(makeQuestion({
      dummy_reasons: [
        'สวย（sǔay / 美しい）：元の文章と合わない',
        'บ้าน（bâan / 家）：食べる対象に場所を表す名詞が入り不自然',
        'กิน（gin / 食べる）：目的語の位置に動詞が入り文法上不自然',
      ],
    }));

    expect(sanitized).not.toBeNull();
    expect(sanitized?.dummy_reasons).toEqual([
      'สวย（sǔay / 美しい）：元の文章と合わない',
      'บ้าน（bâan / 家）：食べる対象に場所を表す名詞が入り不自然',
      'กิน（gin / 食べる）：目的語の位置に動詞が入り文法上不自然',
    ]);
  });

  test('accepts locally specific reasons even when they include a weak wording like 不適切', () => {
    const sanitized = sanitizeQuizQuestion(makeQuestion({
      dummy_reasons: [
        'สวย（sǔay / 美しい）：目的語に形容詞が入り文法上不適切',
        'บ้าน（bâan / 家）：食べる対象に場所を表す名詞が入り不自然',
        'กิน（gin / 食べる）：目的語の位置に動詞が入り文法上不自然',
      ],
    }));

    expect(sanitized).not.toBeNull();
  });

  test('accepts dummy reasons even when a reason says the dummy creates a grammatical sentence', () => {
    const sanitized = sanitizeQuizQuestion(makeQuestion({
      dummy_reasons: [
        'สวย（sǔay / 美しい）：文法上は成立するが元の文章と意味が異なる',
        'บ้าน（bâan / 家）：食べる対象に場所を表す名詞が入り不自然',
        'กิน（gin / 食べる）：目的語の位置に動詞が入り文法上不自然',
      ],
    }));

    expect(sanitized).not.toBeNull();
    expect(sanitized?.dummy_reasons).toEqual([
      'สวย（sǔay / 美しい）：文法上は成立するが元の文章と意味が異なる',
      'บ้าน（bâan / 家）：食べる対象に場所を表す名詞が入り不自然',
      'กิน（gin / 食べる）：目的語の位置に動詞が入り文法上不自然',
    ]);
  });

  test('drops questions instead of filling missing choices from an unverified fallback pool', () => {
    const sanitized = sanitizeQuizQuestion(makeQuestion({
      choices: ['ข้าว', 'สวย', 'บ้าน', 'coffee'],
    }));

    expect(sanitized).toBeNull();
  });
});
