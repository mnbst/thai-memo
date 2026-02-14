import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:google_generative_ai/google_generative_ai.dart';

import '../../../core/config/app_config.dart';
import '../../../core/constants/api_constants.dart';
import '../../models/thai_sentence.dart';
import '../../models/word_breakdown.dart';

/// Service for communicating with Gemini API
class GeminiApiService {
  GenerativeModel? _model;
  final Random _random = Random();

  /// Generate a new Thai sentence using Gemini API
  Future<ThaiSentence> generateSentence(String apiKey) async {
    try {
      // Randomly select a situation from the list
      final randomSituation = ApiConstants
          .situations[_random.nextInt(ApiConstants.situations.length)];

      // Initialize model with API key and JSON schema for structured output
      _model = GenerativeModel(
        model: AppConfig.geminiModel,
        apiKey: apiKey,
        generationConfig: GenerationConfig(
          temperature: AppConfig.apiTemperature,
          maxOutputTokens: AppConfig.apiMaxTokens,
          responseMimeType: 'application/json',
          responseSchema: Schema.object(
            properties: {
              'thai_text': Schema.string(
                description: 'The Thai sentence text',
                nullable: false,
              ),
              'pronunciation': Schema.string(
                description: 'Pinyin-style romanized pronunciation with tone marks (e.g., mâi rúu sì, sùt-tháai, kham-tɔ̀ɔp)',
                nullable: false,
              ),
              'japanese_translation': Schema.string(
                description: 'Japanese translation of the Thai sentence',
                nullable: false,
              ),
              'word_breakdown': Schema.array(
                items: Schema.object(
                  properties: {
                    'word': Schema.string(
                      description: 'Thai word',
                      nullable: false,
                    ),
                    'pronunciation': Schema.string(
                      description: 'Pinyin-style romanized pronunciation with tone marks',
                      nullable: false,
                    ),
                    'meaning': Schema.string(
                      description: 'Japanese meaning of the word',
                      nullable: false,
                    ),
                    'grammatical_role': Schema.string(
                      description: 'Grammatical role of the word (e.g., noun, verb, particle)',
                      nullable: true,
                    ),
                  },
                  requiredProperties: ['word', 'pronunciation', 'meaning'],
                ),
                description: 'Array of word breakdowns',
                nullable: false,
              ),
              'context': Schema.object(
                properties: {
                  'situation': Schema.string(
                    description: 'Situation where this sentence is used',
                    nullable: true,
                  ),
                  'emotion': Schema.string(
                    description: 'Emotion or tone of the sentence',
                    nullable: true,
                  ),
                  'usage_scenarios': Schema.string(
                    description: 'Usage scenarios or contexts',
                    nullable: true,
                  ),
                  'cultural_notes': Schema.string(
                    description: 'Cultural notes or background',
                    nullable: true,
                  ),
                },
              ),
            },
            requiredProperties: [
              'thai_text',
              'pronunciation',
              'japanese_translation',
              'word_breakdown'
            ],
          ),
        ),
      );

      // Generate content with randomly selected situation
      final response = await _model!
          .generateContent([
            Content.text(ApiConstants.getSentenceGenerationPrompt(randomSituation)),
          ])
          .timeout(
            const Duration(seconds: AppConfig.apiTimeoutSeconds),
            onTimeout: () {
              throw ApiTimeoutException(ApiConstants.errorTimeout);
            },
          );

      // Handle response
      return _handleResponse(response);
    } on GenerativeAIException catch (e) {
      // Handle Gemini-specific errors
      if (e.message.contains('API_KEY_INVALID') ||
          e.message.contains('invalid api key')) {
        throw ApiInvalidKeyException(ApiConstants.errorInvalidApiKey);
      } else if (e.message.contains('RESOURCE_EXHAUSTED') ||
          e.message.contains('quota')) {
        throw ApiRateLimitException(ApiConstants.errorRateLimit);
      } else if (e.message.contains('INTERNAL') ||
          e.message.contains('UNAVAILABLE')) {
        throw ApiServerException(ApiConstants.errorServerError);
      } else {
        throw ApiException('Gemini API error: ${e.message}');
      }
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException(ApiConstants.errorUnknown, originalError: e);
    }
  }

  /// Handle API response
  ThaiSentence _handleResponse(GenerateContentResponse response) {
    try {
      // Check if response has text
      final text = response.text;

      if (text == null || text.isEmpty) {
        throw ApiInvalidResponseException('Empty response from Gemini API');
      }

      // Parse JSON response (structured output ensures pure JSON)
      final sentenceJson = json.decode(text);

      // Create ThaiSentence from JSON
      return _createThaiSentence(sentenceJson);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiInvalidResponseException(
          '${ApiConstants.errorInvalidResponse}: $e');
    }
  }

  /// Create ThaiSentence object from parsed JSON
  ThaiSentence _createThaiSentence(Map<String, dynamic> json) {
    try {
      // Parse word breakdowns
      final wordBreakdownsJson = json['word_breakdown'] as List<dynamic>?;
      final wordBreakdowns = <WordBreakdown>[];

      if (wordBreakdownsJson != null) {
        for (var i = 0; i < wordBreakdownsJson.length; i++) {
          final wordJson = wordBreakdownsJson[i] as Map<String, dynamic>;
          wordBreakdowns.add(
            WordBreakdown(
              wordText: wordJson['word'] as String? ?? '',
              pronunciation: wordJson['pronunciation'] as String? ?? '',
              meaning: wordJson['meaning'] as String? ?? '',
              grammaticalRole: wordJson['grammatical_role'] as String?,
              wordOrder: i,
            ),
          );
        }
      }

      // Parse context
      final contextJson = json['context'] as Map<String, dynamic>?;
      final context = contextJson != null
          ? SentenceContext(
              situation: contextJson['situation'] as String?,
              emotion: contextJson['emotion'] as String?,
              usageScenarios: contextJson['usage_scenarios'] as String?,
              culturalNotes: contextJson['cultural_notes'] as String?,
            )
          : null;

      // Create ThaiSentence
      final sentence = ThaiSentence(
        thaiText: json['thai_text'] as String? ?? '',
        pronunciation: json['pronunciation'] as String? ?? '',
        japaneseTranslation: json['japanese_translation'] as String? ?? '',
        wordBreakdowns: wordBreakdowns,
        context: context,
        createdAt: DateTime.now(),
        isFavorite: false,
      );

      return sentence;
    } catch (e) {
      throw ApiInvalidResponseException('Failed to create ThaiSentence: $e');
    }
  }

  /// Dispose resources (not needed for Gemini, but kept for API consistency)
  void dispose() {
    _model = null;
  }
}

// ==================== Custom Exceptions ====================

/// Base exception for API errors
class ApiException implements Exception {
  final String message;
  final Object? originalError;

  ApiException(this.message, {this.originalError});

  @override
  String toString() =>
      'ApiException: $message${originalError != null ? ' (Original: $originalError)' : ''}';
}

/// Exception for invalid API key
class ApiInvalidKeyException extends ApiException {
  ApiInvalidKeyException(String message) : super(message);

  @override
  String toString() => 'ApiInvalidKeyException: $message';
}

/// Exception for rate limit exceeded
class ApiRateLimitException extends ApiException {
  ApiRateLimitException(String message) : super(message);

  @override
  String toString() => 'ApiRateLimitException: $message';
}

/// Exception for server errors
class ApiServerException extends ApiException {
  ApiServerException(String message) : super(message);

  @override
  String toString() => 'ApiServerException: $message';
}

/// Exception for invalid response format
class ApiInvalidResponseException extends ApiException {
  ApiInvalidResponseException(String message) : super(message);

  @override
  String toString() => 'ApiInvalidResponseException: $message';
}

/// Exception for request timeout
class ApiTimeoutException extends ApiException {
  ApiTimeoutException(String message) : super(message);

  @override
  String toString() => 'ApiTimeoutException: $message';
}
