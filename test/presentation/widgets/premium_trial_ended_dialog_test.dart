import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thai_memo/l10n/app_localizations.dart';
import 'package:thai_memo/presentation/providers/vocab_stats_provider.dart';
import 'package:thai_memo/presentation/widgets/premium_trial_ended_dialog.dart';

Future<void> _pump(WidgetTester tester, VocabStats stats) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        vocabStatsProvider.overrideWith((ref) => Stream.value(stats)),
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
        home: const Scaffold(body: PremiumTrialEndedDialog()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  // 語彙の行が増えて表が横に伸びた。狭い画面・大きい文字でも溢れないこと。
  testWidgets('狭い幅でも表が溢れない', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await _pump(tester, const VocabStats(estimatedVocab: 100, testedVocab: 400));

    expect(tester.takeException(), isNull);
    expect(find.text('語彙スコア'), findsOneWidget);
  });

  testWidgets('測った語彙が上限を超えていれば語彙の行を出す', (tester) async {
    await _pump(tester, const VocabStats(estimatedVocab: 100, testedVocab: 400));

    expect(find.text('語彙スコア'), findsOneWidget);
    expect(find.text('上限なし'), findsOneWidget);
    expect(find.text('100語まで'), findsOneWidget);
  });

  testWidgets('上限に届いていなければ語彙の行は出さない', (tester) async {
    await _pump(tester, const VocabStats(estimatedVocab: 80, testedVocab: 80));

    expect(find.text('語彙スコア'), findsNothing);
    // 例文の回数は常に出る（行が消えていないことの確認）。
    expect(find.text('例文'), findsOneWidget);
  });

  testWidgets('未測定なら estimated_vocab で判断する', (tester) async {
    await _pump(tester, const VocabStats(estimatedVocab: 250));

    expect(find.text('語彙スコア'), findsOneWidget);
  });
}
