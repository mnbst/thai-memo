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
  word_breakdown: { word: string; pronunciation: string; meaning: string }[];
  key_word?: string;
}

export interface PreparedQuizSentenceSeed {
  source_index: number;
  thai_text: string;
  blank_text: string;
  correct_answer: string;
  pronunciation: string;
  correct_answer_meaning: string;
  japanese_translation: string;
  word_breakdown: { word: string; pronunciation: string; meaning: string }[];
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
    if (sentence.word_breakdown.length > 0) {
      entry += `\n   語句: ${sentence.word_breakdown.map((word) => {
        const details = [word.pronunciation, word.meaning].filter(Boolean).join(' / ');
        return details ? `${word.word}=(${details})` : word.word;
      }).join(' / ')}`;
    }
    return entry;
  }).join('\n\n');
}

export const QUIZ_GENERATION_SYSTEM_PROMPT = `確定済みのタイ語穴埋め問題1問について、ダミー選択肢・理由・解説だけを作成してください。blank_text と correct_answer は変更しません。

【あなたの主作業】
- correct_answer 以外のタイ語ダミーを3件作る
- dummy_reasons に各ダミーが blank_text に入らない局所破綻を書く
- explanation は correct_answer が入る理由だけを日本語で簡潔に書く
【出力形式】
dummies / explanation / dummy_reasons の3項目だけを出力する。

【ルール】
- 空欄位置・正解語はアプリ側で確定済み。正解が機能語・代名詞でも変えない
- ヒント表示前に見えるのは blank_text と「correct_answer + dummies」のタイ語だけ。日本語訳・語句・発音・解説なしでも周辺タイ語だけで3ダミーを除外できるようにする
- 日本語訳、話者性別、敬意、人称だけで区別する語は、周辺タイ語に明確な手がかりがない限りダミーにしない
- dummies はタイ語のみ3件。correct_answer を含めない
- explanation は正解理由だけ。ダミーには触れない
- dummy_reasons は各ダミーを「単語（拼音風ローマ字 / 日本語の意味）：不正解理由」の形式で1行ずつ書く
- dummy_reasons の3行は互いに異なる理由にする。同じ不正解理由が2つ以上のダミーに当てはまる場合、そのダミーは区別力不足なので別の語に差し替える

【ダミー生成手順】
1. blank_text の品詞、役割、直前直後語、意味カテゴリ、項構造を内部分析
2. ダミーは品詞不一致・項構造不一致・対象カテゴリ不一致で局所破綻する語にする
3. 代入して文法上/意味上入りうる語、意味違いだけ、同カテゴリ置換はNG
4. NG候補や不正解理由を短く説明できない候補は、理由を工夫せず必ず別語に差し替える
5. dummy_reasonsに「元の文」「文脈」「質問文」「合わない」「意味が異なる」「別の意味になる」は書かない
6. 「〜を示す文脈には合わない」と説明したくなる候補は意味上入りうるためNG。必ず別語に差し替える

【ダミーNG例（文として成立するため不可）】
- กิน___ → ข้าว/ผัก/เนื้อ は全て目的語として成立
- อยู่___กล่อง → ใน/บน/ใต้/ข้าง は全て位置関係として成立
- ฉัน___ที่บ้าน → กิน/อ่าน/นอน/ทำงาน は全て自然な文
- เขาซื้อ___ → หนังสือ/เสื้อ/ข้าว/ยา は全て目的語として成立
- ___ไปตลาด → ผม/ฉัน/เรา/เขา は日本語訳や話者情報なしでは一意に選べない
- โรงแรม___ดีนะ → นี้/นั้น/นั่น は全て指示詞として成立し一意に選べない

【良いダミー理由例】
- แกง（kɛɛng / カレー）：動詞の位置に名詞が入り文法上不自然
- เบื่อ（bʉ̀a / 飽きる）：目的語の位置に動詞が入り文法上不自然
- เสื้อ（sʉ̂a / 服）：移動動詞の目的語に衣類名詞が入り不自然
- ช้า（cháa / 遅い）：目的語に形容詞が入り不自然
- สอง（sɔ̌ɔng / 二）：場所を示す前置詞句に数詞が入り不自然

【最終確認】
dummies 3件、correct_answer 不含、dummy_reasons 3件。3ダミーすべて不正解理由を説明できること`;

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
      word_breakdown: sentence.word_breakdown,
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

  const breakdown = findWordBreakdown(sentence.word_breakdown, keyWord);
  return {
    word: keyWord,
    pronunciation: normalizeText(breakdown?.pronunciation),
    meaning: breakdown?.meaning ?? '',
  };
}

function findWordBreakdown(
  wordBreakdown: { word: string; pronunciation: string; meaning: string }[],
  target: string,
): { word: string; pronunciation: string; meaning: string } | null {
  return wordBreakdown.find((word) => normalizeText(word.word) === target) ?? null;
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
