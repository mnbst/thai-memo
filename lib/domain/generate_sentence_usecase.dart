import '../l10n/app_localizations.dart';
import '../data/datasources/backend_api_service.dart';
import '../data/models/thai_sentence.dart';
import '../data/sentence_repository.dart';

/// Use case for generating a new Thai sentence from backend API
class GenerateSentenceUseCase {
  final SentenceRepository _repository;

  GenerateSentenceUseCase(this._repository);

  /// Execute the use case to generate and save a new sentence
  ///
  /// Returns the generated [ThaiSentence]
  /// Throws [GenerateSentenceException] if generation fails
  Future<ThaiSentence> execute({
    Map<String, String?> generationParams = const {},
  }) async {
    try {
      // No need to check API key - authentication handled by Firebase
      final sentence = await _repository.generateAndSaveSentence(
        generationParams: generationParams,
      );
      return sentence;
    } on RepositoryException catch (e) {
      throw GenerateSentenceException(
        e.message,
        type: _mapRepositoryException(e),
      );
    } on BackendApiException catch (e) {
      throw GenerateSentenceException(
        e.message,
        type: _mapBackendApiException(e),
      );
    } catch (e) {
      throw GenerateSentenceException(
        'Failed to generate sentence: $e',
        type: GenerateSentenceErrorType.unknown,
      );
    }
  }

  /// Map repository exception to use case error type
  GenerateSentenceErrorType _mapRepositoryException(RepositoryException e) {
    final message = e.message.toLowerCase();

    if (message.contains('network') || message.contains('connection')) {
      return GenerateSentenceErrorType.networkError;
    } else if (message.contains('rate limit')) {
      return GenerateSentenceErrorType.rateLimitExceeded;
    } else if (message.contains('timeout')) {
      return GenerateSentenceErrorType.timeout;
    } else if (message.contains('server')) {
      return GenerateSentenceErrorType.serverError;
    } else {
      return GenerateSentenceErrorType.unknown;
    }
  }

  /// Map backend API exception to use case error type
  GenerateSentenceErrorType _mapBackendApiException(BackendApiException e) {
    if (e is BackendApiUnauthenticatedException) {
      return GenerateSentenceErrorType.authenticationError;
    } else if (e is BackendApiQuotaExceededException) {
      return GenerateSentenceErrorType.quotaExceeded;
    } else if (e is BackendApiRateLimitException) {
      return GenerateSentenceErrorType.rateLimitExceeded;
    } else if (e is BackendApiTimeoutException) {
      return GenerateSentenceErrorType.timeout;
    } else if (e is BackendApiServerException) {
      return GenerateSentenceErrorType.serverError;
    } else {
      return GenerateSentenceErrorType.unknown;
    }
  }
}

/// Types of errors that can occur during sentence generation
enum GenerateSentenceErrorType {
  /// Authentication error
  authenticationError,

  /// Network connection error
  networkError,

  /// API rate limit exceeded
  rateLimitExceeded,

  /// Quota exceeded (subscription required)
  quotaExceeded,

  /// Request timeout
  timeout,

  /// Server error
  serverError,

  /// Unknown error
  unknown,
}

/// Exception thrown when sentence generation fails
class GenerateSentenceException implements Exception {
  final String message;
  final GenerateSentenceErrorType type;

  GenerateSentenceException(
    this.message, {
    required this.type,
  });

  /// Get user-friendly error message
  String getUserMessage(L10n l10n) {
    switch (type) {
      case GenerateSentenceErrorType.authenticationError:
        return l10n.errAuth;
      case GenerateSentenceErrorType.networkError:
        return l10n.errNetwork;
      case GenerateSentenceErrorType.rateLimitExceeded:
        return l10n.quotaSentenceReached;
      case GenerateSentenceErrorType.quotaExceeded:
        return l10n.quotaSentenceReached;
      case GenerateSentenceErrorType.timeout:
        return l10n.errTimeout;
      case GenerateSentenceErrorType.serverError:
        return l10n.errServer;
      case GenerateSentenceErrorType.unknown:
        return l10n.errSentenceGenerationFailed;
    }
  }

  @override
  String toString() =>
      'GenerateSentenceException(type: $type, message: $message)';
}
