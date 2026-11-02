// =============================================================================
// streak_burst_screenshot.dart
// 連続日数が伸びたときの演出（中央の炎カード）を、日数ごとに静止画で書き出す。
// `_test.dart` ではないので通常の `flutter test` では走らない。
//
//   flutter test test/screenshots/streak_burst_screenshot.dart \
//     --dart-define=OUT=build/streak_burst
//
// 出力: <OUT>/streak_<日数>.png（演出が出きったところ）
// 絵文字のフォントは読み込まないので、ほめ言葉の絵文字は豆腐になる。
// =============================================================================

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thai_memo/core/theme/app_theme.dart';
import 'package:thai_memo/l10n/app_localizations.dart';
import 'package:thai_memo/presentation/providers/settings_provider.dart';
import 'package:thai_memo/presentation/providers/streak_provider.dart';
import 'package:thai_memo/presentation/widgets/streak_widgets.dart';

const _fallbacks = ['NotoSans_regular', 'NotoSansJP'];
const _out = String.fromEnvironment('OUT', defaultValue: 'build/streak_burst');
const _days = [3, 7, 14, 30, 100];

void main() {
  for (final days in _days) {
    testWidgets('連続$days日の演出を撮る', (tester) async {
      GoogleFonts.config.allowRuntimeFetching = false;
      SharedPreferences.setMockInitialValues({});
      await _loadFonts();
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      final now = DateTime.now();
      final container = ProviderContainer(overrides: [
        streakProvider.overrideWith((ref) => _Streak(StreakSummary.compute([
              for (var i = 0; i < days; i++)
                streakDateKey(now.subtract(Duration(days: i)))
            ], now))),
      ]);
      addTearDown(container.dispose);

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          locale: const Locale('ja'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          theme: _withFallbacks(buildAppLightTheme(ThaiFont.sarabun)),
          builder: (context, child) =>
              RepaintBoundary(key: const ValueKey('shot'), child: child),
          home: const _Screen(),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 300));

      container.read(streakCelebrationProvider.notifier).state++;
      await tester.pump();
      // 弾み（最初の 0.25 = 650ms）が収まり、まだ消え始める前。
      await tester.pump(const Duration(milliseconds: 1200));

      final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('shot')));
      final bytes = await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 3);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        return data!.buffer.asUint8List();
      });
      final path = '$_out/streak_$days.png';
      File(path)
        ..parent.createSync(recursive: true)
        ..writeAsBytesSync(bytes!);
      // ignore: avoid_print
      print('WROTE $path');

      // 残りのタイマーを流しきる。
      await tester.pump(const Duration(seconds: 3));
      debugDefaultTargetPlatformOverride = null;
    });
  }
}

/// 学習画面のヘッダーに似せた背景。
class _Screen extends StatelessWidget {
  const _Screen();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('今日の例文'),
        actions: const [StreakChip(), SizedBox(width: 16)],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Card(
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
      ),
    );
  }
}

class _Streak extends StateNotifier<StreakSummary> implements StreakController {
  _Streak(super.s);
  @override
  dynamic noSuchMethod(Invocation i) => Future<void>.value();
}

ThemeData _withFallbacks(ThemeData t) => t.copyWith(
      textTheme: t.textTheme.apply(fontFamilyFallback: _fallbacks),
      appBarTheme: t.appBarTheme.copyWith(
          titleTextStyle: (t.appBarTheme.titleTextStyle ?? const TextStyle())
              .copyWith(fontFamilyFallback: _fallbacks)),
    );

Future<void> _loadFonts() async {
  Future<void> load(String family, String path) async {
    final f = File(path);
    if (!f.existsSync()) return;
    await (FontLoader(family)
          ..addFont(Future.value(ByteData.sublistView(f.readAsBytesSync()))))
        .load();
  }

  const w = {
    'Regular': 'regular',
    'Medium': '500',
    'SemiBold': '600',
    'Bold': '700'
  };
  for (final e in w.entries) {
    await load('Sarabun_${e.value}', 'google_fonts/Sarabun-${e.key}.ttf');
    await load('NotoSans_${e.value}', 'google_fonts/NotoSans-${e.key}.ttf');
  }
  await load('MaterialIcons',
      '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  await load('NotoSansJP', 'tools/x_post/fonts/NotoSansJP-Regular.otf');
}
