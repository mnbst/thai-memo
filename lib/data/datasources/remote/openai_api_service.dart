import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

import '../../../core/config/app_config.dart';
import '../../../core/constants/api_constants.dart';
import '../../models/thai_sentence.dart';
import '../../models/word_breakdown.dart';

/// Service for communicating with OpenAI API
class OpenAiApiService {
  final http.Client _client;

  OpenAiApiService({http.Client? client}) : _client = client ?? http.Client();

  /// Generate a new Thai sentence using OpenAI API
  Future<ThaiSentence> generateSentence(String apiKey) async {
    try {
      // Build request
      final request = _buildRequest(apiKey);

      // Send request with timeout
      final response = await _client
          .post(
        Uri.parse(AppConfig.openAiApiUrl),
        headers: request.headers,
        body: request.body,
      )
          .timeout(
        const Duration(seconds: AppConfig.apiTimeoutSeconds),
        onTimeout: () {
          throw ApiTimeoutException(ApiConstants.errorTimeout);
        },
      );

      // Handle response
      return await _handleResponse(response);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException(ApiConstants.errorUnknown, originalError: e);
    }
  }

  /// Build HTTP request for OpenAI API
  _ApiRequest _buildRequest(String apiKey) {
    final headers = {
      ApiConstants.headerContentType: ApiConstants.contentTypeJson,
      ApiConstants.headerAuthorization: 'Bearer $apiKey',
    };

    final body = json.encode({
      'model': AppConfig.openAiModel,
      'messages': [
        {
          'role': ApiConstants.roleUser,
          'content': ApiConstants.sentenceGenerationPrompt,
        },
      ],
      'max_tokens': AppConfig.apiMaxTokens,
      'temperature': AppConfig.apiTemperature,
      'frequency_penalty': AppConfig.apiFrequencyPenalty,
      'presence_penalty': AppConfig.apiPresencePenalty,
      'response_format': {'type': 'json_object'},
    });

    return _ApiRequest(headers: headers, body: body);
  }

  /// Handle API response
  Future<ThaiSentence> _handleResponse(http.Response response) async {
    // Check HTTP status code
    if (response.statusCode == 200) {
      return _parseSuccessResponse(response.body);
    } else if (response.statusCode == 401) {
      throw ApiInvalidKeyException(ApiConstants.errorInvalidApiKey);
    } else if (response.statusCode == 429) {
      throw ApiRateLimitException(ApiConstants.errorRateLimit);
    } else if (response.statusCode >= 500) {
      throw ApiServerException(ApiConstants.errorServerError);
    } else {
      final errorMessage = _extractErrorMessage(response.body);
      throw ApiException(errorMessage);
    }
  }

  /// Parse successful API response
  ThaiSentence _parseSuccessResponse(String responseBody) {
    try {
      final responseJson = json.decode(responseBody);

      // Extract content from response
      final choices = responseJson[ApiConstants.keyChoices] as List?;
      if (choices == null || choices.isEmpty) {
        throw ApiInvalidResponseException(
            'No choices in response: $responseBody');
      }

      final message =
          choices[0][ApiConstants.keyMessage] as Map<String, dynamic>?;
      if (message == null) {
        throw ApiInvalidResponseException(
            'No message in choice: $responseBody');
      }

      final content = message[ApiConstants.keyContent] as String?;
      if (content == null || content.isEmpty) {
        throw ApiInvalidResponseException(
            'Empty content in message: $responseBody');
      }

      // Parse the JSON content
      final sentenceJson = json.decode(content);

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
      return ThaiSentence(
        thaiText: json['thai_text'] as String? ?? '',
        pronunciation: json['pronunciation'] as String? ?? '',
        japaneseTranslation: json['japanese_translation'] as String? ?? '',
        wordBreakdowns: wordBreakdowns,
        context: context,
        createdAt: DateTime.now(),
        isFavorite: false,
      );
    } catch (e) {
      throw ApiInvalidResponseException('Failed to create ThaiSentence: $e');
    }
  }

  /// Extract error message from error response
  String _extractErrorMessage(String responseBody) {
    try {
      final errorJson = json.decode(responseBody);
      final error = errorJson[ApiConstants.keyError] as Map<String, dynamic>?;
      if (error != null) {
        return error[ApiConstants.keyErrorMessage] as String? ??
            ApiConstants.errorUnknown;
      }
    } catch (e) {
      // If parsing fails, return generic error
    }
    return ApiConstants.errorUnknown;
  }

  /// Get token usage from response (for logging)
  int? getTokenUsage(String responseBody) {
    try {
      final responseJson = json.decode(responseBody);
      final usage =
          responseJson[ApiConstants.keyUsage] as Map<String, dynamic>?;
      if (usage != null) {
        return usage[ApiConstants.keyTotalTokens] as int?;
      }
    } catch (e) {
      // Ignore parsing errors
    }
    return null;
  }

  /// Close the HTTP client
  void dispose() {
    _client.close();
  }
}

/// Helper class for API request
class _ApiRequest {
  final Map<String, String> headers;
  final String body;

  _ApiRequest({required this.headers, required this.body});
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

/// Exception for network failures
class ApiNetworkException extends ApiException {
  ApiNetworkException(String message, {Object? originalError})
      : super(message, originalError: originalError);

  @override
  String toString() => 'ApiNetworkException: $message';
}
