import * as functions from 'firebase-functions/v2';
import { CallableRequest } from 'firebase-functions/v2/https';
import * as logger from 'firebase-functions/logger';

/**
 * App event data structure
 */
interface AppLogEvent {
  eventType: string;      // Event type (e.g., "sentence_saved", "app_opened", "error_occurred")
  userId?: string;        // User ID (optional, will use auth.uid if not provided)
  metadata?: Record<string, any>;  // Additional event metadata
  timestamp: string;      // ISO 8601 timestamp
}

/**
 * Cloud Function to log app events to Cloud Logging
 *
 * This function receives events from the Flutter app and logs them to Cloud Logging.
 * BigQuery export is not required - logs are stored in Cloud Logging only.
 *
 * @example
 * // Call from Flutter app:
 * await functions.httpsCallable('logAppEvent').call({
 *   'eventType': 'sentence_saved',
 *   'userId': 'user123',
 *   'metadata': { 'situation': 'restaurant', 'wordCount': 5 },
 *   'timestamp': DateTime.now().toIso8601String(),
 * });
 */
export const logAppEvent = functions.https.onCall(
  { region: 'asia-northeast1' },
  async (request: CallableRequest<AppLogEvent>) => {
    const startTime = Date.now();

    try {
      const { eventType, userId, metadata, timestamp } = request.data as AppLogEvent;

      // Validate required fields
      if (!eventType) {
        throw new functions.https.HttpsError(
          'invalid-argument',
          'eventType is required'
        );
      }

      // Use provided userId or fall back to authenticated user
      const effectiveUserId = userId || request.auth?.uid || 'anonymous';

      // Log to Cloud Logging
      logger.info('App Event', {
        eventType,
        userId: effectiveUserId,
        metadata: metadata || {},
        timestamp,
        processingTimeMs: Date.now() - startTime,
        // Additional context
        userAgent: request.rawRequest.headers['user-agent'],
        ip: request.rawRequest.ip,
      });

      return {
        success: true,
        logged_at: new Date().toISOString(),
      };

    } catch (error) {
      const processingTimeMs = Date.now() - startTime;

      // Log error to Cloud Logging
      logger.error('Failed to log app event', {
        error: error instanceof Error ? error.message : String(error),
        processingTimeMs,
      });

      // Re-throw HttpsError as-is, wrap other errors
      if (error instanceof functions.https.HttpsError) {
        throw error;
      }

      throw new functions.https.HttpsError(
        'internal',
        'Failed to log event',
        { originalError: String(error) }
      );
    }
  });
