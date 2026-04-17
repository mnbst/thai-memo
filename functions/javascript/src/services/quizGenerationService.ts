import * as logger from 'firebase-functions/logger';

const THAI_SCRIPT_REGEX = /[\u0E00-\u0E7F]/;
const JAPANESE_SCRIPT_REGEX = /[\u3040-\u30FF\u31F0-\u31FF\u4E00-\u9FFF]/;
const LATIN_SCRIPT_REGEX = /[A-Za-z]/;

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

export interface QuizSentenceSeed {
  thai_text: string;
  pronunciation: string;
  japanese_translation: string;
  word_breakdown: { word: string; pronunciation: string; meaning: string }[];
  key_word?: string;
}

export interface QuizGenerationService {
  generateQuizQuestions(sentences: QuizSentenceSeed[]): Promise<QuizQuestionsResponse>;
}

export const QUIZ_RESPONSE_JSON_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  properties: {
    questions: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: false,
        properties: {
          source_index: {
            type: 'integer',
            description: 'Zero-based index of the input sentence this question was generated from',
          },
          thai_text: {
            type: 'string',
            description: 'Original Thai sentence',
          },
          blank_text: {
            type: 'string',
            description: 'Thai sentence with one word replaced by ___',
          },
          correct_answer: {
            type: 'string',
            description: 'The correct word that fills the blank',
          },
          choices: {
            type: 'array',
            items: { type: 'string' },
            description: '4 choices including the correct answer, shuffled',
          },
          pronunciation: {
            type: 'string',
            description: 'Pronunciation of the correct answer word',
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
          'source_index',
          'thai_text',
          'blank_text',
          'correct_answer',
          'choices',
          'pronunciation',
          'explanation',
          'dummy_reasons',
        ],
      },
    },
  },
  required: ['questions'],
} as const;

export function buildQuizGenerationPrompt(sentences: QuizSentenceSeed[]): string {
  const sentenceList = sentences.map((sentence, index) => {
    let entry = `${index + 1}. 入力ID: ${index}\n   例文: ${sentence.thai_text}\n   日本語訳: ${sentence.japanese_translation}`;
    if (sentence.word_breakdown.length > 0) {
      entry += `\n   語句: ${sentence.word_breakdown.map((word) => `${word.word}=${word.meaning}`).join(' / ')}`;
    }
    if (sentence.key_word) {
      entry += `\n   【穴埋め対象】: ${sentence.key_word}`;
    }
    return entry;
  }).join('\n\n');

  return `タイ語例文ごとに穴埋め4択を1問ずつ作成してください。

${sentenceList}

【ルール】
- ユーザーにはヒント表示前は blank_text と choices のタイ語だけが見える。日本語訳・語句・発音・解説は見えない前提で、周辺タイ語だけから正解が一意に判断できる問題にする
- source_index=入力ID
- 【穴埋め対象】があれば必ず___化。なければ特定的な名詞・動詞・形容詞を選ぶ（除外: 助動詞 จะ/อยาก/ต้อง、コピュラ เป็น/คือ、数詞、程度副詞 มาก/ค่อนข้าง、疑問詞、汎用動詞 มี/ได้）
- 「俺/私」「あなた/君」「彼/彼女」など、日本語訳・話者性別・敬意・一人称/二人称/三人称の知識だけで区別する語は、周辺タイ語に明確な手がかりがない限り空欄対象やダミーにしない
- choices=タイ語4択（正解1＋ダミー3、シャッフル）。correct_answerもタイ語のみ
- pronunciation=正解語の発音（例: สวย → sǔay）
- explanation=日本語で正解理由のみ簡潔に
- dummy_reasons=各ダミーを「単語（発音 / 日本語の意味）：<破綻箇所>」で1行ずつ

【ダミー生成手順】
1. 空欄位置を内部分析: 品詞、役割、直前直後語、意味カテゴリ、項構造
2. ダミーは品詞不一致・項構造不一致・対象カテゴリ不一致で局所破綻する語にする
3. 各候補を blank_text に代入。文法上または意味上入りうる語、意味違いだけ、同カテゴリ置換ならNG
4. NG候補や破綻を短く説明できない候補は、理由を工夫せず必ず別語に差し替える
5. dummy_reasonsに「元の文」「文脈」「質問文」「合わない」「意味が異なる」「別の意味になる」は書かない
6. 「〜を示す文脈には合わない」と説明したくなる候補は意味上入りうるためNG。必ず別語に差し替える
7. 日本語訳や語句ヒントを見れば選べるだけのダミーはNG。ヒントなし画面のタイ語だけで局所破綻が分かる語に差し替える

【ダミーNG例（文として成立するため不可）】
- กิน___ → ข้าว/ผัก/เนื้อ は全て目的語として成立
- อยู่___กล่อง → ใน/บน/ใต้/ข้าง は全て位置関係として成立
- ฉัน___ที่บ้าน → กิน/อ่าน/นอน/ทำงาน は全て自然な文
- เขาซื้อ___ → หนังสือ/เสื้อ/ข้าว/ยา は全て目的語として成立
- ___ไปตลาด → ผม/ฉัน/เรา/เขา は日本語訳や話者情報なしでは一意に選べない

【良いダミー理由例】
- สวย（sǔay / 美しい）：目的語に形容詞が入り不自然
- โรงเรียน（roong-rian / 学校）：食べる対象に場所名詞が入り不自然
- กิน（kin / 食べる）：目的語の位置に動詞が入り文法上不自然

【最終確認】
- choicesは4件、correct_answerは1件だけ
- 3つのダミーは全て、代入時の局所破綻を説明できる
- dummy_reasonsは3件で、不正解選択肢それぞれのタイ語単語を含む`;
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
