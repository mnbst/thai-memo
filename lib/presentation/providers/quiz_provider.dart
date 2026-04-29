// =============================================================================
// quiz_provider.dart
// クイズ機能の状態管理。
//
// クイズには2種類ある:
//   1. 学習クイズ（Learning Quiz）: 例文生成直後に出題される1問の確認クイズ。
//      生成された例文の穴埋め問題で、学習内容の即時定着を促す。
//      事前生成（prepareQuiz）により、ユーザーが例文を読んでいる間に
//      バックグラウンドでクイズを準備しておくことで待ち時間を削減する。
//   2. まとめクイズ（Summary Quiz）: クイズタブから開始する5問の復習クイズ。
//      SRS（間隔反復）で選出された過去の例文から出題される。
//
// 状態遷移:
//   QuizInitial → QuizGenerating → QuizAnswering → QuizShowResult → QuizSummary
//                                       ↑               │
//                                       └───────────────┘ (次の問題へ)
//   エラー時: QuizGenerating → QuizError / QuizNoSentences
//
// 永続化:
//   SharedPreferencesにクイズ進行状態を保存し、アプリ再起動後も途中から再開可能。
//   学習クイズとまとめクイズで別々のキーを使用。
//
// UVM連携:
//   回答ごとにupdateUvm APIを非同期で呼び出し、語彙習熟度を更新する。
//   まとめクイズではサマリー表示前に全UVM更新の完了を待つ。
// =============================================================================

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

/// タイ文字のUnicode範囲にマッチする正規表現（選択肢バリデーション用）
final RegExp _thaiScriptRegex = RegExp(r'[฀-๿]');

/// タイ語以外の文字（英字・日本語・漢字）を検出する正規表現（不正な選択肢の検出用）
final RegExp _nonThaiChoiceRegex = RegExp(r'[A-Za-z぀-ヿㇰ-ㇿ一-鿿]');

/// 学習クイズ（1問確認クイズ）のSharedPreferences保存キー
const String _savedConfirmationQuizKey = 'saved_confirmation_quiz';

/// まとめクイズ（5問復習クイズ）のSharedPreferences保存キー
const String _savedSummaryQuizKey = 'saved_summary_quiz';

// =============================================================================
// クイズ状態クラス群
//
// Sealed classパターンで状態遷移を表現。各状態がそのフェーズに必要なデータを保持する。
// selectedIndices / hintLevels / sentenceReviewFlags は回答履歴の詳細で、
// サマリー画面での振り返り表示やUVM更新の精度向上に使用される。
// =============================================================================

/// クイズの状態を表す基底クラス
abstract class QuizState {
  const QuizState();
}

/// 初期状態（クイズ未開始）
class QuizInitial extends QuizState {
  const QuizInitial();
}

/// クイズ生成中（API呼び出し中）。ローディングUIを表示する。
class QuizGenerating extends QuizState {
  const QuizGenerating();
}

/// 問題に回答中の状態
///
/// [index] は現在の問題番号（0始まり）。
/// [answers] は回答済みの正誤リスト（長さ = index）。
/// [hintLevels] はヒント使用段階（0=未使用, 1=発音表示, 2=日本語表示）。
/// [sentenceReviewFlags] は回答前に例文を再確認したかどうか。
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

/// 1問の回答結果を表示中の状態（正解/不正解のフィードバック画面）
///
/// [selectedIndex] はユーザーが選んだ選択肢のインデックス。
/// [isCorrect] は正解だったかどうか。
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

/// 全問回答後のサマリー表示状態
///
/// [stats] はDBから取得した累積クイズ統計（連続日数・正答率など）。
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

/// ユーザーの学習済み例文がないためクイズ生成不可
class QuizNoSentences extends QuizState {
  const QuizNoSentences();
}

/// クイズ生成エラー（ネットワークエラー、レートリミット等）
class QuizError extends QuizState {
  final String message;
  const QuizError(this.message);
}

// =============================================================================
// クイズ統計データモデル
// quiz_statsテーブル（1行キャッシュ）から読み出した累積統計を保持する。
// サマリー画面やホーム画面の学習進捗表示で使用。
// =============================================================================

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

// =============================================================================
// クイズコントローラー
//
// クイズのライフサイクル全体を管理するStateNotifier。
// 主な責務:
//   - クイズの生成（API呼び出し）と事前生成（バックグラウンド）
//   - 回答の処理と正誤判定
//   - UVM（語彙習熟モデル）への結果送信
//   - クイズ進行状態のSharedPreferencesへの永続化・復元
//   - 選択肢のバリデーション（タイ語のみ・4択であることの検証）
//   - クイズ統計（累積正答数・連続日数）のDB更新
// =============================================================================

class QuizController extends StateNotifier<QuizState> {
  final DatabaseHelper _db = DatabaseHelper.instance;
  final BackendApiService _apiService;
  final AnalyticsService _analytics;

  /// 現在のクイズが学習クイズ（true）かまとめクイズ（false）かを区別するフラグ。
  /// UVM更新のタイミングやSP保存先キーの選択に影響する。
  bool _isLearningQuiz = false;

  /// 回答ごとに非同期で送信されるUVM更新のFutureリスト。
  /// まとめクイズのサマリー表示前にすべての完了を待つ。
  final List<Future<void>> _pendingUvmUpdates = [];

  /// バックグラウンド事前生成で準備済みのクイズ問題
  List<QuizQuestion>? _preparedQuestions;

  /// 事前生成の対象となった例文ID（重複生成防止用）
  String? _preparedSentenceId;

  QuizController(this._apiService, this._analytics)
      : super(const QuizInitial());

  /// 例文生成直後にバックグラウンドでクイズを事前生成する。
  ///
  /// 状態遷移を発生させずにAPIを呼び出し、結果をメモリとSPに保持する。
  /// ユーザーが例文を読んでいる間に裏で準備が完了するため、
  /// クイズ開始時の待ち時間がなくなる。
  /// 同じ例文IDに対する重複呼び出しはスキップされる。
  /// 生成中に別の例文のprepareが呼ばれた場合、古い結果は破棄される。
  Future<void> prepareQuiz(ThaiSentence sentence) async {
    final sentenceId = sentence.id;
    if (sentenceId == null || sentenceId.isEmpty) return;
    if (sentenceId == _preparedSentenceId) return;

    _preparedSentenceId = sentenceId;
    _preparedQuestions = null;

    try {
      final questions = await _apiService.generateLearningQuiz(sentence);
      // 学習クイズは1問のみ。バリデーション通過かつ、生成中に対象が変わっていなければ採用
      if (questions.length == 1 &&
          !_hasInvalidQuizChoices(questions) &&
          _preparedSentenceId == sentenceId) {
        _preparedQuestions = questions;
        final initialState = QuizAnswering(questions, 0, []);
        unawaited(
          _saveQuizState(_savedConfirmationQuizKey, initialState,
              sentenceId: sentenceId),
        );
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

  /// 学習クイズ（1問確認クイズ）を開始する。
  ///
  /// 復元の優先順位:
  ///   1. SharedPreferencesに保存済みの状態（アプリ再起動後の復元）
  ///   2. メモリ上の事前生成済みクイズ（prepareQuizで準備済み）
  ///   3. その場でAPI呼び出しして生成（フォールバック）
  Future<void> startLearningQuiz(ThaiSentence sentence) async {
    _isLearningQuiz = true;
    unawaited(_clearQuizState(_savedSummaryQuizKey));
    final sentenceId = sentence.id;

    // 1. SP保存済み状態を復元（途中回答やサマリー完了状態も含む）
    final savedState =
        await _loadQuizState(_savedConfirmationQuizKey, sentenceId: sentenceId);
    if (savedState != null) {
      _preparedSentenceId = sentenceId;
      state = savedState;
      return;
    }

    // 2. 事前生成済みならそのまま開始（待ち時間ゼロ）
    if (hasQuizFor(sentenceId)) {
      _enterAnswering(_preparedQuestions!);
      return;
    }

    // 3. 事前生成中 or 未開始 → その場で生成して開始
    state = const QuizGenerating();

    try {
      final questions = await _apiService.generateLearningQuiz(sentence);
      if (questions.length != 1 || _hasInvalidQuizChoices(questions)) {
        state = const QuizError('クイズの生成に失敗しました。もう一度お試しください。');
        return;
      }

      _preparedSentenceId = sentenceId;
      _preparedQuestions = questions;
      _enterAnswering(questions);
    } on BackendApiRateLimitException {
      state = const QuizError('本日のクイズ生成上限に達しました。');
    } catch (e) {
      debugPrint('学習クイズ生成エラー: $e');
      state = const QuizError('クイズの生成に失敗しました。もう一度お試しください。');
    }
  }

  /// まとめクイズ（5問の復習クイズ）を生成して開始する。
  ///
  /// SRS（間隔反復）で選出された過去の例文から穴埋め問題を生成。
  /// SP保存済みの途中状態があればそこから再開する。
  /// ユーザーの学習済み例文がない場合はQuizNoSentences状態に遷移。
  Future<void> generateAndStartQuiz() async {
    _isLearningQuiz = false;

    // SP保存済みの途中状態があれば復元
    final savedState = await _loadQuizState(_savedSummaryQuizKey);
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

  /// 全状態をリセットしてQuizInitialに戻す。
  /// メモリ上の事前生成データ・SP保存データ・UVM更新キューをすべてクリアする。
  void reset() {
    _preparedQuestions = null;
    _preparedSentenceId = null;
    _pendingUvmUpdates.clear();
    unawaited(_clearQuizState(_savedConfirmationQuizKey));
    unawaited(_clearQuizState(_savedSummaryQuizKey));
    state = const QuizInitial();
  }

  /// 新しい例文が生成されたときに呼ばれ、古いクイズデータを破棄する。
  /// 例文が更新されると既存のクイズは無効になるため、メモリとSP両方をクリアする。
  Future<void> clearSavedGeneratedQuizzes() async {
    _preparedQuestions = null;
    _preparedSentenceId = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_savedConfirmationQuizKey);
    await prefs.remove(_savedSummaryQuizKey);
  }

  /// クイズ問題の選択肢が有効かを検証する。
  ///
  /// 以下のいずれかに該当する場合、不正と判定:
  ///   - 選択肢が4つでない
  ///   - 正解がタイ語でない（英字・日本語・漢字を含む）
  ///   - 正解が選択肢リストに含まれていない
  ///   - いずれかの選択肢がタイ語でない
  /// Gemini APIが稀に不正な選択肢を返すことがあるため、この検証が必要。
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

  /// 選択肢のテキストがタイ語のみで構成されているかを判定する
  bool _isThaiChoice(String text) {
    final normalized = text.trim();
    return normalized.isNotEmpty &&
        _thaiScriptRegex.hasMatch(normalized) &&
        !_nonThaiChoiceRegex.hasMatch(normalized);
  }

  /// QuizAnswering状態に遷移してクイズを開始する共通メソッド。
  /// まとめクイズの場合はSPに状態を保存し、Analyticsにも開始イベントを送信する。
  void _enterAnswering(List<QuizQuestion> questions) {
    final answeringState = QuizAnswering(questions, 0, []);
    state = answeringState;
    if (!_isLearningQuiz) {
      unawaited(_saveQuizState(_savedSummaryQuizKey, answeringState));
    }
    unawaited(
      _analytics.logQuizStart(
        category: 'sentence_review',
        questionCount: questions.length,
      ),
    );
  }

  /// ユーザーが選択肢を選んだときに呼ばれる回答処理。
  ///
  /// 処理の流れ:
  ///   1. 正誤判定を行い、回答履歴（answers, selectedIndices等）を更新
  ///   2. ローカルDB（quiz_results）に回答結果を保存
  ///   3. UVM APIに回答結果を非同期送信（語彙習熟度の更新）
  ///   4. 学習クイズ（1問のみ）なら即サマリーへ、まとめクイズならQuizShowResultへ遷移
  ///   5. Analyticsに回答イベントを送信
  ///
  /// [hintLevel] はヒント使用段階。UVMの習熟度計算で正解の重みを調整するために使用。
  /// [reviewedSentence] は回答前に元の例文を確認したかどうか。
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

    // ローカルDBに回答結果を保存
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

    // UVMに回答結果を非同期送信（語彙習熟度P(know)の更新）
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

    // 学習クイズは1問のみなので、回答後即サマリーへ遷移
    if (_isLearningQuiz && s.questions.length == 1) {
      await _showSummary(resultState);
    } else {
      state = resultState;
      if (!_isLearningQuiz) {
        unawaited(_saveQuizState(_savedSummaryQuizKey, resultState));
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

  /// 回答結果画面から次の問題へ進む、または最終問題ならサマリーへ遷移する
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
        unawaited(_saveQuizState(_savedSummaryQuizKey, answeringState));
      }
    }
  }

  /// 全問回答後のサマリー画面を表示する。
  ///
  /// まとめクイズの場合、保留中のUVM更新をすべて待ってから遷移する。
  /// これにより、サマリー後にホーム画面に戻ったときの語彙スコア表示が
  /// 最新の状態になることを保証する。
  /// quiz_statsテーブルのセッション統計も更新する。
  Future<void> _showSummary(QuizShowResult s) async {
    // まとめクイズでは全UVM更新の完了を待ってからサマリーを表示
    if (!_isLearningQuiz && _pendingUvmUpdates.isNotEmpty) {
      await Future.wait(List<Future<void>>.of(_pendingUvmUpdates));
    }

    final totalCorrect = s.answers.where((a) => a).length;
    final today = _todayString();

    // quiz_statsテーブルの累積統計を更新（連続日数の計算含む）
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

    // 学習クイズはconfirmationキーに、まとめクイズはsummaryキーに保存
    if (_isLearningQuiz) {
      final sid = _preparedSentenceId;
      if (sid != null && sid.isNotEmpty) {
        unawaited(
          _saveQuizState(_savedConfirmationQuizKey, summaryState,
              sentenceId: sid),
        );
      }
      unawaited(_clearQuizState(_savedSummaryQuizKey));
    } else {
      unawaited(_saveQuizState(_savedSummaryQuizKey, summaryState));
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

  // ==========================================================================
  // SharedPreferences永続化
  //
  // クイズの進行状態をJSONとしてSharedPreferencesに保存・復元する。
  // アプリがバックグラウンドで終了された場合でも、途中から再開できるようにする。
  // 学習クイズ（_savedConfirmationQuizKey）とまとめクイズ（_savedSummaryQuizKey）で
  // 別々のキーを使用し、互いに独立して管理する。
  // ==========================================================================

  /// 現在のクイズ状態をSharedPreferencesにJSON保存する。
  /// [sentenceId] は学習クイズの場合に指定し、復元時に対象例文との照合に使う。
  Future<void> _saveQuizState(
    String key,
    QuizState quizState, {
    String? sentenceId,
  }) async {
    final snapshot = switch (quizState) {
      QuizAnswering s => {
          'phase': 'answering',
          if (sentenceId != null) 'sentence_id': sentenceId,
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
          if (sentenceId != null) 'sentence_id': sentenceId,
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
          if (sentenceId != null) 'sentence_id': sentenceId,
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
    await prefs.setString(key, jsonEncode(snapshot));
  }

  Future<void> _clearQuizState(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);
  }

  /// SharedPreferencesからクイズ状態を復元する。
  ///
  /// [sentenceId] が指定された場合、保存されたsentence_idと一致しなければnullを返す。
  /// これにより、別の例文用に保存されたクイズが誤って復元されるのを防ぐ。
  ///
  /// 復元時のフェーズ別処理:
  ///   - summary: そのままQuizSummaryとして復元
  ///   - result: 回答結果画面をスキップし、次の問題（または最終問題ならサマリー）に進める
  ///   - answering: そのままQuizAnsweringとして復元
  ///
  /// データの整合性チェック（問題数・回答数の一致、選択肢バリデーション）を行い、
  /// 不整合があればnullを返して新規生成にフォールバックさせる。
  Future<QuizState?> _loadQuizState(
    String key, {
    String? sentenceId,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(key);
      if (saved == null || saved.isEmpty) return null;

      final data = jsonDecode(saved);
      if (data is! Map) return null;
      if (sentenceId != null && data['sentence_id'] != sentenceId) return null;

      final phase = data['phase'];
      if (phase == null) return null;

      final rawQuestions = data['questions'];
      if (rawQuestions is! List) return null;

      final questions = rawQuestions
          .whereType<Map>()
          .map(
              (json) => QuizQuestion.fromJson(Map<String, dynamic>.from(json)))
          .toList();
      if (questions.isEmpty || _hasInvalidQuizChoices(questions)) return null;

      final selectedIndices = _toIntList(data['selected_indices']);
      final hintLevels = _toIntList(data['hint_levels']);
      final sentenceReviewFlags = _toBoolList(data['sentence_review_flags']);

      if (phase == 'summary') {
        final answers = _toBoolList(data['answers']);
        if (answers.length != questions.length) return null;
        return QuizSummary(
          questions,
          answers,
          data['total_correct'] is int ? data['total_correct'] as int : 0,
          data['stats'] is Map
              ? Map<String, dynamic>.from(data['stats'] as Map)
              : <String, dynamic>{},
          selectedIndices,
          hintLevels,
          sentenceReviewFlags,
        );
      }

      // result状態で保存された場合、回答結果画面はスキップして次に進める
      if (phase == 'result') {
        final index = data['index'] is int ? data['index'] as int : 0;
        if (index < 0 || index >= questions.length) return null;
        final answers = _toBoolList(data['answers']);
        final resumeIndex = index + 1;
        if (answers.length != resumeIndex) return null;
        // 最終問題の結果だった場合はサマリーに変換
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

      // answering状態の復元
      final index = data['index'] is int ? data['index'] as int : 0;
      final answers = _toBoolList(data['answers']);
      if (index < 0 || index >= questions.length || answers.length != index) {
        return null;
      }
      return QuizAnswering(
        questions,
        index,
        answers,
        selectedIndices,
        hintLevels,
        sentenceReviewFlags,
      );
    } catch (e) {
      debugPrint('クイズ状態の読み込みエラー ($key): $e');
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

// =============================================================================
// Riverpodプロバイダー定義
// =============================================================================

/// クイズコントローラーのプロバイダー。
/// UIはこのプロバイダーを通じてクイズの状態を監視し、操作を行う。
final quizControllerProvider =
    StateNotifierProvider<QuizController, QuizState>((ref) {
  return QuizController(
    BackendApiService(),
    ref.watch(analyticsServiceProvider),
  );
});

/// クイズ累積統計のプロバイダー。
/// quiz_statsテーブルから取得した統計データ（総回答数、正答率、連続日数）を提供する。
/// ホーム画面やサマリー画面の学習進捗表示で使用。
final quizStatsProvider = FutureProvider<QuizStatsData>((ref) async {
  final row = await DatabaseHelper.instance.getCachedQuizStats();
  return QuizStatsData.fromDatabase(row);
});
