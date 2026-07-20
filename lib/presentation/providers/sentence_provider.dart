import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/datasources/local/database_helper.dart';
import '../../data/datasources/local/secure_storage_service.dart';
import '../../data/datasources/backend_api_service.dart';
import '../../data/models/thai_sentence.dart';
import '../../data/sentence_repository.dart';
import '../../domain/delete_sentence_usecase.dart';
import '../../domain/generate_sentence_usecase.dart';
import '../../domain/get_sentences_usecase.dart';
import '../../services/analytics_service.dart';
import '../../services/firebase_auth_service.dart';
import 'analytics_provider.dart';
import 'remaining_quota_provider.dart';
import 'settings_provider.dart';
import 'subscription_provider.dart';

typedef GenerateSentenceCallback = Future<ThaiSentence> Function({
  Map<String, String?> generationParams,
});
typedef GetMostRecentSentenceCallback = Future<ThaiSentence?> Function();

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
  final AnalyticsService _analytics;
  final String Function() _currentTier;
  final String? Function() _currentTopic;
  final int Function() _trialRemaining;
  final Future<void> Function() _onTrialExhausted;
  final GenerateSentenceCallback? _generateSentenceOverride;
  final GetMostRecentSentenceCallback? _getMostRecentSentenceOverride;

  SentenceController(
    this._generateUseCase,
    this._getUseCase,
    this._deleteUseCase,
    this._analytics,
    this._currentTier,
    this._currentTopic,
    this._trialRemaining,
    this._onTrialExhausted, {
    GenerateSentenceCallback? generateSentence,
    GetMostRecentSentenceCallback? getMostRecentSentence,
  })  : _generateSentenceOverride = generateSentence,
        _getMostRecentSentenceOverride = getMostRecentSentence,
        super(const SentenceStateInitial());

  /// トライアル中（free かつ残回数あり）か
  bool get _trialActive => _currentTier() != 'premium' && _trialRemaining() > 0;

  /// Generate a new sentence
  ///
  /// テーマ（topic）の扱いは tier で決まる:
  /// free = おまかせ / premium・トライアル中 = ユーザー設定を反映。
  /// トライアル中はサーバーへ premium_trial フラグを送り、残回数を1消費する。
  Future<void> generateSentence({
    Map<String, String?> generationParams = const {},
  }) async {
    state = const SentenceStateLoading();
    await _generate(
      generationParams: generationParams,
      source: 'manual_single',
    );
  }

  /// tier 判定・トライアル消費後処理を共通化した生成本体。
  /// 呼び出し側で Loading 状態にしておくこと。
  ///
  /// [fallbackToRecentOnError] が true の場合、想定外エラー時はエラー表示ではなく
  /// 既存の最新例文（なければ空状態）にフォールバックする。自動生成経路で
  /// 起動直後にエラー画面を出さないための挙動。
  Future<void> _generate({
    required Map<String, String?> generationParams,
    required String source,
    bool fallbackToRecentOnError = false,
  }) async {
    final trialActive = _trialActive;
    final wasLastTrial = trialActive && _trialRemaining() <= 1;

    try {
      final sentence = await _executeGenerateSentence(
        generationParams:
            _effectiveGenerationParams(generationParams, trialActive),
      );
      state = SentenceStateSuccess(sentence, generated: true);
      _logGenerateSentence(
        count: 1,
        source: source,
        topicApplied: trialActive,
      );
      // トライアル最終回を使い切ったら、設定のテーマを「おまかせ」に戻す。
      // 以降はフリーに戻り、テーマ選択（プレミアム機能）が使えないため。
      if (_shouldClearTopicAfterTrial(wasLastTrial)) {
        await _onTrialExhausted();
      }
    } on GenerateSentenceException catch (e) {
      state = SentenceStateError(e.getUserMessage());
    } catch (e) {
      if (!fallbackToRecentOnError) {
        state = SentenceStateError('予期しないエラーが発生しました: $e');
        return;
      }
      // 生成失敗時は既存の最新例文を表示、なければサンプル表示
      final recent = await _executeGetMostRecentSentence();
      if (recent != null) {
        state = SentenceStateSuccess(recent);
      } else {
        state = const SentenceStateEmpty();
      }
    }
  }

  // サーバー側 (_effective_generation_params) でも同じフィルタあり
  Map<String, String?> _effectiveGenerationParams(
    Map<String, String?> generationParams,
    bool premiumTrial,
  ) {
    // トライアル中は premium 相当の扱い（テーマ維持＋フラグ送信）
    if (premiumTrial) {
      final trialParams = Map<String, String?>.from(generationParams);
      trialParams['premium_trial'] = 'true';
      return trialParams;
    }
    if (_currentTier() == 'premium') {
      return generationParams;
    }
    final effectiveParams = Map<String, String?>.from(generationParams);
    effectiveParams.remove('topic');
    return effectiveParams;
  }

  /// Load the most recent sentence
  Future<void> loadMostRecent() async {
    state = const SentenceStateLoading();

    try {
      final sentence = await _executeGetMostRecentSentence();
      if (sentence != null) {
        state = SentenceStateSuccess(sentence);
      } else {
        state = const SentenceStateEmpty();
      }
    } catch (e) {
      state = const SentenceStateError('データの読み込みに失敗しました');
    }
  }

  /// Firestoreフラグに基づき、未生成なら1件自動生成、済みなら最新を表示
  Future<void> loadOrGenerateToday({
    required bool dailySentenceGenerated,
    Map<String, String?> generationParams = const {},
  }) async {
    state = const SentenceStateLoading();

    try {
      if (dailySentenceGenerated) {
        // 今日生成済み → 最新を表示
        final recent = await _executeGetMostRecentSentence();
        if (recent != null) {
          state = SentenceStateSuccess(recent);
          return;
        }
        // ローカルDBが空（再インストール等） → フラグを無視して生成を試みる
      }

      // 未生成 → 1件生成
      await _generate(
        generationParams: generationParams,
        source: 'daily_auto',
        fallbackToRecentOnError: true,
      );
    } catch (e) {
      state = const SentenceStateError('データの読み込みに失敗しました');
    }
  }

  /// 通知から受け取った例文を直接表示する
  void showSentence(ThaiSentence sentence) {
    state = SentenceStateSuccess(sentence);
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

  Future<ThaiSentence> _executeGenerateSentence({
    Map<String, String?> generationParams = const {},
  }) {
    final generate = _generateSentenceOverride ?? _generateUseCase.execute;
    return generate(generationParams: generationParams);
  }

  Future<ThaiSentence?> _executeGetMostRecentSentence() {
    final getMostRecent =
        _getMostRecentSentenceOverride ?? _getUseCase.getMostRecent;
    return getMostRecent();
  }

  bool _shouldClearTopicAfterTrial(bool wasLastTrial) {
    return wasLastTrial && _currentTier() != 'premium';
  }

  /// [topicApplied] はトライアル適用で free ユーザーにもテーマが効いたか。
  /// premium 判定だけで絞るとトライアル分の topic が欠測するため明示的に渡す。
  void _logGenerateSentence({
    required int count,
    required String source,
    bool topicApplied = false,
  }) {
    // provider 側で tier/topic を読むことで、UI からイベント文脈を組み立てなくて済む。
    final tier = _currentTier();
    unawaited(
      _analytics.logGenerateSentence(
        tier: tier,
        topic: (tier == 'premium' || topicApplied) ? _currentTopic() : null,
        source: source,
        count: count,
      ),
    );
  }
}

/// Provider for sentence controller
final sentenceControllerProvider =
    StateNotifierProvider<SentenceController, SentenceState>((ref) {
  final generateUseCase = ref.watch(generateSentenceUseCaseProvider);
  final getUseCase = ref.watch(getSentencesUseCaseProvider);
  final deleteUseCase = ref.watch(deleteSentenceUseCaseProvider);
  final analytics = ref.watch(analyticsServiceProvider);

  return SentenceController(
    generateUseCase,
    getUseCase,
    deleteUseCase,
    analytics,
    () {
      final bool isPremium = ref.read(isPremiumRealtimeProvider).valueOrNull ??
          ref.read(isPremiumProvider);
      return isPremium ? 'premium' : 'free';
    },
    () => ref.read(generationParamsProvider)['topic'],
    () => ref.read(premiumTrialRemainingProvider).valueOrNull ?? 0,
    () => ref
        .read(settingsControllerProvider.notifier)
        .setGenerationParam('topic', null),
  );
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
  final bool generated;

  const SentenceStateSuccess(this.sentence, {this.generated = false});
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
