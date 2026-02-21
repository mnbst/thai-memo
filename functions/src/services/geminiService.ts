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
}
