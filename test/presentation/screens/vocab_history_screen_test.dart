import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thai_memo/core/config/app_config.dart';
import 'package:thai_memo/data/models/vocab_word.dart';
import 'package:thai_memo/l10n/app_localizations.dart';
import 'package:thai_memo/presentation/providers/remaining_quota_provider.dart';
import 'package:thai_memo/presentation/providers/vocab_progress_provider.dart';
import 'package:thai_memo/presentation/providers/vocab_stats_provider.dart';
import 'package:thai_memo/presentation/screens/vocab_history_screen.dart';
import 'package:thai_memo/presentation/widgets/vocab_guide_card.dart';

Future<void> _pump(
  WidgetTester tester, {
  List<VocabEntry> entries = const [],
  int score = 0,
  bool premium = false,
}) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      effectivePremiumProvider.overrideWithValue(premium),
      vocabEntriesProvider.overrideWith((ref) async => entries),
      vocabStatsProvider.overrideWith(
        (ref) => Stream.value(VocabStats(estimatedVocab: score)),
      ),
    ],
    child: MaterialApp(
      locale: const Locale('ja'),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: const VocabHistoryScreen(),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  group('出題範囲の貼り付け', () {
    // 500, 495, … 5 語。スコア 300 の範囲は 250〜308。
    final entries = [
      for (var i = 0; i < 100; i++)
        VocabEntry(
          progress: VocabWord(
            word: 'w$i',
            rank: 500 - i * 5,
            p: 0.4,
            answered: false,
          ),
        ),
    ];

    Future<void> open(WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({
        AppConfig.prefKeyVocabGuideDismissed: true,
      });
      await _pump(tester, entries: entries, score: 300, premium: true);
    }

    double topOf(WidgetTester tester, Finder icon) =>
        tester.getTopLeft(icon).dy - tester.getTopLeft(find.byType(ListView)).dy;

    testWidgets('範囲の中では下向きを上端に貼る', (tester) async {
      await open(tester);
      await tester.drag(find.byType(ListView), const Offset(0, -200));
      await tester.pumpAndSettle();
      final down = find.byIcon(Icons.arrow_downward);
      expect(down, findsOneWidget);
      expect(topOf(tester, down), lessThan(30));
    });

    testWidgets('範囲の中では上向きを一覧の一番下で止める', (tester) async {
      // 開いた直後は範囲の中で、下端の区切りはまだ一覧の外にある。
      await open(tester);
      final up = find.byIcon(Icons.arrow_upward).hitTestable();
      expect(up, findsOneWidget);
      final listBottom = tester.getBottomLeft(find.byType(ListView)).dy;
      expect((listBottom - tester.getBottomLeft(up).dy).abs(), lessThan(30));
    });

    testWidgets('範囲より上では上向きを止めない', (tester) async {
      await open(tester);
      await tester.drag(find.byType(ListView), const Offset(0, 5000));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.arrow_upward).hitTestable(), findsNothing);
    });

    testWidgets('範囲を過ぎたら上向きだけを上端に貼る', (tester) async {
      await open(tester);
      await tester.drag(find.byType(ListView), const Offset(0, -2500));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.arrow_downward), findsNothing);
      final up = find.byIcon(Icons.arrow_upward);
      expect(up, findsOneWidget);
      expect(topOf(tester, up), lessThan(30));
    });
  });

  testWidgets('閉じた記録が無ければ案内を出す', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await _pump(tester);
    expect(find.byType(VocabGuideCard), findsOneWidget);
  });

  testWidgets('閉じた記録があれば案内を出さない', (tester) async {
    SharedPreferences.setMockInitialValues({
      AppConfig.prefKeyVocabGuideDismissed: true,
    });
    await _pump(tester);
    expect(find.byType(VocabGuideCard), findsNothing);
  });
}
