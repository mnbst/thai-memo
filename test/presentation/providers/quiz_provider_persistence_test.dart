import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thai_memo/data/datasources/backend_api_service.dart';
import 'package:thai_memo/data/datasources/local/database_helper.dart';
import 'package:thai_memo/data/models/quiz_question.dart';
import 'package:thai_memo/data/models/thai_sentence.dart';
import 'package:thai_memo/l10n/app_localizations.dart';
import 'package:thai_memo/presentation/providers/quiz_provider.dart';
import 'package:thai_memo/services/analytics_service.dart';
import 'package:thai_memo/services/learning_progress_store.dart';

const _savedSummaryQuizKey = 'saved_summary_quiz';
const _savedConfirmationQuizKey = 'saved_confirmation_quiz';

QuizQuestion _question(int index) => QuizQuestion(
      sentenceId: 'sentence-$index',
      thaiText: 'ฉันชอบภาษาไทย',
      blankText: 'ฉันชอบ _____',
      correctAnswer: 'ภาษาไทย',
      choices: const ['ภาษาไทย', 'อาหาร', 'หนังสือ', 'เพลง'],
      pronunciation: 'phasa thai',
      explanation: 'タイ語',
    );

final _learningSentence = ThaiSentence(
  id: 'sentence-legacy',
  thaiText: 'ฉันชอบภาษาไทย',
  pronunciation: 'chan chop phasa thai',
  japaneseTranslation: '私はタイ語が好きです',
  wordBreakdowns: const [],
);

class _CountingBackendApiService extends Fake implements BackendApiService {
  _CountingBackendApiService({
    required this.summaryFallback,
    required this.learningFallback,
  });

  final List<QuizQuestion> summaryFallback;
  final List<QuizQuestion> learningFallback;
  int generateQuizCalls = 0;
  int generateLearningQuizCalls = 0;

  @override
  Future<List<QuizQuestion>> generateQuiz() async {
    generateQuizCalls++;
    return summaryFallback;
  }

  @override
  Future<List<QuizQuestion>> generateLearningQuiz(ThaiSentence sentence) async {
    generateLearningQuizCalls++;
    return learningFallback;
  }

  @override
  Future<void> updateUvm({
    required List<Map<String, dynamic>> results,
    String? quizType,
  }) async {}
}

class _FakeDatabaseHelper extends Fake implements DatabaseHelper {
  _FakeDatabaseHelper({this.cachedStats});

  final Map<String, dynamic>? cachedStats;

  @override
  Future<Map<String, dynamic>?> getCachedQuizStats() async => cachedStats;

  @override
  Future<int> insertQuizResult(Map<String, dynamic> result) async => 1;

  @override
  Future<void> updateQuizStats({
    required int sessionCorrect,
    required int sessionTotal,
    required String quizDate,
  }) async {}
}

class _FakeAnalyticsService extends Fake implements AnalyticsService {
  @override
  Future<void> logQuizStart({
    required String category,
    int? questionCount,
    String? source,
  }) async {}

  @override
  Future<void> logQuizAnswer({
    required bool correct,
    required String category,
    int? questionIndex,
    String? source,
    String? quizFormat,
    int? srsInterval,
    int? responseMs,
  }) async {}
}

QuizController _controller({
  required _CountingBackendApiService backend,
  Map<String, dynamic>? cachedStats,
}) {
  return QuizController(
    backend,
    _FakeAnalyticsService(),
    () => lookupL10n(const Locale('ja')),
    databaseHelper: _FakeDatabaseHelper(cachedStats: cachedStats),
  );
}

/// 1.4.10 以前の端末に残っていた形。カーソルとクイズが別キーに入っている。
String _legacyCursor({
  required String setId,
  required List<String> ids,
  required String currentId,
}) =>
    jsonEncode({
      'active': {'set_id': setId, 'sentence_ids': ids},
      'active_index': ids.indexOf(currentId),
      'active_sentence_id': currentId,
      'pending': <dynamic>[],
      'completed_set_ids': <String>[],
    });

/// いまの保存先（学習レコード）から、クイズの枠を読む。
Future<Map<String, dynamic>?> _savedQuiz({required bool summary}) async {
  final record = await LearningProgressStore().load();
  return summary ? record.summaryQuiz : record.confirmationQuiz;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('旧result中間状態を次のQuizAnsweringへ復元しAPI生成しない', () async {
    final questions = [_question(1), _question(2), _question(3)];
    SharedPreferences.setMockInitialValues({
      'daily_set_progress':
          _legacyCursor(setId: 'set-a', ids: ['a', 'b'], currentId: 'b'),
      _savedSummaryQuizKey: jsonEncode({
        'phase': 'result',
        'set_id': 'set-a',
        'questions': questions.map((question) => question.toJson()).toList(),
        'index': 0,
        'answers': [true],
        // 旧スナップショットには以下のoptional履歴フィールドがない:
        // selected_indices / hint_levels / sentence_review_flags
      }),
    });
    final backend = _CountingBackendApiService(
      summaryFallback: [_question(99)],
      learningFallback: [_question(98)],
    );
    final controller = _controller(backend: backend);

    expect(await controller.restoreSavedSummaryQuiz(), isTrue);

    expect(backend.generateQuizCalls, 0);
    expect(controller.state, isA<QuizAnswering>());
    final restored = controller.state as QuizAnswering;
    expect(restored.questions.map((question) => question.sentenceId),
        ['sentence-1', 'sentence-2', 'sentence-3']);
    expect(restored.index, 1);
    expect(restored.answers, [true]);
    expect(restored.selectedIndices, isEmpty);
    expect(restored.hintLevels, isEmpty);
    expect(restored.sentenceReviewFlags, isEmpty);
  });

  test('旧result最終状態をQuizSummaryへ復元しAPI生成しない', () async {
    final questions = [_question(1), _question(2), _question(3)];
    SharedPreferences.setMockInitialValues({
      'daily_set_progress':
          _legacyCursor(setId: 'set-a', ids: ['a', 'b'], currentId: 'b'),
      _savedSummaryQuizKey: jsonEncode({
        'phase': 'result',
        'set_id': 'set-a',
        'questions': questions.map((question) => question.toJson()).toList(),
        'index': 2,
        'answers': [true, false, true],
      }),
    });
    final backend = _CountingBackendApiService(
      summaryFallback: [_question(99)],
      learningFallback: [_question(98)],
    );
    final cachedStats = <String, dynamic>{
      'total_answered': 12,
      'total_correct': 9,
    };
    final controller = _controller(
      backend: backend,
      cachedStats: cachedStats,
    );

    expect(await controller.restoreSavedSummaryQuiz(), isTrue);

    expect(backend.generateQuizCalls, 0);
    expect(controller.state, isA<QuizSummary>());
    final restored = controller.state as QuizSummary;
    expect(restored.answers, [true, false, true]);
    expect(restored.totalCorrect, 2);
    expect(restored.stats, cachedStats);
    expect(restored.selectedIndices, isEmpty);
    expect(restored.hintLevels, isEmpty);
    expect(restored.sentenceReviewFlags, isEmpty);
  });

  test('phaseなし旧confirmation状態をQuizAnsweringへ復元しAPI生成しない', () async {
    final savedQuestion = QuizQuestion(
      sentenceId: 'sentence-legacy',
      thaiText: 'ฉันชอบภาษาไทย',
      blankText: 'ฉันชอบ _____',
      correctAnswer: 'ภาษาไทย',
      choices: const ['ภาษาไทย', 'อาหาร', 'หนังสือ', 'เพลง'],
      pronunciation: 'phasa thai',
      explanation: 'タイ語',
    );
    SharedPreferences.setMockInitialValues({
      'daily_set_progress': _legacyCursor(
        setId: 'set-a',
        ids: ['sentence-legacy', 'b'],
        currentId: 'sentence-legacy',
      ),
      _savedConfirmationQuizKey: jsonEncode({
        'sentence_id': 'sentence-legacy',
        'questions': [savedQuestion.toJson()],
      }),
    });
    final backend = _CountingBackendApiService(
      summaryFallback: [_question(99)],
      learningFallback: [_question(98)],
    );
    final controller = _controller(backend: backend);

    await controller.startLearningQuiz(_learningSentence);

    expect(backend.generateLearningQuizCalls, 0);
    expect(controller.state, isA<QuizAnswering>());
    final restored = controller.state as QuizAnswering;
    expect(restored.index, 0);
    expect(restored.answers, isEmpty);
    expect(restored.questions.single.sentenceId, 'sentence-legacy');
  });

  test('新版の自動進行後も旧phaseとフィールド名で最新状態を保存する', () async {
    final questions = [_question(1), _question(2), _question(3)];
    final backend = _CountingBackendApiService(
      summaryFallback: questions,
      learningFallback: [_question(98)],
    );
    final controller = _controller(backend: backend);

    await controller.generateAndStartQuiz();
    await controller.answerQuestion(0);
    await controller.nextQuestion();

    // 保存キューの完了を待ち、result保存が次問題のanswering保存を
    // 後から上書きしないことも同時に確認する。
    await controller.waitForSavedQuizWrites();
    final saved = (await _savedQuiz(summary: true))!;

    expect(saved['phase'], 'answering');
    expect(saved['index'], 1);
    expect(saved['answers'], [true]);
    expect(
        saved.keys,
        containsAll(<String>[
          'phase',
          'questions',
          'index',
          'answers',
          'selected_indices',
          'hint_levels',
          'sentence_review_flags',
        ]));
  });

  group('現行形式の保存と復元の往復', () {
    // 旧形式の読み込みテストはあるが、いま書いた保存をいま読む経路が無かった。
    // 保存の形をこの先まとめるので、畳む前の振る舞いをここで固定する。
    _CountingBackendApiService backend() => _CountingBackendApiService(
          summaryFallback: [_question(1), _question(2)],
          learningFallback: [_question(8)],
        );

    test('回答中のまとめクイズは同じ位置から再開する', () async {
      final controller = _controller(backend: backend());
      await controller.generateAndStartQuiz();
      await controller.answerQuestion(0);
      await controller.nextQuestion();
      expect(controller.state, isA<QuizAnswering>());
      await controller.waitForSavedQuizWrites();

      final restored = _controller(backend: backend());
      expect(await restored.restoreSavedSummaryQuiz(), isTrue);
      final state = restored.state as QuizAnswering;
      expect(state.index, 1);
      expect(state.answers, [true]);
    });

    test('結果表示中のまとめクイズは次の問題から再開する', () async {
      final controller = _controller(backend: backend());
      await controller.generateAndStartQuiz();
      await controller.answerQuestion(0);
      expect(controller.state, isA<QuizShowResult>());
      await controller.waitForSavedQuizWrites();

      final restored = _controller(backend: backend());
      expect(await restored.restoreSavedSummaryQuiz(), isTrue);
      final state = restored.state as QuizAnswering;
      expect(state.index, 1);
      expect(state.answers, [true]);
    });

    test('終わったまとめクイズは結果画面のまま再開する', () async {
      // 「結果画面で離脱して再起動したら、まとめクイズをやり直しになる」の
      // 保存側。ここが壊れていないことを先に固定しておく。
      final controller = _controller(backend: backend());
      await controller.generateAndStartQuiz();
      await controller.answerQuestion(0);
      await controller.nextQuestion();
      await controller.answerQuestion(0);
      await controller.nextQuestion();
      expect(controller.state, isA<QuizSummary>());
      await controller.waitForSavedQuizWrites();

      final restored = _controller(backend: backend());
      expect(await restored.restoreSavedSummaryQuiz(), isTrue);
      final state = restored.state as QuizSummary;
      expect(state.answers, [true, true]);
      expect(state.totalCorrect, 2);
      expect(restored.state, isA<QuizSummary>());
    });
  });

  group('保存の後始末', () {
    test('reset は確認クイズもまとめクイズも保存を消す', () async {
      final controller = _controller(
        backend: _CountingBackendApiService(
          summaryFallback: [_question(1), _question(2)],
          learningFallback: [_question(3)],
        ),
      );
      await controller.generateAndStartQuiz();
      await controller.prepareQuiz(_learningSentence);
      await controller.waitForSavedQuizWrites();
      expect(await _savedQuiz(summary: true), isNotNull);
      expect(await _savedQuiz(summary: false), isNotNull);

      controller.reset();
      await controller.waitForSavedQuizWrites();

      expect(await _savedQuiz(summary: true), isNull);
      expect(await _savedQuiz(summary: false), isNull);
      expect(controller.state, isA<QuizInitial>());
    });

    test('確認クイズの保存は対象の例文が一致しなければ使わない', () async {
      // まとめクイズ側（set_id）には2件あるが、確認クイズ側（sentence_id）の
      // 照合を押さえたものが無かった。
      final backend = _CountingBackendApiService(
        summaryFallback: [_question(1)],
        learningFallback: [_question(5)],
      );
      final controller = _controller(backend: backend);
      await controller.prepareQuiz(_learningSentence);
      await controller.waitForSavedQuizWrites();

      expect(await _savedQuiz(summary: false), isNotNull);
      expect(controller.hasQuizFor(_learningSentence.id), isTrue);
      expect(controller.hasQuizFor('sentence-other'), isFalse);

      // 別の例文で開いたら、保存は使わずその例文のぶんを作り直す。
      final other = ThaiSentence(
        id: 'sentence-other',
        thaiText: 'ผมหิว',
        pronunciation: 'phom hiu',
        japaneseTranslation: 'お腹がすいた',
        wordBreakdowns: const [],
      );
      await controller.startLearningQuiz(other);

      expect(backend.generateLearningQuizCalls, 2);
      expect(controller.state, isA<QuizAnswering>());
    });
  });

  group('1.4.10 以前の保存からの移行', () {
    // 旧版はクイズを別キーに置き、持ち主（セットID・例文ID）を保存へ添えて
    // 突き合わせていた。いまは学習レコードに畳むので、突き合わせるのは
    // 畳むときの1回だけ。持ち主が違うものは引き継がない。
    Map<String, Object> legacy({
      required String cursorSetId,
      required String savedSetId,
    }) =>
        {
          'daily_set_progress': jsonEncode({
            'active': {
              'set_id': cursorSetId,
              'sentence_ids': ['a', 'b'],
            },
            'active_index': 0,
            'active_sentence_id': 'a',
            'pending': <dynamic>[],
            'completed_set_ids': <String>[],
          }),
          _savedSummaryQuizKey: jsonEncode({
            'phase': 'summary',
            'set_id': savedSetId,
            'questions': [_question(1).toJson()],
            'answers': [true],
          }),
        };

    test('終わったセットのまとめクイズは引き継がない', () async {
      SharedPreferences.setMockInitialValues(
        legacy(cursorSetId: 'set-new', savedSetId: 'set-old'),
      );
      final controller = _controller(
        backend: _CountingBackendApiService(
          summaryFallback: [_question(99)],
          learningFallback: [_question(98)],
        ),
      );

      expect(await controller.restoreSavedSummaryQuiz(), isFalse);
      expect(controller.state, isA<QuizInitial>());
    });

    test('進行中セットのまとめクイズは続きから開く', () async {
      SharedPreferences.setMockInitialValues(
        legacy(cursorSetId: 'set-a', savedSetId: 'set-a'),
      );
      final controller = _controller(
        backend: _CountingBackendApiService(
          summaryFallback: [_question(99)],
          learningFallback: [_question(98)],
        ),
      );

      expect(await controller.restoreSavedSummaryQuiz(), isTrue);
      expect(controller.state, isA<QuizSummary>());
    });

    test('持ち主を持たない旧データは引き継がない', () async {
      // 1.4.9 以前の保存にはセットIDが無い。どのセットのものか分からない。
      SharedPreferences.setMockInitialValues({
        _savedSummaryQuizKey: jsonEncode({
          'phase': 'summary',
          'questions': [_question(1).toJson()],
          'answers': [true],
        }),
      });
      final controller = _controller(
        backend: _CountingBackendApiService(
          summaryFallback: [_question(99)],
          learningFallback: [_question(98)],
        ),
      );

      expect(await controller.restoreSavedSummaryQuiz(), isFalse);
    });
  });
}
