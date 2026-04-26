jest.mock('firebase-functions/logger', () => ({
  error: jest.fn(),
  info: jest.fn(),
  warn: jest.fn(),
}));

import {
  applyRuleBasedQuizFields,
  buildBlankSentencePronunciation,
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
        key_word: 'ข้าว',
        key_word_pronunciation: 'khâao',
      },
    ]);

    expect(QUIZ_GENERATION_SYSTEM_PROMPT).toContain('【出力】');
    expect(QUIZ_GENERATION_SYSTEM_PROMPT).toContain('【ダミー条件】');
    expect(QUIZ_GENERATION_SYSTEM_PROMPT).toContain('【NG例】');
    expect(QUIZ_GENERATION_SYSTEM_PROMPT).toContain('กิน___ → ข้าว/ผัก/เนื้อ');
    expect(QUIZ_GENERATION_SYSTEM_PROMPT).toContain('類別詞・指示詞・代名詞・語気助詞・前置詞');
    expect(QUIZ_GENERATION_SYSTEM_PROMPT).toContain('___นี้แพงไปไหม → ลูก/อัน/ตัว');
    expect(QUIZ_GENERATION_SYSTEM_PROMPT).toContain('แกง（kɛɛng / カレー）：動詞の位置に名詞が入り文法上不自然');
    expect(QUIZ_GENERATION_SYSTEM_PROMPT).not.toContain('thai_text: ฉันกินข้าว');
    expect(prompt).toContain('thai_text: ฉันกินข้าว');
    expect(prompt).toContain('blank_text: ฉันกิน___');
    expect(prompt).toContain('correct_answer: ข้าว');
    expect(prompt).not.toContain('【出力】');
    expect(prompt).not.toContain('【ダミー条件】');
  });

  test('prepares blank text and correct answer from the key word before model generation', () => {
    const [prepared] = prepareQuizGenerationInputs([
      {
        thai_text: 'ฉันกินข้าว',
        pronunciation: 'chǎn kin khâao',
        japanese_translation: '私はご飯を食べます',
        key_word: 'ข้าว',
        key_word_pronunciation: 'khâao',
      },
    ]);

    expect(prepared).toMatchObject({
      source_index: 0,
      thai_text: 'ฉันกินข้าว',
      blank_text: 'ฉันกิน___',
      correct_answer: 'ข้าว',
      pronunciation: 'khâao',
      correct_answer_meaning: '',
    });
  });

  test('marks a sentence as ready even when the key word pronunciation is missing', () => {
    expect(isQuizSentenceSeedReady({
      thai_text: 'ฉันกินข้าว',
      pronunciation: 'chǎn kin khâao',
      japanese_translation: '私はご飯を食べます',
      key_word: 'ข้าว',
    })).toBe(true);
  });

  test('marks a sentence as not ready when the key word is absent from the Thai text', () => {
    expect(isQuizSentenceSeedReady({
      thai_text: 'ฉันกินข้าว',
      pronunciation: 'chǎn kin khâao',
      japanese_translation: '私はご飯を食べます',
      key_word: 'น้ำ',
      key_word_pronunciation: 'náam',
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
        key_word: 'ข้าว',
        key_word_pronunciation: 'khâao',
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
        makeDraft(),
      ],
    }, [
      {
        thai_text: 'ฉันกินข้าว',
        pronunciation: 'chǎn kin khâao',
        japanese_translation: '私はご飯を食べます',
        key_word: 'ข้าว',
        key_word_pronunciation: 'khâao',
      },
    ]);

    expect(response.questions[0].pronunciation).toBe('khâao');
  });

  test('uses key_word_pronunciation for the answer pronunciation', () => {
    const response = applyRuleBasedQuizFields({
      questions: [
        makeDraft(),
      ],
    }, [
      {
        thai_text: 'อันนี้ถูกกว่าไหมครับ',
        pronunciation: 'an-níi thùuk kwàa mǎi khráp',
        japanese_translation: 'これ、もっと安いですか',
        key_word: 'กว่า',
        key_word_pronunciation: 'kwàa',
      },
    ]);

    expect(response.questions[0].pronunciation).toBe('kwàa');
  });

  test('returns empty pronunciation when key_word_pronunciation is empty', () => {
    const response = applyRuleBasedQuizFields({
      questions: [
        makeDraft(),
      ],
    }, [
      {
        thai_text: 'ฉันกินข้าว',
        pronunciation: 'chǎn kin khâao',
        japanese_translation: '私はご飯を食べます',
        key_word: 'ข้าว',
      },
    ]);

    expect(response.questions[0].pronunciation).toBe('');
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

  test('builds choice pronunciations using Firestore pronunciation for the correct answer', () => {
    const sanitized = sanitizeQuizQuestion(makeQuestion({
      pronunciation: 'firestore-khâao',
    }));

    expect(sanitized).not.toBeNull();
    const choicePronunciations = sanitized!.choice_pronunciations ?? [];
    const pronunciationsByChoice = new Map(
      sanitized!.choices.map((choice, index) => [
        choice,
        choicePronunciations[index],
      ]),
    );
    expect(pronunciationsByChoice.get('ข้าว')).toBe('firestore-khâao');
    expect(pronunciationsByChoice.get('สวย')).toBe('sǔay');
    expect(pronunciationsByChoice.get('บ้าน')).toBe('bâan');
    expect(pronunciationsByChoice.get('กิน')).toBe('gin');
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

  test('builds a blanked sentence pronunciation by direct word pronunciation replacement', () => {
    expect(buildBlankSentencePronunciation(
      'chǎn kin khâao',
      'khâao',
    )).toBe('chǎn kin ___');
  });

  test('builds a blanked sentence pronunciation from key_word_pronunciation', () => {
    expect(buildBlankSentencePronunciation(
      'an-níi thùuk kwàa mǎi khráp',
      'kwàa',
    )).toBe('an-níi thùuk ___ mǎi khráp');
  });

  test('returns empty blanked pronunciation when key_word_pronunciation is absent', () => {
    expect(buildBlankSentencePronunciation(
      'an-níi thùuk kwàa mǎi khráp',
      '',
    )).toBe('');
  });

  test('returns empty blanked pronunciation when key_word_pronunciation is not in the sentence pronunciation', () => {
    expect(buildBlankSentencePronunciation(
      'chan gin khaao',
      'khâao',
    )).toBe('');
  });
});
