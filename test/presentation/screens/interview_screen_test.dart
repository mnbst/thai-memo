import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thai_memo/core/config/app_config.dart';
import 'package:thai_memo/l10n/app_localizations.dart';
import 'package:thai_memo/presentation/providers/analytics_provider.dart';
import 'package:thai_memo/presentation/screens/interview_screen.dart';

import '../../helpers/fake_firebase.dart';

Widget _app({
  required VoidCallback onComplete,
  required FakeAnalyticsService analytics,
}) {
  return ProviderScope(
    overrides: [analyticsServiceProvider.overrideWithValue(analytics)],
    child: MaterialApp(
      localizationsDelegates: const [
        L10n.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: L10n.supportedLocales,
      locale: const Locale('ja'),
      home: InterviewScreen(onComplete: onComplete),
    ),
  );
}

/// 前置きを読み終えて設問へ入る。
Future<void> _enterQuestions(WidgetTester tester) async {
  await tester.tap(find.text('はじめる'));
  await tester.pumpAndSettle();
}

/// 選択肢をタップして次の設問へ送る。
Future<void> _answer(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('回答すると応答を挟まず次の設問へ進む', (tester) async {
    final analytics = FakeAnalyticsService();
    await tester.pumpWidget(_app(onComplete: () {}, analytics: analytics));

    // 前置きを挟んでから設問に入る。
    expect(find.text('4つ質問させてください'), findsOneWidget);
    await _enterQuestions(tester);

    expect(find.text('1 / 4'), findsOneWidget);
    await _answer(tester, 'まったく初めて');

    // 途中に読み物を挟まない。次の設問がそのまま出る。
    expect(find.text('タイ語を使いたいのはどんな場面ですか？'), findsOneWidget);
    expect(find.text('2 / 4'), findsOneWidget);
    expect(find.text('次へ'), findsNothing);
  });

  testWidgets('4問に答えると回答に沿った考え方が出る', (tester) async {
    var completed = false;
    final analytics = FakeAnalyticsService();
    await tester.pumpWidget(
      _app(onComplete: () => completed = true, analytics: analytics),
    );

    await _enterQuestions(tester);
    expect(find.text('タイ語はどのくらい学んでいますか？'), findsOneWidget);

    await _answer(tester, 'まったく初めて');
    await _answer(tester, '旅行で使いたい');
    await _answer(tester, '数分だけ');
    await _answer(tester, '文字が読めない');

    // 箇条書き4点。学習段階・例文の作り・つまずきの越え方・取れる時間。
    expect(find.textContaining('なんとなくの形から'), findsOneWidget);
    expect(find.textContaining('中心になる単語が1つ'), findsOneWidget);
    expect(find.textContaining('つづりで声調が決まります'), findsOneWidget);
    // 「数分だけ」と答えたので、数分で何ができるかを返す。
    expect(find.textContaining('数分あれば'), findsOneWidget);
    // 見出しは置かない。要約だけ読んでも何も伝わらないため。
    expect(find.text('今日の1文から'), findsNothing);
    expect(find.text('つまずきは仕組みで越える'), findsNothing);
    // 「旅行で使いたい」と答えたので、テーマ選択の案内を返す。
    expect(find.textContaining('「旅行」や「交通」'), findsOneWidget);
    // 語彙推定の締め文はここに出さない（冗長になるため）。
    expect(find.textContaining('次の例文の難しさを調整'), findsNothing);
    // 強調マーカーは描画されない（パースされて色と太さになる）。
    expect(find.textContaining('**'), findsNothing);

    await tester.tap(find.text('実際に使ってみる'));
    await tester.pumpAndSettle();
    expect(completed, isTrue);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('${AppConfig.prefKeyInterviewPrefix}level'), 'none');
    expect(
      prefs.getString('${AppConfig.prefKeyInterviewPrefix}struggle'),
      'script',
    );
    expect(
      analytics.interviewEvents.map((e) => e['action']),
      containsAllInOrder(['start', 'answer', 'answer', 'answer', 'answer', 'complete']),
    );
  });

  testWidgets('考え方は上から1項目ずつ現れる', (tester) async {
    await tester.pumpWidget(_app(onComplete: () {}, analytics: FakeAnalyticsService()));
    await _enterQuestions(tester);
    await _answer(tester, 'まったく初めて');
    await _answer(tester, '旅行で使いたい');
    await _answer(tester, '数分だけ');
    // 最後の回答は settle しない（考え方の出現アニメーションを見るため）。
    await tester.tap(find.text('文字が読めない'));
    await tester.pump();

    double opacityOf(int index) => tester
        .widget<FadeTransition>(find.byKey(ValueKey('philosophy_stagger_$index')))
        .opacity
        .value;

    // 出始めは見出し（0番）だけ。最後の項目（5番）とボタン（6番）はまだ。
    await tester.pump(const Duration(milliseconds: 380));
    expect(opacityOf(0), greaterThan(0.9));
    expect(opacityOf(5), lessThan(0.1));
    expect(opacityOf(6), lessThan(0.1));

    await tester.pumpAndSettle();
    expect(opacityOf(5), 1);
    expect(opacityOf(6), 1);
  });

  testWidgets('スキップは置かない（4問とも答える）', (tester) async {
    final analytics = FakeAnalyticsService();
    await tester.pumpWidget(_app(onComplete: () {}, analytics: analytics));
    await _enterQuestions(tester);

    expect(find.text('スキップ'), findsNothing);
  });
}
