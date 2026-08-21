import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/l10n_provider.dart';
import '../../l10n/app_localizations.dart';
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
import 'interview_goal_provider.dart';
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
    apiService: BackendApiService(
      lang: () => ref.read(appLanguageProvider).code,
    ),
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
  final bool Function() _isTrialActive;

  /// テーマ未指定のときに使う、ヒアリング由来のテーマ。
  /// 呼ぶたびに引き直す（候補が複数あるものを1つに固定しない）。
  final String? Function()? _interviewTopic;

  /// 文言は言語設定に追従させたいので、値ではなく都度引く関数を持つ。
  final L10n Function() _l10n;
  final GenerateSentenceCallback? _generateSentenceOverride;
  final GetMostRecentSentenceCallback? _getMostRecentSentenceOverride;

  SentenceController(
    this._generateUseCase,
    this._getUseCase,
    this._deleteUseCase,
    this._analytics,
    this._currentTier,
    this._currentTopic,
    this._isTrialActive,
    this._l10n, {
    String? Function()? interviewTopic,
    GenerateSentenceCallback? generateSentence,
    GetMostRecentSentenceCallback? getMostRecentSentence,
  })  : _interviewTopic = interviewTopic,
        _generateSentenceOverride = generateSentence,
        _getMostRecentSentenceOverride = getMostRecentSentence,
        super(const SentenceStateInitial());

  /// トライアル中（free かつトライアル有効）か
  bool get _trialActive => _currentTier() != 'premium' && _isTrialActive();

  /// Generate a new sentence
  ///
  /// テーマ（topic）の扱いは tier で決まる:
  /// free = おまかせ / premium・トライアル中 = ユーザー設定を反映。
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
    } on GenerateSentenceException catch (e) {
      state = SentenceStateError(e.getUserMessage(_l10n()));
    } catch (e) {
      if (!fallbackToRecentOnError) {
        state = SentenceStateError(_l10n().errUnexpected('$e'));
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
      return _withInterviewTopic(trialParams);
    }
    if (_currentTier() == 'premium') {
      return _withInterviewTopic(
        Map<String, String?>.from(generationParams),
      );
    }
    final effectiveParams = Map<String, String?>.from(generationParams);
    effectiveParams.remove('topic');
    return effectiveParams;
  }

  /// テーマ未指定（おまかせ）なら、ヒアリングで申告した用途からテーマを決めて
  /// 明示指定として送る。CF 側はここで決まったテーマをそのまま使う。
  ///
  /// 端末で決めるのは、初回例文の生成が users doc への回答書き込みの着地を
  /// 待たずに済むため。サーバーから読ませると、書き込みが間に合わなかった
  /// 回だけテーマが効かない。
  Map<String, String?> _withInterviewTopic(Map<String, String?> params) {
    final current = params['topic'];
    if (current != null && current.isNotEmpty) return params;
    final topic = _interviewTopic?.call();
    if (topic == null) return params;
    params['topic'] = topic;
    return params;
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
      state = SentenceStateError(_l10n().errLoadFailed);
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
      state = SentenceStateError(_l10n().errLoadFailed);
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
    () => ref.read(premiumTrialActiveProvider).valueOrNull ?? false,
    () => ref.read(l10nProvider),
    interviewTopic: () => ref.read(interviewTopicProvider),
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
