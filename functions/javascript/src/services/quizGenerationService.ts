import * as logger from 'firebase-functions/logger';

const THAI_SCRIPT_REGEX = /[\u0E00-\u0E7F]/;
const JAPANESE_SCRIPT_REGEX = /[\u3040-\u30FF\u31F0-\u31FF\u4E00-\u9FFF]/;
const LATIN_SCRIPT_REGEX = /[A-Za-z]/;
const BLANK_TEXT = '___';

export interface QuizQuestion {
  sentence_id: string;
  thai_text: string;
  blank_text: string;
  correct_answer: string;
  choices: string[];
  pronunciation: string;
  explanation: string;
  srs_interval: number;
  japanese_translation: string;
  sentence_pronunciation: string;
  blank_sentence_pronunciation: string;
  dummy_reasons: string[];
}

export interface GeneratedQuizQuestion {
  source_index?: number;
  thai_text: string;
  blank_text: string;
  correct_answer: string;
  choices: string[];
  pronunciation: string;
  explanation: string;
  japanese_translation?: string;
  sentence_pronunciation?: string;
  dummy_reasons: string[];
}

export interface QuizQuestionsResponse {
  questions: GeneratedQuizQuestion[];
}

export interface GeneratedQuizQuestionDraft {
  dummies: string[];
  explanation: string;
  dummy_reasons: string[];
}

export type QuizGenerationModelResponse = GeneratedQuizQuestionDraft;

export interface QuizSentenceSeed {
  thai_text: string;
  pronunciation: string;
  japanese_translation: string;
  key_word?: string;
  key_word_pronunciation?: string;
}

export interface PreparedQuizSentenceSeed {
  source_index: number;
  thai_text: string;
  blank_text: string;
  correct_answer: string;
  pronunciation: string;
  correct_answer_meaning: string;
  japanese_translation: string;
}

export interface QuizGenerationService {
  generateQuizQuestions(sentences: QuizSentenceSeed[]): Promise<QuizQuestionsResponse>;
}

export const QUIZ_RESPONSE_JSON_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  properties: {
    dummies: {
      type: 'array',
      items: { type: 'string' },
      description: 'Exactly 3 Thai dummy choices that do not include the correct answer',
    },
    explanation: {
      type: 'string',
      description: 'Brief explanation in Japanese of why this word fits',
    },
    dummy_reasons: {
      type: 'array',
      items: { type: 'string' },
      description: '不正解の3単語それぞれについて入らない理由を日本語で1行ずつ',
    },
  },
  required: [
    'dummies',
    'explanation',
    'dummy_reasons',
  ],
} as const;

function buildPreparedSentenceList(sentences: QuizSentenceSeed[]): string {
  const preparedSentences = prepareQuizGenerationInputs(sentences);
  return preparedSentences.map((sentence, index) => {
    let entry = `${index + 1}. thai_text: ${sentence.thai_text}` +
      `\n   blank_text: ${sentence.blank_text}` +
      `\n   correct_answer: ${sentence.correct_answer}` +
      `\n   correct_answer_pronunciation: ${sentence.pronunciation}` +
      `\n   correct_answer_meaning: ${sentence.correct_answer_meaning || '未指定'}` +
      `\n   日本語訳: ${sentence.japanese_translation}`;
    return entry;
  }).join('\n\n');
}

export const QUIZ_GENERATION_SYSTEM_PROMPT = `確定済みのタイ語穴埋め問題1問について、ダミー選択肢・理由・解説だけを作成してください。
blank_text と correct_answer は変更しません。

【出力】
dummies / explanation / dummy_reasons の3項目のみ。
- dummies: correct_answer 以外のタイ語3件
- explanation: correct_answer が入る理由だけを日本語で簡潔に書く。ダミーには触れない
- dummy_reasons: 各ダミーを「単語（ローマ字 / 日本語）：不正解理由」の形式で1行ずつ書く

【最重要ルール】
ヒント表示前に見えるのは blank_text と「correct_answer + dummies」のタイ語だけ。
日本語訳・語句・発音・解説なしでも、周辺タイ語だけで3ダミーを除外できる必要がある。

【ダミー条件】
- 品詞不一致、項構造不一致、対象カテゴリ不一致など、局所的に破綻する語を選ぶ
- 代入して文法上/意味上入りうる語、意味違いだけの語、同カテゴリ置換は不可
- 日本語訳、話者性別、敬意、人称だけで区別する語は不可
- 類別詞・指示詞・代名詞・語気助詞・前置詞など、複数候補が成立しやすい機能語同士をダミーにしない
- 正解が類別詞の場合、他の類別詞ではなく、動詞・形容詞・場所名詞など別品詞を優先する
- dummy_reasons の3行は互いに異なる理由にする。同じ理由になる候補は差し替える

【理由の禁止表現】
dummy_reasons に「元の文」「文脈」「質問文」「合わない」「意味が異なる」「別の意味になる」「より一般的」は書かない。
「〜を示す文脈には合わない」「こちらの方が自然」と説明したくなる候補は、意味上入りうるため不可。

【NG例】
- กิน___ → ข้าว/ผัก/เนื้อ は全て目的語として成立
- อยู่___กล่อง → ใน/บน/ใต้/ข้าง は全て位置関係として成立
- ___ไปตลาด → ผม/ฉัน/เรา/เขา は話者情報なしでは一意に選べない
- โรงแรม___ดีนะ → นี้/นั้น/นั่น は指示詞として複数成立
- ___นี้แพงไปไหม → ลูก/อัน/ตัว は類別詞として複数成立
- ฉันมีแมวสอง___ → ตัว/ตน は分類だけで落とす問題として曖昧

【良い理由例】
- แกง（kɛɛng / カレー）：動詞の位置に名詞が入り文法上不自然
- เบื่อ（bʉ̀a / 飽きる）：目的語の位置に動詞が入り文法上不自然
- เสื้อ（sʉ̂a / 服）：移動動詞の目的語に衣類名詞が入り不自然
- ช้า（cháa / 遅い）：目的語に形容詞が入り不自然
- สอง（sɔ̌ɔng / 二）：場所を示す前置詞句に数詞が入り不自然

【最終確認】
dummies 3件、correct_answer 不含、dummy_reasons 3件。
3ダミーすべて、周辺タイ語だけで除外できること。`;

export function buildQuizGenerationPrompt(sentences: QuizSentenceSeed[]): string {
  const sentenceList = buildPreparedSentenceList(sentences);

  return `以下のタイ語穴埋め問題について、システム指示に従って出力してください。

${sentenceList}`;
}

export function prepareQuizGenerationInputs(
  sentences: QuizSentenceSeed[],
): PreparedQuizSentenceSeed[] {
  return sentences.map((sentence, sourceIndex) => {
    const target = resolveBlankTarget(sentence);
    const thaiText = normalizeText(sentence.thai_text);
    const correctAnswer = target?.word ?? normalizeText(sentence.key_word);

    return {
      source_index: sourceIndex,
      thai_text: thaiText,
      blank_text: buildBlankText(thaiText, correctAnswer) ?? thaiText,
      correct_answer: correctAnswer,
      pronunciation: target?.pronunciation ?? '',
      correct_answer_meaning: target?.meaning ?? '',
      japanese_translation: normalizeText(sentence.japanese_translation),
    };
  });
}

export function isQuizSentenceSeedReady(sentence: QuizSentenceSeed): boolean {
  const [prepared] = prepareQuizGenerationInputs([sentence]);
  return Boolean(
    prepared?.correct_answer &&
    prepared.blank_text.includes(BLANK_TEXT),
  );
}

export function applyRuleBasedQuizFields(
  response: { questions: GeneratedQuizQuestionDraft[] },
  sentences: QuizSentenceSeed[],
): QuizQuestionsResponse {
  const preparedSentences = prepareQuizGenerationInputs(sentences);

  return {
    questions: response.questions.map((question, responseIndex) => {
      const prepared = preparedSentences[responseIndex];

      if (!prepared?.correct_answer || !prepared.blank_text.includes(BLANK_TEXT)) {
        return {
          source_index: responseIndex,
          thai_text: prepared?.thai_text ?? '',
          blank_text: prepared?.blank_text ?? '',
          correct_answer: prepared?.correct_answer ?? '',
          choices: question.dummies,
          pronunciation: prepared?.pronunciation ?? '',
          explanation: question.explanation,
          dummy_reasons: question.dummy_reasons,
        };
      }

      return {
        source_index: responseIndex,
        thai_text: prepared.thai_text,
        blank_text: prepared.blank_text,
        correct_answer: prepared.correct_answer,
        choices: [prepared.correct_answer, ...question.dummies],
        pronunciation: prepared.pronunciation,
        explanation: question.explanation,
        dummy_reasons: question.dummy_reasons,
      };
    }),
  };
}

function resolveBlankTarget(
  sentence: QuizSentenceSeed,
): { word: string; pronunciation: string; meaning: string } | null {
  const thaiText = normalizeText(sentence.thai_text);
  const keyWord = normalizeText(sentence.key_word);

  if (!keyWord) return null;
  if (!buildBlankText(thaiText, keyWord)) return null;

  return {
    word: keyWord,
    pronunciation: normalizeText(sentence.key_word_pronunciation),
    meaning: '',
  };
}

function buildBlankText(thaiText: string, answer: string): string | null {
  if (!thaiText || !answer) return null;

  const answerIndex = thaiText.indexOf(answer);
  if (answerIndex === -1) return null;

  return [
    thaiText.slice(0, answerIndex),
    BLANK_TEXT,
    thaiText.slice(answerIndex + answer.length),
  ].join('');
}

function normalizeText(value: string | null | undefined): string {
  return (value ?? '').trim().replace(/\s+/g, ' ');
}

function isThaiChoiceText(value: string): boolean {
  const text = normalizeText(value);
  return text.length > 0 &&
    THAI_SCRIPT_REGEX.test(text) &&
    !JAPANESE_SCRIPT_REGEX.test(text) &&
    !LATIN_SCRIPT_REGEX.test(text);
}

function uniqueTexts(values: string[]): string[] {
  const seen = new Set<string>();
  const result: string[] = [];

  for (const value of values) {
    const normalized = normalizeText(value);
    if (!normalized || seen.has(normalized)) {
      continue;
    }
    seen.add(normalized);
    result.push(normalized);
  }

  return result;
}

export function sanitizeQuizQuestions(response: QuizQuestionsResponse): QuizQuestionsResponse {
  return {
    questions: response.questions.flatMap((question) => {
      const sanitized = sanitizeQuizQuestion(question);
      return sanitized ? [sanitized] : [];
    }),
  };
}

export function buildBlankSentencePronunciation(
  sentencePronunciation: string,
  keyWordPronunciation?: string,
): string {
  const normalizedSentencePronunciation = normalizeText(sentencePronunciation);
  const normalizedKeyWordPronunciation = normalizeText(keyWordPronunciation);
  if (!normalizedSentencePronunciation || !normalizedKeyWordPronunciation) return '';
  if (!normalizedSentencePronunciation.includes(normalizedKeyWordPronunciation)) return '';
  return normalizedSentencePronunciation.replace(normalizedKeyWordPronunciation, BLANK_TEXT);
}

export function sanitizeQuizQuestion(
  question: GeneratedQuizQuestion,
): GeneratedQuizQuestion | null {
  const correctAnswer = normalizeText(question.correct_answer);
  if (!isThaiChoiceText(correctAnswer)) {
    logger.warn('Dropping quiz question due to non-Thai correct answer', {
      event: 'quiz_question_dropped_non_thai_correct_answer',
      correctAnswer: question.correct_answer,
    });
    return null;
  }

  const choices = uniqueTexts([
    correctAnswer,
    ...question.choices.filter(isThaiChoiceText),
  ]).slice(0, 4);

  if (choices.length < 4) {
    logger.warn('Dropping quiz question due to insufficient Thai choices', {
      event: 'quiz_question_dropped_insufficient_thai_choices',
      correctAnswer,
      choices: question.choices,
    });
    return null;
  }

  const dummyReasons = sanitizeDummyReasons(question, correctAnswer, choices);
  if (dummyReasons === null) {
    logger.warn('Dropping quiz question due to incomplete dummy reasons', {
      event: 'quiz_question_dropped_incomplete_dummy_reasons',
      correctAnswer,
      choices: question.choices,
      dummyReasons: question.dummy_reasons,
    });
    return null;
  }

  return {
    ...question,
    source_index: Number.isInteger(question.source_index) ? question.source_index : undefined,
    thai_text: normalizeText(question.thai_text),
    blank_text: normalizeText(question.blank_text),
    correct_answer: correctAnswer,
    choices: shuffleChoices(choices),
    pronunciation: normalizeText(question.pronunciation),
    explanation: normalizeText(question.explanation),
    japanese_translation: normalizeText(question.japanese_translation),
    sentence_pronunciation: normalizeText(question.sentence_pronunciation),
    dummy_reasons: dummyReasons,
  };
}

function sanitizeDummyReasons(
  question: GeneratedQuizQuestion,
  correctAnswer: string,
  choices: string[],
): string[] | null {
  const reasons = uniqueTexts(
    (Array.isArray(question.dummy_reasons) ? question.dummy_reasons : [])
      .map((reason) => normalizeText(reason)),
  );
  const dummyChoices = choices.filter((choice) => choice !== correctAnswer);

  if (dummyChoices.length !== 3 || reasons.length < 3) {
    return null;
  }

  const matchedReasons = dummyChoices.map((choice) => {
    const reason = reasons.find((candidate) => candidate.includes(choice));
    return reason ?? null;
  });

  if (matchedReasons.some((reason) => reason === null)) {
    return null;
  }

  return matchedReasons as string[];
}

function shuffleChoices(choices: string[]): string[] {
  return [...choices].sort(() => Math.random() - 0.5);
}
