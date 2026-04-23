import * as logger from 'firebase-functions/logger';
import {
  applyRuleBasedQuizFields,
  buildQuizGenerationPrompt,
  QUIZ_GENERATION_SYSTEM_PROMPT,
  QuizGenerationModelResponse,
  QUIZ_RESPONSE_JSON_SCHEMA,
  QuizGenerationService,
  QuizQuestionsResponse,
  QuizSentenceSeed,
  sanitizeQuizQuestions,
} from './quizGenerationService';

const GEMINI_MODEL = 'gemini-2.5-flash';

const GEMINI_PRICING_PER_MILLION = { input: 0.30, output: 2.50 };

interface GeminiUsageMetadata {
  promptTokenCount?: number;
  candidatesTokenCount?: number;
  totalTokenCount?: number;
  thoughtsTokenCount?: number;
}

interface GeminiCandidate {
  content?: {
    parts?: Array<{ text?: string }>;
  };
}

interface GeminiResponse {
  candidates?: GeminiCandidate[];
  usageMetadata?: GeminiUsageMetadata;
  error?: { message?: string; code?: number };
}

function toGeminiSchema(openAiSchema: Record<string, unknown>): Record<string, unknown> {
  const clone = JSON.parse(JSON.stringify(openAiSchema));
  removeAdditionalProperties(clone);
  return clone;
}

function removeAdditionalProperties(obj: unknown): void {
  if (obj === null || typeof obj !== 'object') return;
  if (Array.isArray(obj)) {
    obj.forEach(removeAdditionalProperties);
    return;
  }
  const record = obj as Record<string, unknown>;
  delete record['additionalProperties'];
  for (const value of Object.values(record)) {
    removeAdditionalProperties(value);
  }
}

export class GeminiQuizService implements QuizGenerationService {
  constructor(
    private readonly apiKey: string,
    private readonly uid: string,
    private readonly tier: 'free' | 'premium',
  ) {}

  async generateQuizQuestions(
    sentences: QuizSentenceSeed[],
  ): Promise<QuizQuestionsResponse> {
    const response = await this.fetchStructuredResponse<QuizGenerationModelResponse>(
      QUIZ_GENERATION_SYSTEM_PROMPT,
      buildQuizGenerationPrompt(sentences),
      sentences,
    );

    if (!response) {
      return { questions: [] };
    }

    const merged = applyRuleBasedQuizFields(response, sentences);
    return sanitizeQuizQuestions(merged);
  }

  private async fetchStructuredResponse<T>(
    systemPrompt: string,
    prompt: string,
    sentences: QuizSentenceSeed[],
  ): Promise<T | null> {
    try {
      const url = 'https://generativelanguage.googleapis.com/v1beta/models/' +
        `${GEMINI_MODEL}:generateContent?key=${this.apiKey}`;

      const response = await fetch(url, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          systemInstruction: { parts: [{ text: systemPrompt }] },
          contents: [{ role: 'user', parts: [{ text: prompt }] }],
          generationConfig: {
            responseMimeType: 'application/json',
            responseSchema: toGeminiSchema(QUIZ_RESPONSE_JSON_SCHEMA as unknown as Record<string, unknown>),
            maxOutputTokens: 4096,
            thinkingConfig: {
              thinkingBudget: 256,
            },
          },
        }),
      });

      const responseBody = await response.json() as GeminiResponse;

      if (!response.ok) {
        logger.error('Gemini quiz generation failed', {
          event: 'gemini_quiz_generation_failed',
          status: response.status,
          model: GEMINI_MODEL,
          errorCode: responseBody.error?.code,
          errorMessage: responseBody.error?.message,
        });
        return null;
      }

      this.logUsage(sentences, responseBody.usageMetadata);

      const text = responseBody.candidates?.[0]?.content?.parts?.[0]?.text?.trim();
      if (!text) {
        logger.error('Gemini quiz generation returned empty output', {
          event: 'gemini_quiz_generation_empty_output',
          model: GEMINI_MODEL,
        });
        return null;
      }

      return JSON.parse(text) as T;
    } catch (error) {
      logger.error('Failed to generate quiz questions with Gemini', {
        event: 'gemini_quiz_generation_failed',
        model: GEMINI_MODEL,
        error: error instanceof Error ? error.message : 'Unknown',
      });
      return null;
    }
  }

  private logUsage(
    sentences: QuizSentenceSeed[],
    usage: GeminiUsageMetadata | undefined,
  ): void {
    if (!usage) return;

    const promptTokens = usage.promptTokenCount ?? 0;
    const candidatesTokens = usage.candidatesTokenCount ?? 0;
    const thoughtsTokens = usage.thoughtsTokenCount ?? 0;
    const billedOutputTokens = candidatesTokens + thoughtsTokens;
    const totalTokens = usage.totalTokenCount ?? (promptTokens + billedOutputTokens);
    const costUsd = (
      promptTokens * GEMINI_PRICING_PER_MILLION.input +
      billedOutputTokens * GEMINI_PRICING_PER_MILLION.output
    ) / 1_000_000;

    logger.info('Gemini token usage', {
      event: 'gemini_quiz_token_usage',
      uid: this.uid,
      tier: this.tier,
      requestMode: sentences.length > 1 ? 'batch' : 'single',
      sentenceCount: sentences.length,
      keyWords: sentences.map((sentence) => sentence.key_word ?? null),
      model: GEMINI_MODEL,
      promptTokens,
      candidatesTokens,
      thoughtsTokens,
      billedOutputTokens,
      totalTokens,
      costUsd: Number(costUsd.toFixed(6)),
      costUsdMicros: Math.round(costUsd * 1_000_000),
    });
  }
}
