import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../core/config/firebase_config.dart';
import '../../../core/thai_tone_analyzer.dart';
import '../models/syllable.dart';
import '../models/thai_sentence.dart';
import '../models/word_breakdown.dart';

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
  Future<ThaiSentence> generateSentence({
    Map<String, String?> generationParams = const {},
  }) async {
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

      final params = <String, dynamic>{};
      for (final entry in generationParams.entries) {
        if (entry.value != null) {
          params[entry.key] = entry.value;
        }
      }

      final result = await callable.call(params);

      // Parse response
      final data = Map<String, dynamic>.from(result.data as Map);

      if (data['success'] != true) {
        final error = data['error'] != null
            ? Map<String, dynamic>.from(data['error'] as Map)
            : null;
        final errorCode = error?['code'] as String? ?? 'UNKNOWN';
        final errorMessage = error?['message'] as String? ?? 'Unknown error';

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

          // Parse syllables if present (string array from API)
          List<Syllable>? syllables;
          final syllablesJson = wordJson['syllables'] as List<dynamic>?;
          if (syllablesJson != null) {
            syllables = syllablesJson.map((s) {
              final syllableText = s as String;

              // Analyze tone using rule-based analyzer
              final analysis = ThaiToneAnalyzer.analyzeTone(syllableText);

              return Syllable(
                text: syllableText,
                initialConsonant: analysis.initialConsonant ?? '',
                consonantClass:
                    _consonantClassToString(analysis.consonantClass),
                tone: _toneToString(analysis.resultingTone),
                toneMark: _toneMarkToString(analysis.toneMark),
                syllableType: _syllableTypeToString(analysis.syllableType),
                hasShortVowel: analysis.hasShortVowel,
              );
            }).toList();
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
              topic: contextJson['topic'] as String?,
              style: contextJson['style'] as String?,
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
        return BackendApiTimeoutException('Request timeout. Please try again.');
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

  /// Convert ConsonantClass enum to string
  String _consonantClassToString(ConsonantClass consonantClass) {
    switch (consonantClass) {
      case ConsonantClass.high:
        return 'high';
      case ConsonantClass.middle:
        return 'middle';
      case ConsonantClass.low:
        return 'low';
      case ConsonantClass.unknown:
        return 'unknown';
    }
  }

  /// Convert ThaiTone enum to string
  String _toneToString(ThaiTone tone) {
    switch (tone) {
      case ThaiTone.mid:
        return 'mid';
      case ThaiTone.low:
        return 'low';
      case ThaiTone.falling:
        return 'falling';
      case ThaiTone.high:
        return 'high';
      case ThaiTone.rising:
        return 'rising';
      case ThaiTone.unknown:
        return 'unknown';
    }
  }

  /// Convert ToneMark enum to string
  String _toneMarkToString(ToneMark toneMark) {
    switch (toneMark) {
      case ToneMark.none:
        return 'none';
      case ToneMark.maiEk:
        return 'maiEk';
      case ToneMark.maiTho:
        return 'maiTho';
      case ToneMark.maiTri:
        return 'maiTri';
      case ToneMark.maiChattawa:
        return 'maiChattawa';
    }
  }

  /// Convert SyllableType enum to string
  String _syllableTypeToString(SyllableType syllableType) {
    switch (syllableType) {
      case SyllableType.live:
        return 'live';
      case SyllableType.dead:
        return 'dead';
      case SyllableType.unknown:
        return 'unknown';
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
