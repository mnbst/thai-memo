import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thai_memo/data/datasources/backend_api_service.dart';
import 'package:thai_memo/data/datasources/local/database_helper.dart';
import 'package:thai_memo/data/models/quiz_question.dart';
import 'package:thai_memo/data/models/thai_sentence.dart';
import 'package:thai_memo/l10n/app_localizations.dart';
import 'package:thai_memo/presentation/providers/quiz_provider.dart';

import '../../helpers/fake_firebase.dart';

const _question = QuizQuestion(
  sentenceId: 'sentence-1',
  thaiText: 'ฉันชอบภาษาไทย',
  blankText: 'ฉันชอบ _____',
  correctAnswer: 'ภาษาไทย',
  choices: ['ภาษาไทย', 'อาหาร', 'หนังสือ', 'เพลง'],
  pronunciation: 'phasa thai',
  explanation: 'タイ語',
);

final _sentence = ThaiSentence(
  id: 'sentence-1',
  thaiText: 'ฉันชอบภาษาไทย',
  pronunciation: 'chan chop phasa thai',
  japaneseTranslation: '私はタイ語が好きです',
  wordBreakdowns: const [],
);

/// 生成を保留できるスタブ。完了のタイミングをテストから握る。
class _GatedApiService extends Fake implements BackendApiService {
  int calls = 0;
  final _gate = Completer<void>();
  bool fail = false;

  void release() => _gate.complete();

  @override
  Future<List<QuizQuestion>> generateLearningQuiz(ThaiSentence sentence) async {
    calls++;
    await _gate.future;
    if (fail) throw Exception('boom');
    return const [_question];
  }

  @override
  Future<void> updateUvm({
    required List<Map<String, dynamic>> results,
    String? quizType,
  }) async {}
}

class _FakeDatabaseHelper extends Fake implements DatabaseHelper {
  @override
  Future<int> insertQuizResult(Map<String, dynamic> result) async => 1;

  @override
  Future<void> updateQuizStats({
    required int sessionCorrect,
    required int sessionTotal,
    required String quizDate,
  }) async {}

  @override
  Future<Map<String, dynamic>?> getCachedQuizStats() async => null;
}

void main() {
  late _GatedApiService api;
  late QuizController controller;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    api = _GatedApiService();
    controller = QuizController(
      api,
      FakeAnalyticsService(),
      () => lookupL10n(const Locale('ja')),
      databaseHelper: _FakeDatabaseHelper(),
    );
  });

  // サーバーは同じユーザーの生成をロックで直列化するので、2本同時に投げると
  // 片方が 409 で落ちてエラー画面になる（「1回目は必ず失敗、2回目で通る」）。
  test('事前生成の最中に開始しても、APIは1回しか呼ばない', () async {
    unawaited(controller.prepareQuiz(_sentence));
    expect(api.calls, 1);

    final started = controller.startLearningQuiz(_sentence);
    await Future<void>.delayed(Duration.zero);
    expect(controller.state, isA<QuizGenerating>());
    expect(api.calls, 1, reason: '事前生成を待たずに2本目を投げてはいけない');

    api.release();
    await started;

    expect(api.calls, 1);
    expect(controller.state, isA<QuizAnswering>());
  });

  test('事前生成が失敗したときだけ、その場で生成し直す', () async {
    api.fail = true;
    unawaited(controller.prepareQuiz(_sentence));
    final started = controller.startLearningQuiz(_sentence);
    api.release();
    await started;

    // 事前生成1本 + フォールバック1本。並行ではなく直列なのでロックに当たらない。
    expect(api.calls, 2);
  });
}
