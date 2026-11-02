// =============================================================================
// streak_burst_mock_app.dart
// 連続日数が伸びたときの炎の演出を、日数を選んで何度でも出せるモック（Firebase なし）。
//
//   flutter run -t test/screenshots/streak_burst_mock_app.dart
//
// 下のボタンで「◯日目になった」演出を出す。右上のチップも本物と同じく切り替わる。
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:thai_memo/core/theme/app_theme.dart';
import 'package:thai_memo/l10n/app_localizations.dart';
import 'package:thai_memo/presentation/providers/settings_provider.dart';
import 'package:thai_memo/presentation/providers/streak_provider.dart';
import 'package:thai_memo/presentation/widgets/streak_widgets.dart';

const _days = [1, 2, 3, 6, 7, 13, 14, 29, 30, 50, 100, 200];

void main() => runApp(ProviderScope(
      overrides: [streakProvider.overrideWith((ref) => _Streak())],
      child: const _MockApp(),
    ));

class _MockApp extends StatelessWidget {
  const _MockApp();

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: const Locale('ja'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        theme: buildAppLightTheme(ThaiFont.sarabun),
        home: const _Screen(),
      );
}

class _Screen extends ConsumerWidget {
  const _Screen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('今日の例文'),
        actions: const [StreakChip(), SizedBox(width: 16)],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('วันนี้อากาศดีมาก', style: theme.textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  Text('今日はとても天気がいい', style: theme.textTheme.bodyLarge),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text('◯日目になった演出を出す', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final d in _days)
                FilledButton.tonal(
                  onPressed: () {
                    // 前日までの状態にしてから伸ばす（本物と同じ順）。
                    final n = ref.read(streakProvider.notifier) as _Streak;
                    n.set(d);
                    ref.read(streakCelebrationProvider.notifier).state++;
                  },
                  child: Text('$d日'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Streak extends StateNotifier<StreakSummary> implements StreakController {
  _Streak() : super(_summary(0));

  static StreakSummary _summary(int days) {
    final now = DateTime.now();
    return StreakSummary.compute([
      for (var i = 0; i < days; i++)
        streakDateKey(now.subtract(Duration(days: i)))
    ], now);
  }

  void set(int days) => state = _summary(days);

  @override
  dynamic noSuchMethod(Invocation i) => Future<void>.value();
}
