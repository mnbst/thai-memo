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
  Future<ThaiSentence> execute() async {
    try {
      // No need to check API key - authentication handled by Firebase
      final sentence = await _repository.generateAndSaveSentence();
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

  /// Check if a new generation is due based on the configured frequency
  Future<bool> isGenerationDue() async {
    try {
      return await _repository.isGenerationDue();
    } catch (e) {
      // If there's an error checking, assume generation is due
      return true;
    }
  }

  /// Get the timestamp of the last generation
  Future<DateTime?> getLastGenerationTimestamp() async {
    try {
      return await _repository.getLastGenerationTimestamp();
    } catch (e) {
      return null;
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
  String getUserMessage() {
    switch (type) {
      case GenerateSentenceErrorType.authenticationError:
        return '認証エラーが発生しました。アプリを再起動してください。';
      case GenerateSentenceErrorType.networkError:
        return 'ネットワーク接続エラーが発生しました。インターネット接続を確認してください。';
      case GenerateSentenceErrorType.rateLimitExceeded:
        return 'APIの利用制限に達しました。しばらく待ってから再試行してください。';
      case GenerateSentenceErrorType.timeout:
        return 'リクエストがタイムアウトしました。もう一度お試しください。';
      case GenerateSentenceErrorType.serverError:
        return 'サーバーエラーが発生しました。しばらく待ってから再試行してください。';
      case GenerateSentenceErrorType.unknown:
        return '例文の生成に失敗しました。もう一度お試しください。';
    }
  }

  @override
  String toString() =>
      'GenerateSentenceException(type: $type, message: $message)';
}
