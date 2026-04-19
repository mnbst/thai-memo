import * as logger from 'firebase-functions/logger';
import {
  applyRuleBasedQuizFields,
  buildQuizGenerationPrompt,
  QuizGenerationModelResponse,
  QUIZ_RESPONSE_JSON_SCHEMA,
  QuizGenerationService,
  QuizQuestionsResponse,
  QuizSentenceSeed,
  sanitizeQuizQuestions,
} from './quizGenerationService';

type OpenAiReasoningEffort = 'none' | 'low' | 'medium' | 'high' | 'xhigh';

interface OpenAiUsage {
  input_tokens?: number;
  output_tokens?: number;
  total_tokens?: number;
  output_tokens_details?: {
    reasoning_tokens?: number;
  };
}

interface OpenAiOutputContent {
  type?: string;
  text?: string;
}

interface OpenAiOutputItem {
  content?: OpenAiOutputContent[];
}

interface OpenAiResponsesApiResponse {
  output_text?: string;
  output?: OpenAiOutputItem[];
  usage?: OpenAiUsage;
  error?: {
    message?: string;
    type?: string;
    code?: string;
  };
}

const OPENAI_TOKEN_PRICING_PER_MILLION: Record<string, { input: number; output: number }> = {
  'gpt-5.4-mini': { input: 0.75, output: 4.50 },
  'gpt-5.4-nano': { input: 0.20, output: 1.25 },
  'gpt-5-mini': { input: 0.25, output: 2.00 },
  'gpt-5-nano': { input: 0.05, output: 0.40 },
};
const DEFAULT_OPENAI_TOKEN_PRICING_PER_MILLION = OPENAI_TOKEN_PRICING_PER_MILLION['gpt-5.4-nano'];

function getReasoningEffort(modelName: string): OpenAiReasoningEffort {
  if (modelName.startsWith('gpt-5.4-')) {
    return 'low';
  }
  if (modelName.startsWith('gpt-5-')) {
    return 'low';
  }
  return 'none';
}

function extractOutputText(response: OpenAiResponsesApiResponse): string | null {
  if (typeof response.output_text === 'string' && response.output_text.trim()) {
    return response.output_text;
  }

  const outputText = (response.output ?? [])
    .flatMap((item) => item.content ?? [])
    .map((content) => content.text ?? '')
    .join('')
    .trim();

  return outputText || null;
}

export class OpenAiQuizService implements QuizGenerationService {
  constructor(
    private readonly apiKey: string,
    private readonly modelName: string,
    private readonly uid: string,
    private readonly tier: 'free' | 'premium',
  ) {}

  async generateQuizQuestions(
    sentences: QuizSentenceSeed[],
  ): Promise<QuizQuestionsResponse> {
    const response = await this.fetchStructuredResponse<QuizGenerationModelResponse>(
      buildQuizGenerationPrompt(sentences),
      'quiz_questions_response',
      QUIZ_RESPONSE_JSON_SCHEMA,
      4096,
      sentences,
    );

    if (!response) {
      return { questions: [] };
    }

    const merged = applyRuleBasedQuizFields(response, sentences);
    return sanitizeQuizQuestions(merged);
  }

  private async fetchStructuredResponse<T>(
    prompt: string,
    schemaName: string,
    schema: unknown,
    maxOutputTokens: number,
    sentences: QuizSentenceSeed[],
  ): Promise<T | null> {
    try {
      const response = await fetch('https://api.openai.com/v1/responses', {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${this.apiKey}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          model: this.modelName,
          input: [
            {
              role: 'user',
              content: prompt,
            },
          ],
          max_output_tokens: maxOutputTokens,
          reasoning: {
            effort: getReasoningEffort(this.modelName),
          },
          text: {
            format: {
              type: 'json_schema',
              name: schemaName,
              strict: true,
              schema,
            },
          },
        }),
      });
      const responseBody = await response.json() as OpenAiResponsesApiResponse;

      if (!response.ok) {
        logger.error('OpenAI quiz generation failed', {
          event: 'openai_quiz_generation_failed',
          status: response.status,
          model: this.modelName,
          errorType: responseBody.error?.type,
          errorCode: responseBody.error?.code,
          errorMessage: responseBody.error?.message,
        });
        return null;
      }

      this.logUsage(sentences, responseBody.usage);
      const text = extractOutputText(responseBody);
      if (!text) {
        logger.error('OpenAI quiz generation returned empty output', {
          event: 'openai_quiz_generation_empty_output',
          model: this.modelName,
        });
        return null;
      }

      return JSON.parse(text) as T;
    } catch (error) {
      logger.error('Failed to generate quiz questions with OpenAI', {
        event: 'openai_quiz_generation_failed',
        model: this.modelName,
        error: error instanceof Error ? error.message : 'Unknown',
      });
      return null;
    }
  }

  private logUsage(
    sentences: QuizSentenceSeed[],
    usage: OpenAiUsage | undefined,
  ): void {
    if (!usage) return;

    const inputTokens = usage.input_tokens ?? 0;
    const outputTokens = usage.output_tokens ?? 0;
    const reasoningTokens = usage.output_tokens_details?.reasoning_tokens ?? 0;
    const totalTokens = usage.total_tokens ?? inputTokens + outputTokens;
    const pricing = OPENAI_TOKEN_PRICING_PER_MILLION[this.modelName] ?? DEFAULT_OPENAI_TOKEN_PRICING_PER_MILLION;
    const costUsd = (inputTokens * pricing.input + outputTokens * pricing.output) / 1_000_000;

    logger.info('OpenAI token usage', {
      event: 'openai_token_usage',
      uid: this.uid,
      tier: this.tier,
      requestMode: sentences.length > 1 ? 'batch' : 'single',
      sentenceCount: sentences.length,
      keyWords: sentences.map((sentence) => sentence.key_word ?? null),
      model: this.modelName,
      inputTokens,
      outputTokens,
      reasoningTokens,
      totalTokens,
      inputUsdPerMillion: pricing.input,
      outputUsdPerMillion: pricing.output,
      costUsd: Number(costUsd.toFixed(6)),
      costUsdMicros: Math.round(costUsd * 1_000_000),
    });
  }
}
