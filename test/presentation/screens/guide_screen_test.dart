import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thai_memo/l10n/app_localizations.dart';
import 'package:thai_memo/presentation/providers/analytics_provider.dart';
import 'package:thai_memo/presentation/screens/guide_screen.dart';

import '../../helpers/fake_firebase.dart';

Widget _host({
  required bool isFirstLaunch,
  VoidCallback? onDone,
  Locale locale = const Locale('ja'),
}) {
  return ProviderScope(
    overrides: [
      analyticsServiceProvider.overrideWithValue(FakeAnalyticsService())
    ],
    child: MaterialApp(
      // 実行環境のロケールに引きずられないよう明示する。
      locale: locale,
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: GuideScreen(isFirstLaunch: isFirstLaunch, onDone: onDone),
    ),
  );
}

void main() {
  testWidgets('章は 概要 → 役割 → 操作 の順に並び、図も描かれる', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_host(isFirstLaunch: false));
    await tester.pumpAndSettle();

    expect(find.text('概要'), findsOneWidget);
    expect(find.text('それぞれの機能の役割'), findsOneWidget);

    // 概要の図（学習のくり返し）は先頭の章に出る。
    expect(find.text('まとめクイズ'), findsWidgets);

    await tester.scrollUntilVisible(find.text('操作のしかた'), 400);
    expect(find.text('操作のしかた'), findsOneWidget);

    // 例文カードの図・判定の色の図まで描けている。
    await tester.scrollUntilVisible(find.text('タイ文字'), 400);
    await tester.scrollUntilVisible(find.text('惜しい'), 400);
    expect(tester.takeException(), isNull);
  });

  testWidgets('初回はスキップと「はじめる」で閉じられる', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var done = 0;

    await tester.pumpWidget(
      _host(isFirstLaunch: true, onDone: () => done += 1),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('スキップ'));
    await tester.pump();
    expect(done, 1);

    await tester.scrollUntilVisible(find.text('はじめる'), 400);
    await tester.tap(find.text('はじめる'));
    await tester.pump();
    expect(done, 2);
  });

  testWidgets('設定から開いた場合はスキップを出さない', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_host(isFirstLaunch: false));
    await tester.pumpAndSettle();

    expect(find.text('スキップ'), findsNothing);
  });

  testWidgets('英語の図に英語訳と正しい操作案内が出る', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 3000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _host(isFirstLaunch: false, locale: const Locale('en')),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('I like coffee.'), 400);
    expect(find.text('I like coffee.'), findsOneWidget);
    expect(find.text('私はコーヒーが好きです'), findsNothing);

    await tester.scrollUntilVisible(find.textContaining('Hold to speak'), 400);
    expect(
      find.textContaining('tap “Practice,” then hold “Hold to speak”'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
