import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thai_memo/data/datasources/backend_api_service.dart';
import 'package:thai_memo/data/datasources/local/database_helper.dart';
import 'package:thai_memo/data/models/quiz_question.dart';
import 'package:thai_memo/data/models/thai_sentence.dart';
import 'package:thai_memo/l10n/app_localizations.dart';
import 'package:thai_memo/presentation/providers/analytics_provider.dart';
import 'package:thai_memo/presentation/providers/quiz_provider.dart';
import 'package:thai_memo/presentation/providers/remaining_quota_provider.dart';
import 'package:thai_memo/presentation/providers/settings_provider.dart';
import 'package:thai_memo/presentation/providers/vocab_stats_provider.dart';
import 'package:thai_memo/presentation/screens/quiz_screen.dart';

import '../../helpers/fake_firebase.dart';

final _questions = List<QuizQuestion>.generate(
  5,
  (index) => QuizQuestion(
    sentenceId: 'sentence-$index',
    thaiText: 'นี่คือโจทย์ที่ ${index + 1} ภาษาไทย',
    blankText: 'นี่คือโจทย์ที่ ${index + 1} _____',
    correctAnswer: 'ภาษาไทย',
    correctAnswerMeaning: 'タイ語 ${index + 1}',
    choices: const ['ภาษาไทย', 'อาหาร', 'หนังสือ', 'เพลง'],
    pronunciation: 'phasa thai',
    explanation: '詳細解説 ${index + 1}',
    japaneseTranslation: 'これは問題 ${index + 1} の全文訳です',
    sentencePronunciation: 'nii khue coot thii ${index + 1} phasa thai',
    dummyReasons: ['อาหาร を選んだ場合の詳しい誤答理由 ${index + 1}'],
  ),
);

class _FakeBackendApiService extends Fake implements BackendApiService {
  _FakeBackendApiService([List<QuizQuestion>? questions])
      : _quizQuestions = questions ?? _questions;

  final List<QuizQuestion> _quizQuestions;

  @override
  Future<List<QuizQuestion>> generateQuiz() async => _quizQuestions;

  @override
  Future<List<QuizQuestion>> generateLearningQuiz(ThaiSentence sentence) async {
    return [_quizQuestions.first];
  }

  @override
  Future<void> updateUvm({
    required List<Map<String, dynamic>> results,
    String? quizType,
  }) async {}
}

class _FakeDatabaseHelper extends Fake implements DatabaseHelper {
  _FakeDatabaseHelper({bool blockFirstInsert = false})
      : _insertCompleter = blockFirstInsert ? Completer<int>() : null;

  final Completer<int>? _insertCompleter;
  int insertCallCount = 0;

  @override
  Future<int> insertQuizResult(Map<String, dynamic> result) {
    insertCallCount += 1;
    return _insertCompleter?.future ?? Future<int>.value(1);
  }

  void completeFirstInsert() {
    final completer = _insertCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.complete(1);
    }
  }

  @override
  Future<void> updateQuizStats({
    required int sessionCorrect,
    required int sessionTotal,
    required String quizDate,
  }) async {}

  @override
  Future<Map<String, dynamic>?> getCachedQuizStats() async => null;
}

class _QuizHarness {
  const _QuizHarness({required this.controller, required this.database});

  final QuizController controller;
  final _FakeDatabaseHelper database;
}

Future<_QuizHarness> _pumpSummaryQuiz(
  WidgetTester tester, {
  ThaiSentence? learningSentence,
  Future<void> Function()? onNextSentence,
  Future<void> Function()? onOptionalChallenge,
  bool blockFirstInsert = false,
  List<QuizQuestion>? questions,
  double textScale = 1,
  bool showVocabScoreTransition = false,
  VoidCallback? onNotificationCue,
}) async {
  final database = _FakeDatabaseHelper(blockFirstInsert: blockFirstInsert);
  final controller = QuizController(
    _FakeBackendApiService(questions),
    FakeAnalyticsService(),
    () => lookupL10n(const Locale('ja')),
    databaseHelper: database,
  );
  await controller.generateAndStartQuiz();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        quizControllerProvider.overrideWith((ref) => controller),
        vocabStatsProvider.overrideWith(
          (ref) => Stream.value(const VocabStats(estimatedVocab: 20)),
        ),
        effectivePremiumProvider.overrideWithValue(false),
        analyticsServiceProvider.overrideWithValue(FakeAnalyticsService()),
        generationParamsProvider.overrideWithValue(const {'topic': null}),
      ],
      child: MaterialApp(
        locale: const Locale('ja'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
          ),
          child: child!,
        ),
        home: QuizScreen(
          learningSentence: learningSentence,
          onNextSentence: onNextSentence,
          onOptionalChallenge: onOptionalChallenge,
          showVocabScoreTransition: showVocabScoreTransition,
          onNotificationCue: onNotificationCue,
        ),
      ),
    ),
  );
  await tester.pump();

  return _QuizHarness(controller: controller, database: database);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    resetSummaryCoachDeclined();
  });

  testWidgets('正解は同じ問題内で表示し、二重送信せず自動で次問へ進む', (tester) async {
    final harness = await _pumpSummaryQuiz(
      tester,
      blockFirstInsert: true,
    );
    const correctChoiceKey = ValueKey('quiz_choice_0');

    expect(find.text('問題 1 / 5'), findsOneWidget);
    expect(find.text(_questions.first.blankText), findsOneWidget);

    // DB保存を待っている間に連打しても、回答は一度だけ送る。
    await tester.tap(find.byKey(correctChoiceKey));
    await tester.tap(find.byKey(correctChoiceKey));
    expect(harness.database.insertCallCount, 1);

    harness.database.completeFirstInsert();
    await tester.pump();

    expect(harness.controller.state, isA<QuizShowResult>());
    expect(find.byKey(const ValueKey('quiz_inline_feedback')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('quiz_result_next_button')),
      findsNothing,
    );
    expect(find.text('正解！'), findsOneWidget);
    expect(find.text(_questions.first.blankText), findsOneWidget);
    for (var index = 0; index < 4; index++) {
      expect(find.byKey(ValueKey('quiz_choice_$index')), findsOneWidget);
    }
    expect(find.text(_questions.first.explanation), findsNothing);

    await tester.pump(const Duration(milliseconds: 1500));

    final state = harness.controller.state;
    expect(state, isA<QuizAnswering>());
    expect((state as QuizAnswering).index, 1);
    expect(find.text('問題 2 / 5'), findsOneWidget);
    expect(find.text(_questions[1].blankText), findsOneWidget);
  });

  testWidgets('不正解は既存の結果画面で詳しく復習し、次へボタンで進む', (tester) async {
    final harness = await _pumpSummaryQuiz(tester);

    await tester.tap(find.byKey(const ValueKey('quiz_choice_1')));
    await tester.pump();

    expect(harness.controller.state, isA<QuizShowResult>());
    expect(find.byKey(const ValueKey('quiz_inline_feedback')), findsNothing);
    expect(find.text('不正解'), findsOneWidget);
    expect(find.text('正解: ภาษาไทย'), findsOneWidget);
    expect(find.text('phasa thai'), findsOneWidget);
    expect(find.text('タイ語 1'), findsOneWidget);
    expect(find.text(_questions.first.thaiText), findsOneWidget);
    expect(find.text(_questions.first.sentencePronunciation), findsOneWidget);
    expect(
      find.text(_questions.first.japaneseTranslation),
      findsOneWidget,
    );
    expect(find.text(_questions.first.explanation), findsOneWidget);
    expect(find.text(_questions.first.dummyReasons.first), findsOneWidget);
    expect(find.text(_questions.first.blankText), findsNothing);
    expect(find.byKey(const ValueKey('quiz_choice_0')), findsNothing);

    final nextButton = find.byKey(const ValueKey('quiz_result_next_button'));
    expect(nextButton, findsOneWidget);

    await tester.pump(const Duration(seconds: 2));

    final resultState = harness.controller.state;
    expect(resultState, isA<QuizShowResult>());
    expect((resultState as QuizShowResult).index, 0);
    expect(find.text('問題 1 / 5'), findsOneWidget);

    await tester.ensureVisible(nextButton);
    await tester.pumpAndSettle();
    expect(nextButton.hitTestable(), findsOneWidget);
    await tester.tap(nextButton);
    await tester.pump();

    final nextState = harness.controller.state;
    expect(nextState, isA<QuizAnswering>());
    expect((nextState as QuizAnswering).index, 1);
    expect(find.text('問題 2 / 5'), findsOneWidget);
  });

  testWidgets('小さい画面と拡大文字でも結果画面を最後までスクロールできる', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _pumpSummaryQuiz(tester, textScale: 1.6);

    final wrongChoice = find.byKey(const ValueKey('quiz_choice_1'));
    await tester.ensureVisible(wrongChoice);
    await tester.tap(wrongChoice);
    await tester.pump();

    final layoutException = tester.takeException();
    expect(
      layoutException,
      isNull,
      reason: layoutException is FlutterError
          ? layoutException.toStringDeep()
          : layoutException?.toString(),
    );
    expect(find.text('正解: ภาษาไทย'), findsOneWidget);
    expect(find.text(_questions.first.thaiText), findsOneWidget);
    expect(
      find.text(_questions.first.sentencePronunciation),
      findsOneWidget,
    );
    expect(
      find.text(_questions.first.japaneseTranslation),
      findsOneWidget,
    );
    final nextButton = find.byKey(
      const ValueKey('quiz_result_next_button'),
    );
    expect(nextButton, findsOneWidget);
    await tester.ensureVisible(nextButton);
    await tester.pumpAndSettle();
    expect(nextButton.hitTestable(), findsOneWidget);
  });

  testWidgets('最終問の正解は自動進行せず、インラインの結果を見るから完了する', (tester) async {
    final harness = await _pumpSummaryQuiz(
      tester,
      questions: [_questions.first],
    );

    await tester.tap(find.byKey(const ValueKey('quiz_choice_0')));
    await tester.pump();

    expect(harness.controller.state, isA<QuizShowResult>());
    expect(find.byKey(const ValueKey('quiz_inline_feedback')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('quiz_result_next_button')),
      findsNothing,
    );

    final resultsButton = find.byKey(const ValueKey('quiz_next_button'));
    expect(
      find.descendant(
        of: resultsButton,
        matching: find.text('結果を見る'),
      ),
      findsOneWidget,
    );

    await tester.pump(const Duration(seconds: 2));
    expect(harness.controller.state, isA<QuizShowResult>());

    await tester.tap(resultsButton);
    await tester.pump();
    expect(harness.controller.state, isA<QuizSummary>());
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
  });

  testWidgets('旧形式の問題は欠損項目を隠し、正解語と既存の発音・完成文を表示する', (tester) async {
    final legacyQuestion = QuizQuestion.fromJson({
      'sentence_id': 'legacy-sentence',
      'thai_text': 'ทัวร์นี้เหมือนทัวร์นั้น',
      'blank_text': 'ทัวร์นี้___ทัวร์นั้น',
      'correct_answer': 'เหมือน',
      'choices': ['เหมือน', 'กิน', 'สูง', 'ไป'],
      'pronunciation': 'muean',
      'explanation': 'legacy explanation',
      'srs_interval': 0,
    });
    final harness = await _pumpSummaryQuiz(
      tester,
      questions: [legacyQuestion],
    );

    await tester.tap(find.byKey(const ValueKey('quiz_choice_2')));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('quiz_inline_feedback')), findsNothing);
    expect(find.text('正解: เหมือน'), findsOneWidget);
    expect(find.text('muean'), findsOneWidget);
    expect(find.text('ทัวร์นี้เหมือนทัวร์นั้น'), findsOneWidget);
    expect(find.text('legacy explanation'), findsOneWidget);

    final resultsButton = find.byKey(
      const ValueKey('quiz_result_next_button'),
    );
    expect(resultsButton, findsOneWidget);
    expect(
      find.descendant(
        of: resultsButton,
        matching: find.text('結果を見る'),
      ),
      findsOneWidget,
    );
    await tester.ensureVisible(resultsButton);
    await tester.pumpAndSettle();
    expect(resultsButton.hitTestable(), findsOneWidget);
    await tester.tap(resultsButton);
    await tester.pump();

    expect(harness.controller.state, isA<QuizSummary>());
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
  });

  testWidgets('まとめクイズの結果が出ると、演出が終わってから通知の案内へ渡す', (tester) async {
    var cued = 0;
    final harness = await _pumpSummaryQuiz(
      tester,
      showVocabScoreTransition: true,
      onNotificationCue: () => cued += 1,
    );

    // 全問を誤答で通す（クラッカー演出は出ない経路）。
    for (var i = 0; i < _questions.length; i++) {
      await harness.controller.answerQuestion(1);
      await tester.pump();
      await harness.controller.nextQuestion();
      await tester.pump();
    }
    expect(harness.controller.state, isA<QuizSummary>());

    // 語彙スコアの加算演出が流れている間はまだ渡さない。
    await tester.pump(const Duration(milliseconds: 1200));
    expect(cued, 0);

    await tester.pump(const Duration(milliseconds: 700));
    expect(cued, 1);
    await tester.pumpAndSettle();
  });

  testWidgets('まとめクイズの案内は初回だけ強制で、逃げ道を出さない', (tester) async {
    // 案内カードは対象の近くに出る。結果画面が縦に長いので画面も広く取る。
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final questions = _questions.take(2).toList();
    final harness = await _pumpSummaryQuiz(
      tester,
      questions: questions,
      onNextSentence: () async {},
      onOptionalChallenge: () async {},
    );

    for (var i = 0; i < questions.length; i++) {
      await harness.controller.answerQuestion(1);
      await tester.pump();
      await harness.controller.nextQuestion();
      await tester.pump();
    }
    await tester.pumpAndSettle();

    expect(find.text('まとめクイズに挑戦'), findsOneWidget);
    // 「あとで」は出さない。
    expect(find.text('あとで'), findsNothing);

    // 暗幕を押しても閉じない（押せる場所は光っているボタンだけ）。
    await tester.tapAt(const Offset(400, 40));
    await tester.pumpAndSettle();
    expect(find.text('まとめクイズに挑戦'), findsOneWidget);

    // レビュー依頼の遅延タイマーを消化してから終える。
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
  });

  testWidgets('テーマの案内を「あとで」で断ったら、別の案内は続けて出さない',
      (tester) async {
    // 案内カードは対象の近くに出る。結果画面が縦に長いので画面も広く取る。
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final questions = _questions.take(2).toList();
    final harness = await _pumpSummaryQuiz(
      tester,
      questions: questions,
      onNextSentence: () async {},
    );

    for (var i = 0; i < questions.length; i++) {
      await harness.controller.answerQuestion(1);
      await tester.pump();
      await harness.controller.nextQuestion();
      await tester.pump();
    }
    await tester.pumpAndSettle();

    expect(find.text('次の例文のテーマを選べます'), findsOneWidget);
    await tester.tap(find.text('あとで'));
    await tester.pumpAndSettle();

    // 断った直後に別の案内を重ねない。誘導ボタンのある結果画面へ移っても、
    // この起動の間は出さない。
    await _pumpSummaryQuiz(
      tester,
      questions: questions,
      onNextSentence: () async {},
      onOptionalChallenge: () async {},
    );
    await tester.pumpAndSettle();
    expect(find.text('まとめクイズに挑戦'), findsNothing);

    // レビュー依頼の遅延タイマーを消化してから終える。
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
  });
}
