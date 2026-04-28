import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/datasources/backend_api_service.dart'
    show
        BackendApiNoUserSentencesException,
        BackendApiRateLimitException,
        BackendApiService;
import '../../data/datasources/local/database_helper.dart';
import '../../data/models/quiz_question.dart';
import '../../data/models/quiz_result.dart';
import '../../data/models/thai_sentence.dart';
import '../../services/analytics_service.dart';
import 'analytics_provider.dart';

final RegExp _thaiScriptRegex = RegExp(r'[฀-๿]');
final RegExp _nonThaiChoiceRegex = RegExp(r'[A-Za-z぀-ヿㇰ-ㇿ一-鿿]');
const String _savedConfirmationQuizKey = 'saved_confirmation_quiz';
const String _savedSummaryQuizKey = 'saved_summary_quiz';

// ==================== State ====================

abstract class QuizState {
  const QuizState();
}

class QuizInitial extends QuizState {
  const QuizInitial();
}

/// クイズ生成中（API呼び出し中）
class QuizGenerating extends QuizState {
  const QuizGenerating();
}

class QuizAnswering extends QuizState {
  final List<QuizQuestion> questions;
  final int index;
  final List<bool> answers;
  final List<int> selectedIndices;
  final List<int>? hintLevels;
  final List<bool>? sentenceReviewFlags;

  const QuizAnswering(
    this.questions,
    this.index,
    this.answers, [
    this.selectedIndices = const [],
    this.hintLevels = const [],
    this.sentenceReviewFlags = const [],
  ]);
}

class QuizShowResult extends QuizState {
  final List<QuizQuestion> questions;
  final int index;
  final List<bool> answers;
  final int selectedIndex;
  final bool isCorrect;
  final List<int> selectedIndices;
  final List<int>? hintLevels;
  final List<bool>? sentenceReviewFlags;

  const QuizShowResult(
    this.questions,
    this.index,
    this.answers,
    this.selectedIndex,
    this.isCorrect, [
    this.selectedIndices = const [],
    this.hintLevels = const [],
    this.sentenceReviewFlags = const [],
  ]);
}

class QuizSummary extends QuizState {
  final List<QuizQuestion> questions;
  final List<bool> answers;
  final int totalCorrect;
  final Map<String, dynamic> stats;
  final List<int> selectedIndices;
  final List<int>? hintLevels;
  final List<bool>? sentenceReviewFlags;

  const QuizSummary(
    this.questions,
    this.answers,
    this.totalCorrect,
    this.stats, [
    this.selectedIndices = const [],
    this.hintLevels = const [],
    this.sentenceReviewFlags = const [],
  ]);
}

/// ユーザー例文がないためクイズ生成不可
class QuizNoSentences extends QuizState {
  const QuizNoSentences();
}

/// クイズ生成エラー
class QuizError extends QuizState {
  final String message;
  const QuizError(this.message);
}

// ==================== Stats Model ====================

class QuizStatsData {
  final int totalAnswered;
  final int totalCorrect;
  final int currentStreak;
  final int bestStreak;
  final int accuracyPercent;

  const QuizStatsData({
    this.totalAnswered = 0,
    this.totalCorrect = 0,
    this.currentStreak = 0,
    this.bestStreak = 0,
    this.accuracyPercent = 0,
  });

  factory QuizStatsData.fromDatabase(Map<String, dynamic>? row) {
    if (row == null) return const QuizStatsData();
    final total = row['total_answered'] as int? ?? 0;
    final correct = row['total_correct'] as int? ?? 0;
    return QuizStatsData(
      totalAnswered: total,
      totalCorrect: correct,
      currentStreak: row['current_streak'] as int? ?? 0,
      bestStreak: row['best_streak'] as int? ?? 0,
      accuracyPercent: total > 0 ? (correct / total * 100).round() : 0,
    );
  }
}

// ==================== Controller ====================

class QuizController extends StateNotifier<QuizState> {
  final DatabaseHelper _db = DatabaseHelper.instance;
  final BackendApiService _apiService;
  final AnalyticsService _analytics;
  bool _isLearningQuiz = false;
  final List<Future<void>> _pendingUvmUpdates = [];

  // バックグラウンド事前生成用
  List<QuizQuestion>? _preparedQuestions;
  String? _preparedSentenceId;

  QuizController(this._apiService, this._analytics)
      : super(const QuizInitial());

  /// 例文生成直後にバックグラウンドでクイズを事前生成する（状態遷移なし）
  Future<void> prepareQuiz(ThaiSentence sentence) async {
    final sentenceId = sentence.id;
    if (sentenceId == null || sentenceId.isEmpty) return;
    if (sentenceId == _preparedSentenceId) return;

    _preparedSentenceId = sentenceId;
    _preparedQuestions = null;

    try {
      final questions = await _apiService.generateLearningQuiz(sentence);
      if (questions.length == 1 &&
          !_hasInvalidQuizChoices(questions) &&
          _preparedSentenceId == sentenceId) {
        _preparedQuestions = questions;
        await _saveConfirmationQuiz(sentenceId, questions);
      }
    } catch (e) {
      debugPrint('クイズ事前生成エラー: $e');
    }
  }

  /// 事前生成済みのクイズがあるか確認
  bool hasQuizFor(String? sentenceId) {
    return sentenceId != null &&
        sentenceId == _preparedSentenceId &&
        _preparedQuestions != null;
  }

  /// 事前生成中かどうか（APIコール中）
  bool isPreparingFor(String? sentenceId) {
    return sentenceId != null &&
        sentenceId == _preparedSentenceId &&
        _preparedQuestions == null;
  }

  /// 学習クイズを開始（事前生成済みなら即開始、なければ生成して開始）
  Future<void> startLearningQuiz(ThaiSentence sentence) async {
    _isLearningQuiz = true;
    unawaited(_clearSavedSummaryQuiz());
    final sentenceId = sentence.id;

    // 事前生成済みならそのまま開始
    if (hasQuizFor(sentenceId)) {
      _enterAnswering(_preparedQuestions!);
      return;
    }

    final savedQuestions = await _loadConfirmationQuiz(sentenceId);
    if (savedQuestions != null) {
      _preparedSentenceId = sentenceId;
      _preparedQuestions = savedQuestions;
      _enterAnswering(savedQuestions);
      return;
    }

    // 事前生成中 or 未開始 → 生成して開始
    state = const QuizGenerating();

    try {
      final questions = await _apiService.generateLearningQuiz(sentence);
      if (questions.length != 1 || _hasInvalidQuizChoices(questions)) {
        state = const QuizError('クイズの生成に失敗しました。もう一度お試しください。');
        return;
      }

      _preparedSentenceId = sentenceId;
      _preparedQuestions = questions;
      if (sentenceId != null && sentenceId.isNotEmpty) {
        await _saveConfirmationQuiz(sentenceId, questions);
      }
      _enterAnswering(questions);
    } on BackendApiRateLimitException {
      state = const QuizError('本日のクイズ生成上限に達しました。');
    } catch (e) {
      debugPrint('学習クイズ生成エラー: $e');
      state = const QuizError('クイズの生成に失敗しました。もう一度お試しください。');
    }
  }

  /// まとめクイズ（5問）を生成して開始
  Future<void> generateAndStartQuiz() async {
    _isLearningQuiz = false;

    final savedState = await _loadSummaryQuizState();
    if (savedState != null) {
      state = savedState;
      return;
    }

    try {
      state = const QuizGenerating();
      final questions = await _apiService.generateQuiz();
      if (questions.isEmpty || _hasInvalidQuizChoices(questions)) {
        state = const QuizError('クイズの生成に失敗しました。もう一度お試しください。');
        return;
      }

      _enterAnswering(questions);
    } on BackendApiNoUserSentencesException {
      state = const QuizNoSentences();
    } on BackendApiRateLimitException {
      state = const QuizError('本日のクイズ生成上限に達しました。');
    } catch (e) {
      debugPrint('クイズ生成エラー: $e');
      state = const QuizError('クイズの生成に失敗しました。もう一度お試しください。');
    }
  }

  /// アプリ再起動後に復元できる未完了のまとめクイズがあるか確認する。
  Future<bool> hasSavedSummaryQuiz() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey(_savedSummaryQuizKey);
  }

  /// 状態をリセット
  void reset() {
    _preparedQuestions = null;
    _preparedSentenceId = null;
    _pendingUvmUpdates.clear();
    unawaited(_clearSavedConfirmationQuiz());
    unawaited(_clearSavedSummaryQuiz());
    state = const QuizInitial();
  }

  /// 新しい例文生成時に、古い生成済みクイズを洗い替え対象として破棄する。
  Future<void> clearSavedGeneratedQuizzes() async {
    _preparedQuestions = null;
    _preparedSentenceId = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_savedConfirmationQuizKey);
    await prefs.remove(_savedSummaryQuizKey);
  }

  bool _hasInvalidQuizChoices(List<QuizQuestion> questions) {
    return questions.any((question) {
      if (question.choices.length != 4) {
        return true;
      }
      if (!_isThaiChoice(question.correctAnswer)) {
        return true;
      }
      if (!question.choices.contains(question.correctAnswer)) {
        return true;
      }
      return question.choices.any((choice) => !_isThaiChoice(choice));
    });
  }

  bool _isThaiChoice(String text) {
    final normalized = text.trim();
    return normalized.isNotEmpty &&
        _thaiScriptRegex.hasMatch(normalized) &&
        !_nonThaiChoiceRegex.hasMatch(normalized);
  }

  void _enterAnswering(List<QuizQuestion> questions) {
    final answeringState = QuizAnswering(questions, 0, []);
    state = answeringState;
    if (!_isLearningQuiz) {
      unawaited(_saveSummaryQuizState(answeringState));
    }
    unawaited(
      _analytics.logQuizStart(
        category: 'sentence_review',
        questionCount: questions.length,
      ),
    );
  }

  /// 回答を選択
  Future<void> answerQuestion(
    int choiceIndex, {
    int hintLevel = 0,
    bool reviewedSentence = false,
  }) async {
    if (state is! QuizAnswering) return;
    final s = state as QuizAnswering;
    final question = s.questions[s.index];
    final isCorrect = question.choices[choiceIndex] == question.correctAnswer;
    final newAnswers = [...s.answers, isCorrect];
    final newSelectedIndices = [...s.selectedIndices, choiceIndex];
    final newHintLevels = <int>[...s.hintLevels ?? const [], hintLevel];
    final newSentenceReviewFlags = <bool>[
      ...s.sentenceReviewFlags ?? const [],
      reviewedSentence,
    ];

    final result = QuizResult(
      id: '${question.sentenceId}_${DateTime.now().millisecondsSinceEpoch}',
      sentenceId: question.sentenceId,
      questionText: question.blankText,
      correctAnswer: question.correctAnswer,
      userAnswer: question.choices[choiceIndex],
      isCorrect: isCorrect,
      answeredAt: DateTime.now(),
    );
    await _db.insertQuizResult(result.toDatabase());

    final word = question.correctAnswer;
    if (word.isNotEmpty) {
      final uvmUpdate = _apiService.updateUvm(
        results: [
          {
            'word': word,
            'is_correct': isCorrect,
            'hint_level': hintLevel,
            if (reviewedSentence) 'sentence_reviewed': true,
          },
        ],
        quizType: _isLearningQuiz ? 'learning' : null,
      );
      _pendingUvmUpdates.add(uvmUpdate);
      unawaited(uvmUpdate.whenComplete(() {
        _pendingUvmUpdates.remove(uvmUpdate);
      }));
    }

    final resultState = QuizShowResult(
      s.questions,
      s.index,
      newAnswers,
      choiceIndex,
      isCorrect,
      newSelectedIndices,
      newHintLevels,
      newSentenceReviewFlags,
    );

    if (_isLearningQuiz && s.questions.length == 1) {
      await _showSummary(resultState);
    } else {
      state = resultState;
      if (!_isLearningQuiz) {
        unawaited(_saveSummaryQuizState(resultState));
      }
    }

    unawaited(
      _analytics.logQuizAnswer(
        correct: isCorrect,
        category: 'sentence_review',
        questionIndex: s.index + 1,
      ),
    );
  }

  /// 次の問題へ or サマリーへ
  Future<void> nextQuestion() async {
    if (state is! QuizShowResult) return;
    final s = state as QuizShowResult;
    final nextIndex = s.index + 1;

    if (nextIndex >= s.questions.length) {
      await _showSummary(s);
    } else {
      final answeringState = QuizAnswering(
        s.questions,
        nextIndex,
        s.answers,
        s.selectedIndices,
        s.hintLevels ?? const [],
        s.sentenceReviewFlags ?? const [],
      );
      state = answeringState;
      if (!_isLearningQuiz) {
        unawaited(_saveSummaryQuizState(answeringState));
      }
    }
  }

  Future<void> _showSummary(QuizShowResult s) async {
    if (!_isLearningQuiz && _pendingUvmUpdates.isNotEmpty) {
      await Future.wait(List<Future<void>>.of(_pendingUvmUpdates));
    }

    final totalCorrect = s.answers.where((a) => a).length;
    final today = _todayString();

    await _db.updateQuizStats(
      sessionCorrect: totalCorrect,
      sessionTotal: s.questions.length,
      quizDate: today,
    );

    final cachedStats = await _db.getCachedQuizStats();

    final summaryState = QuizSummary(
      s.questions,
      s.answers,
      totalCorrect,
      cachedStats ?? {},
      s.selectedIndices,
      s.hintLevels,
      s.sentenceReviewFlags,
    );

    if (_isLearningQuiz) {
      unawaited(_clearSavedConfirmationQuiz());
      unawaited(_clearSavedSummaryQuiz());
    } else {
      unawaited(_saveSummaryQuizState(summaryState));
    }

    state = summaryState;
  }

  /// 同じ問題でやり直し
  void retryQuiz() {
    if (state is! QuizSummary) return;
    final questions = (state as QuizSummary).questions;
    _enterAnswering(questions);
  }

  String _todayString() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  Future<void> _saveConfirmationQuiz(
    String sentenceId,
    List<QuizQuestion> questions,
  ) async {
    if (sentenceId.isEmpty || questions.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _savedConfirmationQuizKey,
      jsonEncode({
        'sentence_id': sentenceId,
        'questions': questions.map((question) => question.toJson()).toList(),
      }),
    );
  }

  Future<void> _clearSavedConfirmationQuiz() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_savedConfirmationQuizKey);
  }

  Future<void> _saveSummaryQuizState(QuizState summaryState) async {
    final snapshot = switch (summaryState) {
      QuizAnswering s => {
          'phase': 'answering',
          'questions':
              s.questions.map((question) => question.toJson()).toList(),
          'index': s.index,
          'answers': s.answers,
          'selected_indices': s.selectedIndices,
          'hint_levels': s.hintLevels ?? const <int>[],
          'sentence_review_flags': s.sentenceReviewFlags ?? const <bool>[],
        },
      QuizShowResult s => {
          'phase': 'result',
          'questions':
              s.questions.map((question) => question.toJson()).toList(),
          'index': s.index,
          'answers': s.answers,
          'selected_indices': s.selectedIndices,
          'hint_levels': s.hintLevels ?? const <int>[],
          'sentence_review_flags': s.sentenceReviewFlags ?? const <bool>[],
        },
      QuizSummary s => {
          'phase': 'summary',
          'questions':
              s.questions.map((question) => question.toJson()).toList(),
          'answers': s.answers,
          'total_correct': s.totalCorrect,
          'stats': s.stats,
          'selected_indices': s.selectedIndices,
          'hint_levels': s.hintLevels ?? const <int>[],
          'sentence_review_flags': s.sentenceReviewFlags ?? const <bool>[],
        },
      _ => null,
    };
    if (snapshot == null) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_savedSummaryQuizKey, jsonEncode(snapshot));
  }

  Future<void> _clearSavedSummaryQuiz() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_savedSummaryQuizKey);
  }

  Future<QuizState?> _loadSummaryQuizState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_savedSummaryQuizKey);
      if (saved == null || saved.isEmpty) return null;

      final data = jsonDecode(saved);
      if (data is! Map) return null;

      final rawQuestions = data['questions'];
      if (rawQuestions is! List) return null;

      final questions = rawQuestions
          .whereType<Map>()
          .map((json) => QuizQuestion.fromJson(Map<String, dynamic>.from(json)))
          .toList();
      if (questions.isEmpty || _hasInvalidQuizChoices(questions)) {
        return null;
      }

      final index = data['index'] is int ? data['index'] as int : 0;
      if (index < 0 || index >= questions.length) return null;

      final answers = _toBoolList(data['answers']);
      final selectedIndices = _toIntList(data['selected_indices']);
      final hintLevels = _toIntList(data['hint_levels']);
      final sentenceReviewFlags = _toBoolList(data['sentence_review_flags']);

      if (data['phase'] == 'result') {
        // 結果画面で終了 → 次の問題 or サマリーから再開
        final resumeIndex = index + 1;
        if (answers.length != resumeIndex) return null;
        if (resumeIndex >= questions.length) {
          final totalCorrect = answers.where((a) => a).length;
          final cachedStats =
              await DatabaseHelper.instance.getCachedQuizStats();
          return QuizSummary(
            questions,
            answers,
            totalCorrect,
            cachedStats ?? {},
            selectedIndices,
            hintLevels,
            sentenceReviewFlags,
          );
        }
        return QuizAnswering(
          questions,
          resumeIndex,
          answers,
          selectedIndices,
          hintLevels,
          sentenceReviewFlags,
        );
      }

      if (data['phase'] == 'summary') {
        if (answers.length != questions.length) return null;
        final totalCorrect =
            data['total_correct'] is int ? data['total_correct'] as int : 0;
        final stats = data['stats'] is Map
            ? Map<String, dynamic>.from(data['stats'] as Map)
            : <String, dynamic>{};
        return QuizSummary(
          questions,
          answers,
          totalCorrect,
          stats,
          selectedIndices,
          hintLevels,
          sentenceReviewFlags,
        );
      }

      if (answers.length != index) return null;
      return QuizAnswering(
        questions,
        index,
        answers,
        selectedIndices,
        hintLevels,
        sentenceReviewFlags,
      );
    } catch (e) {
      debugPrint('保存済みまとめクイズの読み込みエラー: $e');
      return null;
    }
  }

  Future<List<QuizQuestion>?> _loadConfirmationQuiz(String? sentenceId) async {
    if (sentenceId == null || sentenceId.isEmpty) return null;

    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_savedConfirmationQuizKey);
      if (saved == null || saved.isEmpty) return null;

      final data = jsonDecode(saved);
      if (data is! Map || data['sentence_id'] != sentenceId) {
        return null;
      }

      final rawQuestions = data['questions'];
      if (rawQuestions is! List) return null;

      final questions = rawQuestions
          .whereType<Map>()
          .map((json) => QuizQuestion.fromJson(Map<String, dynamic>.from(json)))
          .toList();
      if (questions.length != 1 || _hasInvalidQuizChoices(questions)) {
        return null;
      }

      return questions;
    } catch (e) {
      debugPrint('保存済み確認クイズの読み込みエラー: $e');
      return null;
    }
  }

  List<int> _toIntList(dynamic value) {
    if (value is! List) return const [];
    return value.whereType<int>().toList();
  }

  List<bool> _toBoolList(dynamic value) {
    if (value is! List) return const [];
    return value.whereType<bool>().toList();
  }
}

// ==================== Providers ====================

final quizControllerProvider =
    StateNotifierProvider<QuizController, QuizState>((ref) {
  return QuizController(
    BackendApiService(),
    ref.watch(analyticsServiceProvider),
  );
});

final quizStatsProvider = FutureProvider<QuizStatsData>((ref) async {
  final row = await DatabaseHelper.instance.getCachedQuizStats();
  return QuizStatsData.fromDatabase(row);
});
