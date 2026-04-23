jest.mock('firebase-functions/logger', () => ({
  error: jest.fn(),
  info: jest.fn(),
  warn: jest.fn(),
}));

import {
  applyRuleBasedQuizFields,
  buildQuizGenerationPrompt,
  GeneratedQuizQuestion,
  GeneratedQuizQuestionDraft,
  isQuizSentenceSeedReady,
  prepareQuizGenerationInputs,
  QUIZ_GENERATION_SYSTEM_PROMPT,
  sanitizeQuizQuestion,
} from '../services/quizGenerationService';

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

function makeDraft(
  overrides: Partial<GeneratedQuizQuestionDraft> = {},
): GeneratedQuizQuestionDraft {
  return {
    dummies: ['สวย', 'บ้าน', 'กิน'],
    explanation: 'กินの目的語として食べ物を表すข้าวが入ります。',
    dummy_reasons: [
      'สวย（sǔay / 美しい）：目的語に形容詞が入り不自然',
      'บ้าน（bâan / 家）：食べる対象に場所を表す名詞が入り不自然',
      'กิน（gin / 食べる）：目的語の位置に動詞が入り文法上不自然',
    ],
    correct_answer_pronunciation: 'khâao',
    ...overrides,
  };
}

describe('quiz generation sanitization', () => {
  test('keeps fixed quiz instructions in the system prompt and sentence data in the user prompt', () => {
    const prompt = buildQuizGenerationPrompt([
      {
        thai_text: 'ฉันกินข้าว',
        pronunciation: 'chǎn kin khâao',
        japanese_translation: '私はご飯を食べます',
        word_breakdown: [
          { word: 'ฉัน', pronunciation: 'chǎn', meaning: '私' },
          { word: 'กิน', pronunciation: 'kin', meaning: '食べる' },
          { word: 'ข้าว', pronunciation: 'khâao', meaning: 'ご飯' },
        ],
        key_word: 'ข้าว',
      },
    ]);

    expect(QUIZ_GENERATION_SYSTEM_PROMPT).toContain('【あなたの主作業】');
    expect(QUIZ_GENERATION_SYSTEM_PROMPT).toContain('【発音表記】');
    expect(QUIZ_GENERATION_SYSTEM_PROMPT).toContain('平=記号なし/低=à/降=â/高=á/昇=ǎ');
    expect(QUIZ_GENERATION_SYSTEM_PROMPT).toContain('ไม่=mâi');
    expect(QUIZ_GENERATION_SYSTEM_PROMPT).toContain('สวัสดี=sà-wàt-dii');
    expect(QUIZ_GENERATION_SYSTEM_PROMPT).toContain('ชื่อ=chʉ̂ʉ');
    expect(QUIZ_GENERATION_SYSTEM_PROMPT).toContain('เธอ=thəə');
    expect(QUIZ_GENERATION_SYSTEM_PROMPT).toContain('แม่=mɛ̂ɛ');
    expect(QUIZ_GENERATION_SYSTEM_PROMPT).toContain('ของ=khɔ̌ɔng');
    expect(QUIZ_GENERATION_SYSTEM_PROMPT).toContain('【ダミー生成手順】');
    expect(QUIZ_GENERATION_SYSTEM_PROMPT).toContain('【ダミーNG例（文として成立するため不可）】');
    expect(QUIZ_GENERATION_SYSTEM_PROMPT).toContain('กิน___ → ข้าว/ผัก/เนื้อ');
    expect(QUIZ_GENERATION_SYSTEM_PROMPT).toContain('สวย（sǔay / 美しい）：目的語に形容詞が入り不自然');
    expect(QUIZ_GENERATION_SYSTEM_PROMPT).not.toContain('thai_text: ฉันกินข้าว');
    expect(prompt).toContain('thai_text: ฉันกินข้าว');
    expect(prompt).toContain('blank_text: ฉันกิน___');
    expect(prompt).toContain('correct_answer: ข้าว');
    expect(prompt).not.toContain('【あなたの主作業】');
    expect(prompt).not.toContain('【ダミー生成手順】');
  });

  test('prepares blank text and correct answer from the key word before model generation', () => {
    const [prepared] = prepareQuizGenerationInputs([
      {
        thai_text: 'ฉันกินข้าว',
        pronunciation: 'chǎn kin khâao',
        japanese_translation: '私はご飯を食べます',
        word_breakdown: [
          { word: 'ฉัน', pronunciation: 'chǎn', meaning: '私' },
          { word: 'กิน', pronunciation: 'kin', meaning: '食べる' },
          { word: 'ข้าว', pronunciation: 'khâao', meaning: 'ご飯' },
        ],
        key_word: 'ข้าว',
      },
    ]);

    expect(prepared).toMatchObject({
      source_index: 0,
      thai_text: 'ฉันกินข้าว',
      blank_text: 'ฉันกิน___',
      correct_answer: 'ข้าว',
      pronunciation: 'khâao',
      correct_answer_meaning: 'ご飯',
    });
  });

  test('marks a sentence as ready even when the key word pronunciation is missing (LLM fills it)', () => {
    expect(isQuizSentenceSeedReady({
      thai_text: 'ฉันกินข้าว',
      pronunciation: 'chǎn kin khâao',
      japanese_translation: '私はご飯を食べます',
      word_breakdown: [],
      key_word: 'ข้าว',
    })).toBe(true);
  });

  test('marks a sentence as not ready when the key word is absent from the Thai text', () => {
    expect(isQuizSentenceSeedReady({
      thai_text: 'ฉันกินข้าว',
      pronunciation: 'chǎn kin khâao',
      japanese_translation: '私はご飯を食べます',
      word_breakdown: [
        { word: 'ข้าว', pronunciation: 'khâao', meaning: 'ご飯' },
      ],
      key_word: 'น้ำ',
    })).toBe(false);
  });

  test('applies rule-based blank text and correct answer before sanitization', () => {
    const response = applyRuleBasedQuizFields({
      questions: [
        makeDraft(),
      ],
    }, [
      {
        thai_text: 'ฉันกินข้าว',
        pronunciation: 'chǎn kin khâao',
        japanese_translation: '私はご飯を食べます',
        word_breakdown: [
          { word: 'ฉัน', pronunciation: 'chǎn', meaning: '私' },
          { word: 'กิน', pronunciation: 'kin', meaning: '食べる' },
          { word: 'ข้าว', pronunciation: 'khâao', meaning: 'ご飯' },
        ],
        key_word: 'ข้าว',
      },
    ]);
    const sanitized = sanitizeQuizQuestion(response.questions[0]);

    expect(sanitized).not.toBeNull();
    expect(sanitized).toMatchObject({
      thai_text: 'ฉันกินข้าว',
      blank_text: 'ฉันกิน___',
      correct_answer: 'ข้าว',
      pronunciation: 'khâao',
    });
    expect(sanitized?.choices).toEqual(expect.arrayContaining(['ข้าว', 'สวย', 'บ้าน', 'กิน']));
  });

  test('applies rule-based pronunciation from the prepared input', () => {
    const response = applyRuleBasedQuizFields({
      questions: [
        makeDraft({ correct_answer_pronunciation: 'wrong' }),
      ],
    }, [
      {
        thai_text: 'ฉันกินข้าว',
        pronunciation: 'chǎn kin khâao',
        japanese_translation: '私はご飯を食べます',
        word_breakdown: [
          { word: 'ฉัน', pronunciation: 'chǎn', meaning: '私' },
          { word: 'กิน', pronunciation: 'kin', meaning: '食べる' },
          { word: 'ข้าว', pronunciation: 'khâao', meaning: 'ご飯' },
        ],
        key_word: 'ข้าว',
      },
    ]);

    expect(response.questions[0].pronunciation).toBe('khâao');
  });

  test('falls back to the model-provided pronunciation when word_breakdown is empty', () => {
    const response = applyRuleBasedQuizFields({
      questions: [
        makeDraft({ correct_answer_pronunciation: 'khâao' }),
      ],
    }, [
      {
        thai_text: 'ฉันกินข้าว',
        pronunciation: 'chǎn kin khâao',
        japanese_translation: '私はご飯を食べます',
        word_breakdown: [],
        key_word: 'ข้าว',
      },
    ]);

    expect(response.questions[0].pronunciation).toBe('khâao');
  });

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
