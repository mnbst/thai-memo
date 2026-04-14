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
                  },
                  required: ['thai_text', 'blank_text', 'correct_answer', 'choices', 'pronunciation', 'explanation'],
                },
              },
            },
            required: ['questions'],
          },
        } as any,
      });

      const sentenceList = sentences.map((s, i) => {
        const thaiWords = s.word_breakdown
          .map((w) => normalizeText(w.word))
          .filter(isThaiChoiceText);
        let entry = `${i + 1}. 例文: ${s.thai_text}\n   発音: ${s.pronunciation}\n   日本語訳: ${s.japanese_translation}`;
        if (thaiWords.length > 0) {
          entry += `\n   タイ語語彙候補: ${thaiWords.join(', ')}`;
        }
        if (s.key_word) {
          entry += `\n   【穴埋め対象】: ${s.key_word}`;
        }
        return entry;
      }).join('\n\n');

      const prompt = `以下のタイ語例文それぞれについて、穴埋めクイズ問題を1問ずつ作成してください。

${sentenceList}

【ルール】
- 【穴埋め対象】が指定されている場合、必ずその単語を___に置き換える
- 指定がない場合は、意味が特定的な単語（固有の名詞・動詞・形容詞など）を1つ選び、___に置き換える。汎用的な動詞（มี, เป็น, ได้など）は避ける
- 助詞や冠詞など簡単すぎる単語は避ける
- 4択の選択肢を作成（正解1つ＋ダミー3つ）
- correct_answer と choices は必ずタイ語表記の単語だけにする
- choices に日本語訳、英語、ローマ字発音、説明文を混ぜない
- 【重要】ダミー3つは、空欄に入れても文の意味が成立しないことを確認してから採用すること。意味的・文法的に正解になりうる単語は絶対にダミーに含めない
- ダミーは正解と同じ品詞で、意味カテゴリが明確に異なる単語にする（例：正解が食べ物なら別の食べ物ではなく、場所・人・道具などをダミーにする）
- 4つの選択肢の中で正解になりうる単語は厳密に1つだけであること
- 選択肢はシャッフルする
- explanationは日本語で簡潔に（なぜその単語が正解か）`;

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
