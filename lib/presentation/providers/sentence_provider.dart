import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/datasources/local/database_helper.dart';
import '../../data/datasources/local/secure_storage_service.dart';
import '../../data/datasources/backend_api_service.dart';
import '../../data/models/thai_sentence.dart';
import '../../data/sentence_repository.dart';
import '../../domain/delete_sentence_usecase.dart';
import '../../domain/generate_sentence_usecase.dart';
import '../../domain/get_sentences_usecase.dart';
import '../../services/firebase_auth_service.dart';

// ==================== Repository Provider ====================

/// Provider for sentence repository
final sentenceRepositoryProvider = Provider<SentenceRepository>((ref) {
  return SentenceRepository(
    databaseHelper: DatabaseHelper.instance,
    apiService: BackendApiService(),
    secureStorage: SecureStorageService.instance,
    authService: FirebaseAuthService.instance,
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

/// Provider for delete sentence use case
final deleteSentenceUseCaseProvider = Provider<DeleteSentenceUseCase>((ref) {
  final repository = ref.watch(sentenceRepositoryProvider);
  return DeleteSentenceUseCase(repository);
});

// ==================== State Providers ====================

/// Provider for all sentences
final allSentencesProvider = FutureProvider<List<ThaiSentence>>((ref) async {
  final useCase = ref.watch(getSentencesUseCaseProvider);
  return await useCase.execute();
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

// ==================== Sentence Controller ====================

/// Controller for managing sentence operations
class SentenceController extends StateNotifier<SentenceState> {
  final GenerateSentenceUseCase _generateUseCase;
  final GetSentencesUseCase _getUseCase;
  final DeleteSentenceUseCase _deleteUseCase;

  SentenceController(
    this._generateUseCase,
    this._getUseCase,
    this._deleteUseCase,
  ) : super(const SentenceStateInitial());

  /// Generate a new sentence
  Future<void> generateSentence({
    Map<String, String?> generationParams = const {},
  }) async {
    state = const SentenceStateLoading();

    try {
      final sentence = await _generateUseCase.execute(
        generationParams: generationParams,
      );
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

  /// 今日まだ生成していなければ自動生成、済みなら最新を表示
  Future<void> loadOrGenerateToday({
    Map<String, String?> generationParams = const {},
  }) async {
    state = const SentenceStateLoading();

    try {
      final recent = await _getUseCase.getMostRecent();
      if (recent != null && _isToday(recent.createdAt)) {
        state = SentenceStateSuccess(recent);
        return;
      }

      // 今日未生成 → 自動生成
      try {
        final sentence = await _generateUseCase.execute(
          generationParams: generationParams,
        );
        state = SentenceStateSuccess(sentence);
      } catch (e) {
        // 生成失敗時は既存の最新例文を表示、なければサンプル表示
        if (recent != null) {
          state = SentenceStateSuccess(recent);
        } else {
          state = const SentenceStateEmpty();
        }
      }
    } catch (e) {
      state = const SentenceStateError('データの読み込みに失敗しました');
    }
  }

  bool _isToday(DateTime? date) {
    if (date == null) return false;
    final now = DateTime.now();
    return date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
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

  /// Delete a sentence
  Future<void> deleteSentence(String id) async {
    try {
      await _deleteUseCase.execute(id);
      // If the deleted sentence is the current one, clear the state
      if (state is SentenceStateSuccess) {
        final current = (state as SentenceStateSuccess).sentence;
        if (current.id == id) {
          state = const SentenceStateEmpty();
        }
      }
    } on DeleteSentenceException catch (e) {
      throw Exception(e.message);
    }
  }

  /// Delete all sentences
  Future<void> deleteAllSentences() async {
    try {
      await _deleteUseCase.deleteAll();
      state = const SentenceStateEmpty();
    } on DeleteSentenceException catch (e) {
      throw Exception(e.message);
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
  final deleteUseCase = ref.watch(deleteSentenceUseCaseProvider);

  return SentenceController(generateUseCase, getUseCase, deleteUseCase);
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
