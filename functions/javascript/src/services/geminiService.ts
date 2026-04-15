import { GoogleGenerativeAI, SchemaType } from '@google/generative-ai';

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

type GeneratedQuizQuestion = Omit<QuizQuestion, 'sentence_id' | 'srs_interval'>;

export interface QuizQuestionsResponse {
  questions: GeneratedQuizQuestion[];
}

interface QuizSentenceSeed {
  thai_text: string;
  pronunciation: string;
  japanese_translation: string;
  word_breakdown: { word: string; pronunciation: string; meaning: string }[];
  key_word?: string;
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

export class GeminiService {
  private genAI: GoogleGenerativeAI;
  private modelName: string;

  constructor(apiKey: string, modelName: string) {
    this.genAI = new GoogleGenerativeAI(apiKey);
    this.modelName = modelName;
  }

  async generateQuizQuestions(sentences: QuizSentenceSeed[]): Promise<QuizQuestionsResponse> {
    try {
      const model = this.genAI.getGenerativeModel({
        model: this.modelName,
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        generationConfig: {
          temperature: 0.4,
          maxOutputTokens: 4096,
          responseMimeType: 'application/json',
          thinkingConfig: { thinkingBudget: 0 },
          responseSchema: {
            type: SchemaType.OBJECT,
            properties: {
              questions: {
                type: SchemaType.ARRAY,
                description: 'Quiz questions array, one per input sentence',
                items: {
                  type: SchemaType.OBJECT,
                  properties: {
                    thai_text: {
                      type: SchemaType.STRING,
                      description: 'Original Thai sentence',
                    },
                    blank_text: {
                      type: SchemaType.STRING,
                      description: 'Thai sentence with one word replaced by ___',
                    },
                    correct_answer: {
                      type: SchemaType.STRING,
                      description: 'The correct word that fills the blank',
                    },
                    choices: {
                      type: SchemaType.ARRAY,
                      items: { type: SchemaType.STRING },
                      description: '4 choices including the correct answer, shuffled',
                    },
                    pronunciation: {
                      type: SchemaType.STRING,
                      description: 'Pronunciation of the correct answer word',
                    },
                    explanation: {
                      type: SchemaType.STRING,
                      description: 'Brief explanation in Japanese of why this word fits',
                    },
                    dummy_reasons: {
                      type: SchemaType.ARRAY,
                      items: { type: SchemaType.STRING },
                      description: '不正解の3単語それぞれについて文意が通らない理由を日本語で1行ずつ',
                    },
                  },
                  required: ['thai_text', 'blank_text', 'correct_answer', 'choices', 'pronunciation', 'explanation', 'dummy_reasons'],
                },
              },
            },
            required: ['questions'],
          },
        } as any,
      });

      const sentenceList = sentences.map((s, i) => {
        let entry = `${i + 1}. 例文: ${s.thai_text}\n   日本語訳: ${s.japanese_translation}`;
        if (s.key_word) {
          entry += `\n   【穴埋め対象】: ${s.key_word}`;
        }
        return entry;
      }).join('\n\n');

      const prompt = `以下のタイ語例文それぞれについて、穴埋めクイズ問題を1問ずつ作成してください。

${sentenceList}

【ルール】
- 【穴埋め対象】が指定されている場合、必ずその単語を___に置き換える
- 指定がない場合は意味が特定的な名詞・動詞・形容詞を選ぶ。助動詞（จะ/อยาก/ต้อง）・コピュラ（เป็น/คือ）・数詞・程度副詞（มาก/ค่อนข้าง）・疑問詞・汎用動詞（มี/ได้）は穴埋め対象にしない
- 4択（正解1つ＋ダミー3つ）。choices・correct_answer はタイ語表記のみ（日本語訳・英語・ローマ字不可）
- 正解になりうる選択肢は厳密に1つ。ダミーは品詞または意味カテゴリを正解と大きく変える
- choices はシャッフル
- explanation は日本語で簡潔に（正解の理由のみ、他の選択肢に言及しない）
- dummy_reasons：各ダミー単語について「単語（拼音風ローマ字 / 日本語の意味）を入れると〜」の形式で文意が通らない理由を1行ずつ
  例: "ช้า（chà / 遅い）を入れると「彼は遅いを食べる」となり意味が通らない"

【ダミーNG一覧（文意が通ってしまうパターン）】
- 人称代名詞: ___ กินข้าว → ผม/ฉัน/เขา/เธอ/ท่าน どれも主語として成立
- 同カテゴリ名詞: กิน___ → ข้าว/ผัก/เนื้อ、ดื่ม___ → กาแฟ/ชา/น้ำ、ไปที่___ → บ้าน/โรงเรียน/ตลาด、เสื้อ___ → แดง/ขาว/ดำ どれも意味が成立
- 類義語動詞: อ่าน↔ดู、ไป↔เดิน（文脈次第で成立）
- 助動詞互換: เธอ___จะไป → จะ/อยาก/ต้องการ どれも意志・希望として成立
- コピュラ互換: เขา___ครู → เป็น/คือ どちらも「〜だ」として成立

対処: 品詞だけでなく意味カテゴリを大きく変える（人→物、食べ物→場所、移動動詞→感情動詞など）`;

      const result = await model.generateContent(prompt);
      const usage = result.response.usageMetadata;
      if (usage) {
        const inputTokens = usage.promptTokenCount ?? 0;
        const outputTokens = usage.candidatesTokenCount ?? 0;
        const totalTokens = usage.totalTokenCount ?? 0;
        const thoughtsTokens = totalTokens - inputTokens - outputTokens;
        const billedOutput = outputTokens + thoughtsTokens;
        const costUsd = (inputTokens * 0.30 + billedOutput * 2.50) / 1_000_000;
        console.log('Gemini token usage', {
          keyWord: sentences[0]?.key_word ?? null,
          inputTokens,
          outputTokens,
          thoughtsTokens,
          billedOutput,
          totalTokens,
          costUsd: costUsd.toFixed(6),
        });
      }
      const text = result.response.text();
      const parsed = JSON.parse(text) as QuizQuestionsResponse;
      return this.sanitizeQuizQuestions(
        parsed,
        this.buildThaiChoicePoolFromSentences(sentences),
      );
    } catch (error) {
      console.error('Failed to generate quiz questions', {
        error: error instanceof Error ? error.message : 'Unknown',
      });
      return { questions: [] };
    }
  }


  private sanitizeQuizQuestions(
    response: QuizQuestionsResponse,
    seedPool: string[],
  ): QuizQuestionsResponse {
    const generatedPool = uniqueTexts([
      ...seedPool,
      ...response.questions.map((question) => question.correct_answer),
      ...response.questions.flatMap((question) => question.choices),
    ]).filter(isThaiChoiceText);

    return {
      questions: response.questions.flatMap((question) => {
        const sanitized = this.sanitizeQuizQuestion(question, generatedPool);
        return sanitized ? [sanitized] : [];
      }),
    };
  }

  private sanitizeQuizQuestion(
    question: GeneratedQuizQuestion,
    fallbackPool: string[],
  ): GeneratedQuizQuestion | null {
    const correctAnswer = normalizeText(question.correct_answer);
    if (!isThaiChoiceText(correctAnswer)) {
      console.warn('Dropping quiz question due to non-Thai correct answer', {
        correctAnswer: question.correct_answer,
      });
      return null;
    }

    const choices = uniqueTexts([
      correctAnswer,
      ...question.choices.filter(isThaiChoiceText),
      ...fallbackPool.filter((choice) => choice !== correctAnswer),
    ]).slice(0, 4);

    if (choices.length < 4) {
      console.warn('Dropping quiz question due to insufficient Thai choices', {
        correctAnswer,
        choices: question.choices,
      });
      return null;
    }

    return {
      ...question,
      thai_text: normalizeText(question.thai_text),
      blank_text: normalizeText(question.blank_text),
      correct_answer: correctAnswer,
      choices: this.shuffleChoices(choices),
      pronunciation: normalizeText(question.pronunciation),
      explanation: normalizeText(question.explanation),
      japanese_translation: normalizeText(question.japanese_translation),
      sentence_pronunciation: normalizeText(question.sentence_pronunciation),
    };
  }

  private buildThaiChoicePoolFromSentences(sentences: QuizSentenceSeed[]): string[] {
    return uniqueTexts(
      sentences.flatMap((sentence) => [
        sentence.key_word ?? '',
        ...sentence.word_breakdown.map((word) => word.word),
      ]),
    ).filter(isThaiChoiceText);
  }

  private shuffleChoices(choices: string[]): string[] {
    return [...choices].sort(() => Math.random() - 0.5);
  }
}
