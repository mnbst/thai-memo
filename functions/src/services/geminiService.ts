import { GoogleGenerativeAI, SchemaType } from '@google/generative-ai';
import { ThaiSentence } from '../types/thaiSentence';
import {
  GEMINI_MODEL,
  API_TEMPERATURE,
  API_MAX_TOKENS,
  SITUATIONS,
  getSentenceGenerationPrompt,
} from '../config/constants';

export class GeminiService {
  private genAI: GoogleGenerativeAI;

  constructor(apiKey: string) {
    this.genAI = new GoogleGenerativeAI(apiKey);
  }

  async generateSentence(situationOverride?: string): Promise<ThaiSentence> {
    const apiStartTime = Date.now();

    try {
      // Select situation
      const situation =
        situationOverride ||
        SITUATIONS[Math.floor(Math.random() * SITUATIONS.length)];

      console.log('Gemini API call started', {
        situation,
        isRandomSelection: !situationOverride,
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
                  },
                  required: ['word', 'pronunciation', 'meaning'],
                },
                description: 'Array of word breakdowns',
                nullable: false,
              },
              context: {
                type: SchemaType.OBJECT,
                properties: {
                  situation: {
                    type: SchemaType.STRING,
                    description: 'Situation where this sentence is used',
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
      const prompt = getSentenceGenerationPrompt(situation);
      const result = await model.generateContent(prompt);
      const response = result.response;
      const text = response.text();

      const apiLatency = Date.now() - apiStartTime;

      console.log('Gemini API call completed', {
        latencyMs: apiLatency,
        responseLength: text.length,
      });

      // Parse JSON response
      const sentence: ThaiSentence = JSON.parse(text);

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
}
