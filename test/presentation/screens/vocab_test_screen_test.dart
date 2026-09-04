import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thai_memo/data/datasources/backend_api_service.dart';
import 'package:thai_memo/data/models/vocab_test_step.dart';
import 'package:thai_memo/l10n/app_localizations.dart';
import 'package:thai_memo/presentation/providers/analytics_provider.dart';
import 'package:thai_memo/presentation/screens/vocab_test_screen.dart';

import '../../helpers/fake_firebase.dart';

/// 段を順に返す差し替え。回答は記録するだけで採点しない（採点はサーバー）。
class _FakeApi extends Fake implements BackendApiService {
  _FakeApi(this.steps, {this.error});

  final List<VocabTestStep> steps;
  Object? error;

  int calls = 0;
  int startCalls = 0;
  final List<List<int>> submitted = [];
  final List<int?> stages = [];

  VocabTestStep _next() {
    if (error != null) throw error!;
    final step = steps[calls.clamp(0, steps.length - 1)];
    calls++;
    return step;
  }

  @override
  Future<VocabTestStep> startVocabTest() async {
    startCalls++;
    return _next();
  }

  @override
  Future<VocabTestStep> submitVocabTest(List<int> answers, {int? stage}) async {
    submitted.add(answers);
    stages.add(stage);
    return _next();
  }
}

VocabTestStep _stage(int stage) => VocabTestStep(
      done: false,
      stage: stage,
      totalStages: 6,
      questions: List.generate(
        4,
        (i) => VocabTestQuestion(
          word: 'คำ$stage$i',
          choices: ['訳$stage${i}a', '訳$stage${i}b', '訳$stage${i}c', '訳$stage${i}d'],
        ),
      ),
    );

Widget _app(
  _FakeApi api, {
  bool mandatory = false,
  void Function(int? vocab)? onFinished,
}) {
  return ProviderScope(
    overrides: [
      analyticsServiceProvider.overrideWithValue(FakeAnalyticsService())
    ],
    child: MaterialApp(
      localizationsDelegates: const [
        L10n.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: L10n.supportedLocales,
      locale: const Locale('ja'),
      home: VocabTestScreen(
        source: 'test',
        mandatory: mandatory,
        onFinished: onFinished,
        api: api,
      ),
    ),
  );
}

Future<void> _start(WidgetTester tester) async {
  await tester.tap(find.text('はじめる'));
  await tester.pumpAndSettle();
}

/// 1段（4問）ぶん、先頭の選択肢を選ぶ。
Future<void> _answerStage(WidgetTester tester, int stage) async {
  for (var i = 0; i < 4; i++) {
    await tester.tap(find.text('訳$stage${i}a'));
    await tester.pumpAndSettle();
  }
}

void main() {
  testWidgets('1段で終わると4問だけ出して結果に着く', (tester) async {
    final api = _FakeApi([
      _stage(0),
      const VocabTestStep(done: true, vocab: 17, asked: 4),
    ]);
    await tester.pumpWidget(_app(api));
    await _start(tester);

    expect(find.text('1 / 4 問目'), findsOneWidget);
    await _answerStage(tester, 0);

    expect(find.text('約 17 語'), findsOneWidget);
    expect(api.submitted.single, [0, 0, 0, 0]);
  });

  testWidgets('通過すると次の段を続けて出す', (tester) async {
    final api = _FakeApi([
      _stage(0),
      _stage(1),
      const VocabTestStep(done: true, vocab: 150),
    ]);
    await tester.pumpWidget(_app(api));
    await _start(tester);
    await _answerStage(tester, 0);

    // 2段目の1問目に戻っている（進捗も振り出し）。
    expect(find.text('1 / 4 問目'), findsOneWidget);
    await _answerStage(tester, 1);
    expect(find.text('約 150 語'), findsOneWidget);
  });

  testWidgets('わからないは誤答（-1）として送る', (tester) async {
    final api = _FakeApi([
      _stage(0),
      const VocabTestStep(done: true, vocab: 0),
    ]);
    await tester.pumpWidget(_app(api));
    await _start(tester);
    for (var i = 0; i < 4; i++) {
      await tester.tap(find.text('わからない'));
      await tester.pumpAndSettle();
    }
    expect(api.submitted.single, [-1, -1, -1, -1]);
  });

  // プレミアム限定・1日3回・セッション切れ。送り直しても結果は変わらないので
  // 再試行は出さない（出すと 1日3回の枠を空振りで使わせることになる）。
  testWidgets('受けられない理由はそのまま出し、再試行は出さない', (tester) async {
    final api = _FakeApi(
      const [],
      error: VocabTestUnavailableException('語彙テストはプレミアム限定です'),
    );
    await tester.pumpWidget(_app(api));
    await _start(tester);

    expect(find.text('語彙テストはプレミアム限定です'), findsOneWidget);
    expect(find.text('やり直す'), findsNothing);
  });

  // 通信断で段の送信が落ちただけなら、最初からやり直さずその段を送り直す。
  // _start に戻すと 1日3回の枠が 1 つ減る。
  testWidgets('段の送信が失敗したら、同じ段の送信を再試行する', (tester) async {
    final api = _FakeApi([_stage(0), const VocabTestStep(done: true, vocab: 50)]);
    await tester.pumpWidget(_app(api));
    await _start(tester);

    api.error = BackendApiException('通信に失敗しました');
    for (var i = 0; i < 4; i++) {
      await tester.tap(find.text('わからない'));
      await tester.pumpAndSettle();
    }
    expect(find.text('やり直す'), findsOneWidget);
    expect(api.startCalls, 1);

    api.error = null;
    await tester.tap(find.text('やり直す'));
    await tester.pumpAndSettle();

    // 開始し直していない。送ったのは同じ段・同じ回答。
    expect(api.startCalls, 1);
    expect(api.submitted, [
      [-1, -1, -1, -1],
      [-1, -1, -1, -1],
    ]);
    expect(api.stages, [0, 0]);
  });

  testWidgets('free 上限に掛かる結果では注意書きを出す', (tester) async {
    final api = _FakeApi([
      const VocabTestStep(done: true, vocab: 300, freeCapped: true),
    ]);
    await tester.pumpWidget(_app(api));
    await _start(tester);

    expect(find.textContaining('100までに制限されます'), findsOneWidget);
  });

  testWidgets('オンボーディングでは逃げ道を出さない', (tester) async {
    final api = _FakeApi([_stage(0)]);
    await tester.pumpWidget(_app(api, mandatory: true));

    // 「あとで」も戻る矢印も出さない。測らないと先へ進めない。
    expect(find.text('あとで'), findsNothing);
    expect(find.byType(BackButton), findsNothing);
    expect(api.calls, 0);
  });

  // 選択肢4つ＋設問語は、小さい端末で文字サイズを上げると縦に入らない。
  // 非スクロールの Column だと RenderFlex overflow で赤縞が出る。
  testWidgets('小さい画面と大きい文字でも溢れない', (tester) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // MaterialApp が自前の MediaQuery を作るので、外から包んでも効かない。
    // 端末設定と同じ経路（PlatformDispatcher）で拡大する。
    tester.platformDispatcher.textScaleFactorTestValue = 1.8;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final api = _FakeApi([_stage(0)]);
    await tester.pumpWidget(_app(api));

    // イントロも Spacer で組んであるので、まずここで溢れないこと。
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('はじめる'));
    await tester.tap(find.text('はじめる'));
    await tester.pumpAndSettle();

    // 設問画面。選択肢4つ＋「わからない」まで、スクロールすれば全部届く。
    expect(tester.takeException(), isNull);
    expect(find.text('訳00a'), findsOneWidget);
    await tester.ensureVisible(find.text('わからない'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('AppBar の戻るで抜けられる', (tester) async {
    final api = _FakeApi([_stage(0)]);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          analyticsServiceProvider.overrideWithValue(FakeAnalyticsService())
        ],
        child: MaterialApp(
          localizationsDelegates: const [
            L10n.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: L10n.supportedLocales,
          locale: const Locale('ja'),
          // 押した先があること（＝戻る矢印が出ること）を作る。
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () => Navigator.push<void>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => VocabTestScreen(source: 'test', api: api),
                  ),
                ),
                child: const Text('開く'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('開く'));
    await tester.pumpAndSettle();
    expect(find.text('はじめる'), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(find.text('はじめる'), findsNothing);
    expect(find.text('開く'), findsOneWidget);
  });
}
