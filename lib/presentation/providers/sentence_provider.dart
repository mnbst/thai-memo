import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/datasources/local/database_helper.dart';
import '../../data/datasources/local/secure_storage_service.dart';
import '../../data/datasources/remote/openai_api_service.dart';
import '../../data/models/thai_sentence.dart';
import '../../data/repositories/sentence_repository.dart';
import '../../domain/usecases/generate_sentence_usecase.dart';
import '../../domain/usecases/get_sentences_usecase.dart';
import '../../domain/usecases/save_sentence_usecase.dart';

// ==================== Repository Provider ====================

/// Provider for sentence repository
final sentenceRepositoryProvider = Provider<SentenceRepository>((ref) {
  return SentenceRepository(
    databaseHelper: DatabaseHelper.instance,
    apiService: OpenAiApiService(),
    secureStorage: SecureStorageService.instance,
  );
});

// ==================== Use Case Providers ====================

/// Provider for generate sentence use case
final generateSentenceUseCaseProvider =
    Provider<GenerateSentenceUseCase>((ref) {
  final repository = ref.watch(sentenceRepositoryProvider);
  return GenerateSentenceUseCase(repository);
});

/// Provider for get sentences use case
final getSentencesUseCaseProvider = Provider<GetSentencesUseCase>((ref) {
  final repository = ref.watch(sentenceRepositoryProvider);
  return GetSentencesUseCase(repository);
});

/// Provider for save sentence use case
final saveSentenceUseCaseProvider = Provider<SaveSentenceUseCase>((ref) {
  final repository = ref.watch(sentenceRepositoryProvider);
  return SaveSentenceUseCase(repository);
});

// ==================== State Providers ====================

/// Provider for all sentences
final allSentencesProvider = FutureProvider<List<ThaiSentence>>((ref) async {
  final useCase = ref.watch(getSentencesUseCaseProvider);
  return await useCase.execute();
});

/// Provider for most recent sentence
final mostRecentSentenceProvider = FutureProvider<ThaiSentence?>((ref) async {
  final useCase = ref.watch(getSentencesUseCaseProvider);
  return await useCase.getMostRecent();
});

/// Provider for favorite sentences
final favoriteSentencesProvider =
    FutureProvider<List<ThaiSentence>>((ref) async {
  final useCase = ref.watch(getSentencesUseCaseProvider);
  return await useCase.getFavorites();
});

/// Provider for sentence count
final sentenceCountProvider = FutureProvider<int>((ref) async {
  final useCase = ref.watch(getSentencesUseCaseProvider);
  return await useCase.getCount();
});

/// Provider for checking if sentences exist
final hasSentencesProvider = FutureProvider<bool>((ref) async {
  final useCase = ref.watch(getSentencesUseCaseProvider);
  return await useCase.hasSentences();
});

// ==================== Sentence Controller ====================

/// Controller for managing sentence operations
class SentenceController extends StateNotifier<SentenceState> {
  final GenerateSentenceUseCase _generateUseCase;
  final GetSentencesUseCase _getUseCase;

  SentenceController(
    this._generateUseCase,
    this._getUseCase,
  ) : super(const SentenceStateInitial());

  /// Generate a new sentence
  Future<void> generateSentence() async {
    state = const SentenceStateLoading();

    try {
      final sentence = await _generateUseCase.execute();
      state = SentenceStateSuccess(sentence);
    } on GenerateSentenceException catch (e) {
      state = SentenceStateError(e.getUserMessage());
    } catch (e) {
      state = SentenceStateError('予期しないエラーが発生しました: $e');
    }
  }

  /// Load the most recent sentence
  Future<void> loadMostRecent() async {
    state = const SentenceStateLoading();

    try {
      final sentence = await _getUseCase.getMostRecent();
      if (sentence != null) {
        state = SentenceStateSuccess(sentence);
      } else {
        state = const SentenceStateEmpty();
      }
    } catch (e) {
      state = const SentenceStateError('データの読み込みに失敗しました');
    }
  }

  /// Toggle favorite status
  Future<void> toggleFavorite(String id, bool isFavorite) async {
    try {
      await _getUseCase.toggleFavorite(id, isFavorite);
      // Reload current sentence if needed
      if (state is SentenceStateSuccess) {
        final current = (state as SentenceStateSuccess).sentence;
        if (current.id == id) {
          state = SentenceStateSuccess(
            current.copyWith(isFavorite: isFavorite),
          );
        }
      }
    } catch (e) {
      // Handle error silently or show snackbar
    }
  }

  /// Reset state
  void reset() {
    state = const SentenceStateInitial();
  }
}

/// Provider for sentence controller
final sentenceControllerProvider =
    StateNotifierProvider<SentenceController, SentenceState>((ref) {
  final generateUseCase = ref.watch(generateSentenceUseCaseProvider);
  final getUseCase = ref.watch(getSentencesUseCaseProvider);

  return SentenceController(generateUseCase, getUseCase);
});

// ==================== Sentence State ====================

/// State for sentence operations
abstract class SentenceState {
  const SentenceState();
}

/// Initial state
class SentenceStateInitial extends SentenceState {
  const SentenceStateInitial();
}

/// Loading state
class SentenceStateLoading extends SentenceState {
  const SentenceStateLoading();
}

/// Success state with sentence
class SentenceStateSuccess extends SentenceState {
  final ThaiSentence sentence;

  const SentenceStateSuccess(this.sentence);
}

/// Error state
class SentenceStateError extends SentenceState {
  final String message;

  const SentenceStateError(this.message);
}

/// Empty state (no sentences)
class SentenceStateEmpty extends SentenceState {
  const SentenceStateEmpty();
}
