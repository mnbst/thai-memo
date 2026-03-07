import { GoogleGenerativeAI, SchemaType } from '@google/generative-ai';
import { GEMINI_MODEL } from '../config/constants';

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

export interface QuizQuestionsResponse {
  questions: Omit<QuizQuestion, 'sentence_id' | 'srs_interval'>[];
}

export class GeminiService {
  private genAI: GoogleGenerativeAI;

  constructor(apiKey: string) {
    this.genAI = new GoogleGenerativeAI(apiKey);
  }

  async generateQuizQuestions(sentences: {
    thai_text: string;
    pronunciation: string;
    japanese_translation: string;
    word_breakdown: { word: string; pronunciation: string; meaning: string }[];
  }[]): Promise<QuizQuestionsResponse> {
    try {
      const model = this.genAI.getGenerativeModel({
        model: GEMINI_MODEL,
        generationConfig: {
          temperature: 0.8,
          maxOutputTokens: 4096,
          responseMimeType: 'application/json',
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
        },
      });

      const sentenceList = sentences.map((s, i) =>
        `${i + 1}. 例文: ${s.thai_text}\n   発音: ${s.pronunciation}\n   日本語訳: ${s.japanese_translation}\n   単語: ${s.word_breakdown.map(w => `${w.word}(${w.meaning})`).join(', ')}`
      ).join('\n\n');

      const prompt = `以下のタイ語例文それぞれについて、穴埋めクイズ問題を1問ずつ作成してください。

${sentenceList}

【ルール】
- 各例文から意味のある単語（名詞・動詞・形容詞など）を1つ選び、___に置き換える
- 助詞や冠詞など簡単すぎる単語は避ける
- 4択の選択肢を作成（正解1つ＋紛らわしいダミー3つ）
- ダミーは文法的には入りうるが意味が異なる単語にする
- 選択肢はシャッフルする
- explanationは日本語で簡潔に（なぜその単語が正解か）`;

      const result = await model.generateContent(prompt);
      const usage = result.response.usageMetadata;
      if (usage) {
        console.log('Gemini token usage', {
          inputTokens: usage.promptTokenCount,
          outputTokens: usage.candidatesTokenCount,
          totalTokens: usage.totalTokenCount,
        });
      }
      const text = result.response.text();
      return JSON.parse(text) as QuizQuestionsResponse;
    } catch (error) {
      console.error('Failed to generate quiz questions', {
        error: error instanceof Error ? error.message : 'Unknown',
      });
      return { questions: [] };
    }
  }
}
