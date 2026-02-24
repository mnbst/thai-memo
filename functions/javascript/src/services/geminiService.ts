import { GoogleGenerativeAI, SchemaType } from '@google/generative-ai';
import { ThaiSentence } from '../types/thaiSentence';
import {
  GEMINI_MODEL,
  API_TEMPERATURE,
  API_MAX_TOKENS,
  TOPICS,
  STYLES,
  POLITENESS_LEVELS,
  GRAMMAR_FOCUSES,
  VOCAB_LEVELS,
  SENTENCE_LENGTHS,
  EMOTIONS,
  LEARNING_PURPOSES,
  TONE_DENSITIES,
  getSentenceGenerationPrompt,
} from '../config/constants';

export interface ReviewNotes {
  grammar_points: { label: string; detail: string }[];
  pronunciation_tips: { thai: string; roman: string; tip: string }[];
  related_expressions: { thai: string; roman: string; meaning: string }[];
}

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

  async generateSentence(params: {
    topic?: string;
    style?: string;
    politeness?: string;
    grammarFocus?: string;
    vocabLevel?: string;
    sentenceLength?: string;
    emotion?: string;
    learningPurpose?: string;
    toneDensity?: string;
    customPrompt?: string;
  } = {}): Promise<ThaiSentence> {
    const apiStartTime = Date.now();

    try {
      const rand = <T>(arr: T[]): T => arr[Math.floor(Math.random() * arr.length)];

      const topic = params.topic || rand(TOPICS);
      const style = params.style || rand(STYLES);
      const politeness = params.politeness || rand(POLITENESS_LEVELS);
      const grammarFocus = params.grammarFocus || rand(GRAMMAR_FOCUSES);
      const vocabLevel = params.vocabLevel || rand(VOCAB_LEVELS);
      const sentenceLength = params.sentenceLength || rand(SENTENCE_LENGTHS);
      const emotion = params.emotion || rand(EMOTIONS);
      const learningPurpose = params.learningPurpose || rand(LEARNING_PURPOSES);
      const toneDensity = params.toneDensity || rand(TONE_DENSITIES);

      console.log('Gemini API call started', {
        topic,
        style,
        politeness,
        grammarFocus,
        vocabLevel,
        sentenceLength,
        emotion,
        learningPurpose,
        toneDensity,
      });

      // Initialize model with JSON schema
      const model = this.genAI.getGenerativeModel({
        model: GEMINI_MODEL,
        generationConfig: {
          temperature: API_TEMPERATURE,
          maxOutputTokens: API_MAX_TOKENS,
          responseMimeType: 'application/json',
          responseSchema: {
            type: SchemaType.OBJECT,
            properties: {
              thai_text: {
                type: SchemaType.STRING,
                description: 'The Thai sentence text',
                nullable: false,
              },
              pronunciation: {
                type: SchemaType.STRING,
                description: 'Pinyin-style romanized pronunciation with tone marks',
                nullable: false,
              },
              japanese_translation: {
                type: SchemaType.STRING,
                description: 'Japanese translation of the Thai sentence',
                nullable: false,
              },
              word_breakdown: {
                type: SchemaType.ARRAY,
                items: {
                  type: SchemaType.OBJECT,
                  properties: {
                    word: {
                      type: SchemaType.STRING,
                      description: 'Thai word',
                      nullable: false,
                    },
                    pronunciation: {
                      type: SchemaType.STRING,
                      description: 'Pinyin-style romanized pronunciation with tone marks',
                      nullable: false,
                    },
                    meaning: {
                      type: SchemaType.STRING,
                      description: 'Japanese meaning of the word',
                      nullable: false,
                    },
                    grammatical_role: {
                      type: SchemaType.STRING,
                      description: 'Grammatical role of the word',
                      nullable: true,
                    },
                    syllables: {
                      type: SchemaType.ARRAY,
                      items: {
                        type: SchemaType.STRING,
                      },
                      description: 'Syllable breakdown (tone analysis will be done on app side)',
                      nullable: true,
                    },
                  },
                  required: ['word', 'pronunciation', 'meaning'],
                },
                description: 'Array of word breakdowns',
                nullable: false,
              },
              context: {
                type: SchemaType.OBJECT,
                properties: {
                  topic: {
                    type: SchemaType.STRING,
                    description: 'Topic of this sentence',
                    nullable: true,
                  },
                  style: {
                    type: SchemaType.STRING,
                    description: 'Writing style used (e.g. news, colloquial)',
                    nullable: true,
                  },
                  emotion: {
                    type: SchemaType.STRING,
                    description: 'Emotion or tone of the sentence',
                    nullable: true,
                  },
                  usage_scenarios: {
                    type: SchemaType.STRING,
                    description: 'Usage scenarios or contexts',
                    nullable: true,
                  },
                  cultural_notes: {
                    type: SchemaType.STRING,
                    description: 'Cultural notes or background',
                    nullable: true,
                  },
                },
              },
            },
            required: [
              'thai_text',
              'pronunciation',
              'japanese_translation',
              'word_breakdown',
            ],
          },
        },
      });

      // Generate content
      const prompt = getSentenceGenerationPrompt({
        topic,
        style,
        politeness,
        grammarFocus,
        vocabLevel,
        sentenceLength,
        emotion,
        learningPurpose,
        toneDensity,
        customPrompt: params.customPrompt,
      });
      const result = await model.generateContent(prompt);
      const response = result.response;
      const text = response.text();

      const apiLatency = Date.now() - apiStartTime;

      console.log('Gemini API call completed', {
        latencyMs: apiLatency,
        responseLength: text.length,
      });

      // Validate response before parsing
      if (!text || text.trim().length === 0) {
        throw new Error('Empty response from Gemini API');
      }

      // Parse JSON response with better error handling
      let sentence: ThaiSentence;
      try {
        sentence = JSON.parse(text);
      } catch (parseError) {
        console.error('JSON parse failed', {
          responsePreview: text.substring(0, 500),
          responseSuffix: text.substring(Math.max(0, text.length - 200)),
          fullResponseLength: text.length,
          parseError: parseError instanceof Error ? parseError.message : 'Unknown',
        });
        throw new Error(`Invalid JSON response: ${parseError instanceof Error ? parseError.message : 'Unknown'}`);
      }

      return sentence;
    } catch (error) {
      const apiLatency = Date.now() - apiStartTime;

      console.error('Gemini API call failed', {
        latencyMs: apiLatency,
        error: error instanceof Error ? error.message : 'Unknown error',
      });

      if (error instanceof Error) {
        throw new Error(`GEMINI_API_ERROR: ${error.message}`);
      }
      throw new Error('GEMINI_API_ERROR: Unknown error');
    }
  }

  async generateReviewNotes(sentence: {
    thai_text: string;
    pronunciation: string;
    japanese_translation: string;
  }): Promise<ReviewNotes> {
    try {
      const model = this.genAI.getGenerativeModel({
        model: GEMINI_MODEL,
        generationConfig: {
          temperature: 0.7,
          maxOutputTokens: 4096,
          responseMimeType: 'application/json',
          responseSchema: {
            type: SchemaType.OBJECT,
            properties: {
              grammar_points: {
                type: SchemaType.ARRAY,
                description: 'Key grammar points (1-2 items)',
                items: {
                  type: SchemaType.OBJECT,
                  properties: {
                    label: { type: SchemaType.STRING, description: 'Short label e.g. 語順, 助詞' },
                    detail: { type: SchemaType.STRING, description: 'Explanation in Japanese, Thai words with romanization in parentheses e.g. ไม่(mâi)' },
                  },
                  required: ['label', 'detail'],
                },
              },
              pronunciation_tips: {
                type: SchemaType.ARRAY,
                description: 'Pronunciation/tone tips (1-2 items)',
                items: {
                  type: SchemaType.OBJECT,
                  properties: {
                    thai: { type: SchemaType.STRING, description: 'Thai word/phrase being discussed' },
                    roman: { type: SchemaType.STRING, description: 'Romanized pronunciation' },
                    tip: { type: SchemaType.STRING, description: 'Pronunciation tip in Japanese' },
                  },
                  required: ['thai', 'roman', 'tip'],
                },
              },
              related_expressions: {
                type: SchemaType.ARRAY,
                description: 'Related/alternative expressions (1-2 items)',
                items: {
                  type: SchemaType.OBJECT,
                  properties: {
                    thai: { type: SchemaType.STRING, description: 'Thai expression' },
                    roman: { type: SchemaType.STRING, description: 'Romanized pronunciation' },
                    meaning: { type: SchemaType.STRING, description: 'Japanese meaning' },
                  },
                  required: ['thai', 'roman', 'meaning'],
                },
              },
            },
            required: ['grammar_points', 'pronunciation_tips', 'related_expressions'],
          },
        },
      });

      const prompt = `以下のタイ語例文について、学習者向けの復習ポイントを作成してください。

例文: ${sentence.thai_text}
発音: ${sentence.pronunciation}
日本語訳: ${sentence.japanese_translation}

【重要なルール】
- 例文そのものは再掲しない。ポイントだけに絞る
- タイ語を出す場合は必ずローマ字読みを添える（例: ไม่(mâi)）
- 各カテゴリ1〜2項目、簡潔に`;

      const result = await model.generateContent(prompt);
      const text = result.response.text();
      const parsed = JSON.parse(text);
      return parsed as ReviewNotes;
    } catch (error) {
      console.error('Failed to generate review notes', {
        error: error instanceof Error ? error.message : 'Unknown',
      });
      return { grammar_points: [], pronunciation_tips: [], related_expressions: [] };
    }
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
          temperature: 0.7,
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
