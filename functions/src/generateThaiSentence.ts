import * as functions from 'firebase-functions/v2';
import { CallableRequest } from 'firebase-functions/v2/https';
import { SecretManagerServiceClient } from '@google-cloud/secret-manager';
import { GeminiService } from './services/geminiService';
import {
  GenerateSentenceRequest,
  GenerateSentenceResponse,
} from './types/thaiSentence';

const secretClient = new SecretManagerServiceClient();

async function getGeminiApiKey(): Promise<string> {
  try {
    const projectId = process.env.GCLOUD_PROJECT;
    const secretName = `projects/${projectId}/secrets/gemini-api-key/versions/latest`;

    const [version] = await secretClient.accessSecretVersion({
      name: secretName,
    });

    const apiKey = version.payload?.data?.toString();
    if (!apiKey) {
      throw new Error('API key is empty');
    }

    return apiKey;
  } catch (error) {
    console.error('Failed to retrieve API key from Secret Manager:', error);
    throw new Error('SECRET_MANAGER_ERROR');
  }
}

export const generateThaiSentence = functions.https.onCall(
  { region: 'asia-northeast1' }, // Tokyo region for low latency
  async (request: CallableRequest<GenerateSentenceRequest>) => {
    const startTime = Date.now();
    const response: GenerateSentenceResponse = {
      success: false,
    };

    // Structured logging
    const logData: Record<string, any> = {
      timestamp: new Date().toISOString(),
      userId: request.auth?.uid || 'anonymous',
      requestedTopic: request.data.topic || 'random',
    };

    try {
      // Verify authentication
      if (!request.auth) {
        logData.error = 'UNAUTHENTICATED';
        logData.success = false;
        console.error('Authentication failed', logData);

        response.error = {
          code: 'UNAUTHENTICATED',
          message: 'User must be authenticated',
        };
        return response;
      }

      console.log('Request started', logData);

      // Get Gemini API key from Secret Manager
      const apiKey = await getGeminiApiKey();

      // Initialize Gemini service
      const geminiService = new GeminiService(apiKey);

      // Generate sentence
      const sentence = await geminiService.generateSentence({
        topic: request.data.topic,
        style: request.data.style,
        politeness: request.data.politeness,
        grammarFocus: request.data.grammarFocus,
        vocabLevel: request.data.vocabLevel,
        sentenceLength: request.data.sentenceLength,
        emotion: request.data.emotion,
        learningPurpose: request.data.learningPurpose,
        toneDensity: request.data.toneDensity,
      });

      // Calculate processing time
      const processingTime = Date.now() - startTime;

      logData.success = true;
      logData.processingTimeMs = processingTime;
      logData.generatedTopic = sentence.context?.topic || 'unknown';
      logData.sentenceLength = sentence.thai_text.length;
      logData.wordCount = sentence.word_breakdown.length;

      response.success = true;
      response.data = sentence;

      console.log('Request completed successfully', logData);
      return response;
    } catch (error) {
      const processingTime = Date.now() - startTime;

      logData.success = false;
      logData.processingTimeMs = processingTime;
      logData.errorMessage = error instanceof Error ? error.message : 'Unknown error';

      if (error instanceof Error) {
        if (error.message.includes('UNAUTHENTICATED')) {
          logData.errorCode = 'UNAUTHENTICATED';
          response.error = {
            code: 'UNAUTHENTICATED',
            message: 'Authentication failed',
          };
        } else if (error.message.includes('SECRET_MANAGER_ERROR')) {
          logData.errorCode = 'SECRET_MANAGER_ERROR';
          response.error = {
            code: 'INTERNAL',
            message: 'Failed to retrieve API configuration',
          };
        } else if (error.message.includes('GEMINI_API_ERROR')) {
          logData.errorCode = 'GEMINI_API_ERROR';
          response.error = {
            code: 'API_ERROR',
            message: 'Failed to generate sentence',
          };
        } else {
          logData.errorCode = 'UNKNOWN';
          response.error = {
            code: 'UNKNOWN',
            message: 'An unexpected error occurred',
          };
        }
      } else {
        logData.errorCode = 'UNKNOWN';
        response.error = {
          code: 'UNKNOWN',
          message: 'An unexpected error occurred',
        };
      }

      console.error('Request failed', logData);
      return response;
    }
  }
);
