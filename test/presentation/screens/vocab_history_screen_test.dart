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

Future<void> _pump(WidgetTester tester) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      effectivePremiumProvider.overrideWithValue(false),
      vocabEntriesProvider.overrideWith((ref) async => const <VocabEntry>[]),
      vocabStatsProvider.overrideWith((ref) => Stream.value(const VocabStats())),
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
