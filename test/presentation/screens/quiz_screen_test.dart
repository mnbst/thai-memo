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

final _learningSentence = ThaiSentence(
  id: 'sentence-0',
  thaiText: 'นี่คือโจทย์ที่ 1 ภาษาไทย',
  pronunciation: 'nii khue coot thii nueng phasa thai',
  japaneseTranslation: 'これは問題1のタイ語です',
  wordBreakdowns: const [],
);

final _meaningQuestion = QuizQuestion(
  sentenceId: 'sentence-0',
  thaiText: 'ฉันชอบภาษาไทย',
  blankText: 'ฉันชอบ___',
  correctAnswer: 'ภาษาไทย',
  correctAnswerMeaning: 'タイ語',
  choices: const ['タイ語', '私', '好き', '本'],
  pronunciation: 'phasa thai',
  explanation: 'ภาษาไทย は「タイ語」を意味し、言語名を表す名詞です。',
  srsInterval: 7,
  japaneseTranslation: '私はタイ語が好きです',
  sentencePronunciation: 'chan chop phasa thai',
  dummyReasons: const [
    '私：ฉัน の意味です',
    '好き：ชอบ の意味です',
    '本：この単語の意味ではありません',
  ],
  sentenceDetail: _learningSentence,
  quizFormat: QuizQuestion.meaningChoiceFormat,
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
  const _QuizHarness({
    required this.controller,
    required this.database,
    required this.analytics,
  });

  final QuizController controller;
  final _FakeDatabaseHelper database;
  final FakeAnalyticsService analytics;
}

Future<_QuizHarness> _pumpSummaryQuiz(
  WidgetTester tester, {
  ThaiSentence? learningSentence,
  Future<void> Function()? onNextSentence,
  bool blockFirstInsert = false,
  List<QuizQuestion>? questions,
  double textScale = 1,
  bool showVocabScoreTransition = false,
}) async {
  final database = _FakeDatabaseHelper(blockFirstInsert: blockFirstInsert);
  final analytics = FakeAnalyticsService();
  final controller = QuizController(
    _FakeBackendApiService(questions),
    analytics,
    () => lookupL10n(const Locale('ja')),
    databaseHelper: database,
  );
  if (learningSentence != null) {
    await controller.startLearningQuiz(learningSentence);
  } else {
    await controller.generateAndStartQuiz();
  }

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        quizControllerProvider.overrideWith((ref) => controller),
        vocabStatsProvider.overrideWith(
          (ref) => Stream.value(const VocabStats(estimatedVocab: 20)),
        ),
        effectivePremiumProvider.overrideWithValue(false),
        analyticsServiceProvider.overrideWithValue(analytics),
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
          showVocabScoreTransition: showVocabScoreTransition,
        ),
      ),
    ),
  );
  await tester.pump();

  return _QuizHarness(
    controller: controller,
    database: database,
    analytics: analytics,
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('確認クイズは表示と回答時間・正誤を記録する', (tester) async {
    final harness = await _pumpSummaryQuiz(
      tester,
      learningSentence: _learningSentence,
      questions: [_questions.first],
    );

    expect(harness.analytics.confirmationQuizQuestionEvents, [
      {
        'action': 'shown',
        'quiz_format': 'cloze_choice',
        'response_ms': null,
        'correct': null,
        'exit_reason': null,
      },
    ]);

    await tester.pump(const Duration(milliseconds: 1200));
    await tester.tap(find.byKey(const ValueKey('quiz_choice_0')));
    await tester.pump();

    final answered = harness.analytics.confirmationQuizQuestionEvents.last;
    expect(answered['action'], 'answered');
    expect(answered['quiz_format'], 'cloze_choice');
    expect(answered['correct'], isTrue);
    expect(answered['response_ms'], isA<int>());
    expect(answered['response_ms'], greaterThanOrEqualTo(0));
    expect(answered['exit_reason'], isNull);
  });

  testWidgets('確認クイズを未回答で離れるとabandonedを記録する', (tester) async {
    final harness = await _pumpSummaryQuiz(
      tester,
      learningSentence: _learningSentence,
      questions: [_questions.first],
    );

    await tester.pump(const Duration(milliseconds: 800));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    final abandoned = harness.analytics.confirmationQuizQuestionEvents.last;
    expect(abandoned['action'], 'abandoned');
    expect(abandoned['quiz_format'], 'cloze_choice');
    expect(abandoned['correct'], isNull);
    expect(abandoned['response_ms'], isA<int>());
    expect(abandoned['response_ms'], greaterThanOrEqualTo(0));
    expect(abandoned['exit_reason'], 'screen_disposed');
  });

  testWidgets('確認意味4択の正解時も単語の解説を出し、元例文は出さない', (tester) async {
    final harness = await _pumpSummaryQuiz(
      tester,
      learningSentence: _learningSentence,
      questions: [_meaningQuestion],
    );

    expect(find.text('この単語の意味を選んでください'), findsOneWidget);
    expect(find.byKey(const ValueKey('quiz_meaning_word')), findsOneWidget);
    expect(find.text('ภาษาไทย'), findsOneWidget);
    // ローマ字はヒント扱いにせず出題時から常に出す。
    expect(
      find.byKey(const ValueKey('quiz_meaning_word_pronunciation')),
      findsOneWidget,
    );
    expect(find.text('phasa thai'), findsOneWidget);
    expect(find.text('ฉันชอบ___'), findsNothing);
    expect(find.text('私はタイ語が好きです'), findsNothing);
    expect(find.text('例文を復習する'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('quiz_choice_0')));
    await tester.pump();

    expect(harness.controller.state, isA<QuizSummary>());
    expect(find.text('単語の解説'), findsOneWidget);
    expect(find.byKey(const ValueKey('quiz_word_explanation')), findsOneWidget);
    expect(find.text(_meaningQuestion.explanation), findsOneWidget);
    expect(find.byKey(const ValueKey('quiz_source_sentence')), findsNothing);
    expect(find.text('chan chop phasa thai'), findsNothing);
    expect(find.text('私はタイ語が好きです'), findsNothing);

    final answerEvent = harness.analytics.quizAnswerEvents.single;
    expect(answerEvent['correct'], isTrue);
    expect(answerEvent['quiz_format'], QuizQuestion.meaningChoiceFormat);
    expect(answerEvent['srs_interval'], 7);
    expect(answerEvent['response_ms'], isA<int>());
  });

  testWidgets('確認意味4択の不正解時は正解語と単語解説だけを表示する', (tester) async {
    await _pumpSummaryQuiz(
      tester,
      learningSentence: _learningSentence,
      questions: [_meaningQuestion],
    );

    await tester.tap(find.byKey(const ValueKey('quiz_choice_1')));
    await tester.pump();

    expect(find.text('単語の解説'), findsOneWidget);
    expect(find.byKey(const ValueKey('quiz_word_explanation')), findsOneWidget);
    expect(find.text(_meaningQuestion.explanation), findsOneWidget);
    expect(find.text('この単語を使った例文'), findsNothing);
    expect(find.byKey(const ValueKey('quiz_source_sentence')), findsNothing);
    expect(find.text('ฉันชอบภาษาไทย'), findsNothing);
    expect(find.text('chan chop phasa thai'), findsNothing);
    expect(find.text('私はタイ語が好きです'), findsNothing);
    expect(find.text(_meaningQuestion.dummyReasons.first), findsNothing);
    expect(find.text('私'), findsNothing);
  });

  testWidgets('正解は同じ問題内で解説まで見せ、二重送信せず次へボタンで進む', (tester) async {
    final harness = await _pumpSummaryQuiz(
      tester,
      blockFirstInsert: true,
    );
    const correctChoiceKey = ValueKey('quiz_choice_0');

    expect(find.text('1 / 5'), findsOneWidget);
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
    // 解説を出す回は自分で読み終えてから進む。
    expect(find.text(_questions.first.explanation), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1500));
    expect(harness.controller.state, isA<QuizShowResult>());

    await tester.tap(find.byKey(const ValueKey('quiz_next_button')));
    await tester.pump();

    final state = harness.controller.state;
    expect(state, isA<QuizAnswering>());
    expect((state as QuizAnswering).index, 1);
    expect(find.text('2 / 5'), findsOneWidget);
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
    expect(find.text('1 / 5'), findsOneWidget);

    await tester.ensureVisible(nextButton);
    await tester.pumpAndSettle();
    expect(nextButton.hitTestable(), findsOneWidget);
    await tester.tap(nextButton);
    await tester.pump();

    final nextState = harness.controller.state;
    expect(nextState, isA<QuizAnswering>());
    expect((nextState as QuizAnswering).index, 1);
    expect(find.text('2 / 5'), findsOneWidget);
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

  testWidgets('5問クイズのヒントは発音→訳文の2段階で開き、段階を回答に渡す', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final harness = await _pumpSummaryQuiz(tester);
    final hintButton = find.byKey(const ValueKey('quiz_hint_button'));

    // 未使用時はどちらのヒントも出さない。
    expect(find.text('nii khue coot thii 1 ___'), findsNothing);
    expect(find.text(_questions.first.japaneseTranslation), findsNothing);

    await tester.ensureVisible(hintButton);
    await tester.tap(hintButton);
    await tester.pump();

    // 1段階目は発音だけ。訳文はまだ伏せたまま。
    expect(find.text('nii khue coot thii 1 ___'), findsOneWidget);
    expect(find.text(_questions.first.japaneseTranslation), findsNothing);

    await tester.ensureVisible(hintButton);
    await tester.tap(hintButton);
    await tester.pump();

    expect(find.text(_questions.first.japaneseTranslation), findsOneWidget);

    // 使い切ったあともボタンは不活性で残す。
    expect(hintButton, findsOneWidget);
    expect(find.text('ヒントは表示済み'), findsOneWidget);
    expect(tester.widget<TextButton>(hintButton).onPressed, isNull);

    final choice = find.byKey(const ValueKey('quiz_choice_0'));
    await tester.ensureVisible(choice);
    await tester.tap(choice);
    await tester.pump();

    final state = harness.controller.state as QuizShowResult;
    expect(state.hintLevels, [2]);
  });

  testWidgets('クイズ完了後に案内は一切出さない', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final harness = await _pumpSummaryQuiz(
      tester,
      showVocabScoreTransition: true,
      onNextSentence: () async {},
    );

    for (var i = 0; i < _questions.length; i++) {
      await harness.controller.answerQuestion(1);
      await tester.pump();
      await harness.controller.nextQuestion();
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 1300));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    // 使い方の案内は説明書に集約した。結果画面から案内は出さない。
    expect(find.byType(Dialog), findsNothing);
    expect(find.text('今後の進め方'), findsNothing);

    // レビュー依頼の遅延タイマーを消化してから終える。
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
  });
}
