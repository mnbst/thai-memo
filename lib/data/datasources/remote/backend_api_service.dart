import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../core/config/firebase_config.dart';
import '../../models/syllable.dart';
import '../../models/thai_sentence.dart';
import '../../models/word_breakdown.dart';

/// Service for communicating with backend Cloud Functions
class BackendApiService {
  final FirebaseFunctions _functions;
  final FirebaseAuth _auth;

  BackendApiService({
    FirebaseFunctions? functions,
    FirebaseAuth? auth,
  })  : _functions = functions ??
            FirebaseFunctions.instanceFor(
              region: FirebaseConfig.functionsRegion,
            ),
        _auth = auth ?? FirebaseAuth.instance;

  /// Generate a new Thai sentence using backend API
  Future<ThaiSentence> generateSentence({String? situation}) async {
    try {
      // Ensure user is authenticated
      final user = _auth.currentUser;
      if (user == null) {
        throw BackendApiException('User not authenticated');
      }

      // Call Cloud Function
      final callable = _functions.httpsCallable(
        FirebaseConfig.generateSentenceFunctionName,
        options: HttpsCallableOptions(
          timeout: FirebaseConfig.functionTimeout,
        ),
      );

      final result = await callable.call(<String, dynamic>{
        if (situation != null) 'situation': situation,
      });

      // Parse response
      final data = Map<String, dynamic>.from(result.data as Map);

      if (data['success'] != true) {
        final error = data['error'] != null
            ? Map<String, dynamic>.from(data['error'] as Map)
            : null;
        final errorCode = error?['code'] as String? ?? 'UNKNOWN';
        final errorMessage =
            error?['message'] as String? ?? 'Unknown error';

        throw _mapBackendError(errorCode, errorMessage);
      }

      // Extract sentence data
      final sentenceData = Map<String, dynamic>.from(data['data'] as Map);

      return _createThaiSentence(sentenceData);
    } on FirebaseFunctionsException catch (e) {
      throw _mapFirebaseFunctionsException(e);
    } on BackendApiException {
      rethrow;
    } catch (e) {
      throw BackendApiException('Failed to generate sentence: $e');
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
          final wordJson =
              Map<String, dynamic>.from(wordBreakdownsJson[i] as Map);

          // Parse syllables if present
          List<Syllable>? syllables;
          final syllablesJson = wordJson['syllables'] as List<dynamic>?;
          if (syllablesJson != null) {
            syllables = syllablesJson
                .map((s) =>
                    Syllable.fromJson(Map<String, dynamic>.from(s as Map)))
                .toList();
          }

          wordBreakdowns.add(
            WordBreakdown(
              wordText: wordJson['word'] as String? ?? '',
              pronunciation: wordJson['pronunciation'] as String? ?? '',
              meaning: wordJson['meaning'] as String? ?? '',
              grammaticalRole: wordJson['grammatical_role'] as String?,
              wordOrder: i,
              syllables: syllables,
            ),
          );
        }
      }

      // Parse context
      final contextJson = json['context'] != null
          ? Map<String, dynamic>.from(json['context'] as Map)
          : null;
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
      throw BackendApiInvalidResponseException(
          'Failed to create ThaiSentence: $e');
    }
  }

  /// Map Firebase Functions exceptions to custom exceptions
  BackendApiException _mapFirebaseFunctionsException(
      FirebaseFunctionsException e) {
    switch (e.code) {
      case 'unauthenticated':
        return BackendApiUnauthenticatedException(
            'Authentication required. Please restart the app.');
      case 'permission-denied':
        return BackendApiPermissionDeniedException(
            'Permission denied. Please check your account.');
      case 'deadline-exceeded':
        return BackendApiTimeoutException(
            'Request timeout. Please try again.');
      case 'unavailable':
        return BackendApiServerException('Service temporarily unavailable.');
      case 'resource-exhausted':
        return BackendApiRateLimitException(
            'Rate limit exceeded. Please try again later.');
      default:
        return BackendApiException('${e.code}: ${e.message}');
    }
  }

  /// Map backend error codes to custom exceptions
  BackendApiException _mapBackendError(String code, String message) {
    switch (code) {
      case 'UNAUTHENTICATED':
        return BackendApiUnauthenticatedException(message);
      case 'API_ERROR':
        return BackendApiServerException(message);
      case 'INTERNAL':
        return BackendApiServerException(message);
      default:
        return BackendApiException(message);
    }
  }

  /// Dispose resources
  void dispose() {
    // Nothing to dispose for Cloud Functions
  }
}

// ==================== Custom Exceptions ====================

/// Base exception for backend API errors
class BackendApiException implements Exception {
  final String message;
  final Object? originalError;

  BackendApiException(this.message, {this.originalError});

  @override
  String toString() =>
      'BackendApiException: $message${originalError != null ? ' (Original: $originalError)' : ''}';
}

/// Exception for unauthenticated requests
class BackendApiUnauthenticatedException extends BackendApiException {
  BackendApiUnauthenticatedException(String message) : super(message);

  @override
  String toString() => 'BackendApiUnauthenticatedException: $message';
}

/// Exception for permission denied
class BackendApiPermissionDeniedException extends BackendApiException {
  BackendApiPermissionDeniedException(String message) : super(message);

  @override
  String toString() => 'BackendApiPermissionDeniedException: $message';
}

/// Exception for rate limit exceeded
class BackendApiRateLimitException extends BackendApiException {
  BackendApiRateLimitException(String message) : super(message);

  @override
  String toString() => 'BackendApiRateLimitException: $message';
}

/// Exception for server errors
class BackendApiServerException extends BackendApiException {
  BackendApiServerException(String message) : super(message);

  @override
  String toString() => 'BackendApiServerException: $message';
}

/// Exception for invalid response format
class BackendApiInvalidResponseException extends BackendApiException {
  BackendApiInvalidResponseException(String message) : super(message);

  @override
  String toString() => 'BackendApiInvalidResponseException: $message';
}

/// Exception for request timeout
class BackendApiTimeoutException extends BackendApiException {
  BackendApiTimeoutException(String message) : super(message);

  @override
  String toString() => 'BackendApiTimeoutException: $message';
}
