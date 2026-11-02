// =============================================================================
// notify_schedule_screenshot.dart
// 通知時刻の設定画面（NotificationScheduleScreen）を Firebase なしで描画して
// PNG に書き出す。X 告知・見た目確認用。`_test.dart` ではないので通常の
// `flutter test` では走らない。
//
//   flutter test test/screenshots/notify_schedule_screenshot.dart \
//     --dart-define=OUT=build/notify_schedule.png \
//     --dart-define=PLAN=premium   # premium / free
//     --dart-define=LANG=ja        # ja / en
//
// 日本語フォントは tools/store_screenshots/fetch_fonts.sh で取得しておく。
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
import 'package:thai_memo/core/notify_slots.dart';
import 'package:thai_memo/core/theme/app_theme.dart';
import 'package:thai_memo/l10n/app_localizations.dart';
import 'package:thai_memo/presentation/providers/remaining_quota_provider.dart';
import 'package:thai_memo/presentation/providers/settings_provider.dart';
import 'package:thai_memo/presentation/screens/notification_schedule_screen.dart';

const _fallbacks = ['NotoSans_regular', 'NotoSansJP'];
const _out =
    String.fromEnvironment('OUT', defaultValue: 'build/notify_schedule.png');
const _plan = String.fromEnvironment('PLAN', defaultValue: 'premium');
const _lang = String.fromEnvironment('LANG', defaultValue: 'ja');

void main() {
  testWidgets('通知時刻の設定画面を撮る', (tester) async {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
    await _loadFonts();
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    tester.view.physicalSize = const Size(390 * 3, 520 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final premium = _plan == 'premium';
    await tester.pumpWidget(ProviderScope(
      overrides: [
        effectivePremiumProvider.overrideWithValue(premium),
        settingsControllerProvider.overrideWith((ref) => _Settings(premium)),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: const Locale(_lang),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        theme: _withFallbacks(buildAppLightTheme(ThaiFont.sarabun)),
        home: const RepaintBoundary(
            key: ValueKey('shot'), child: NotificationScheduleScreen()),
      ),
    ));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));

    final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('shot')));
    final bytes = await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 3);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data!.buffer.asUint8List();
    });
    File(_out)
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(bytes!);
    // ignore: avoid_print
    print('WROTE $_out');
    debugDefaultTargetPlatformOverride = null;
  });
}

class _Settings extends StateNotifier<SettingsState>
    implements SettingsController {
  _Settings(bool premium)
      : super(SettingsState.initial().copyWith(
          isFirstLaunch: false,
          dailyReminderEnabled: true,
          notifySlots: premium
              ? const [NotifySlot(7), NotifySlot(12), NotifySlot(21)]
              : const [NotifySlot(8)],
        ));

  @override
  Future<void> syncNotifySlotsPlan({required bool premium}) async {}

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// 日本語グリフを持たないフォントで豆腐にならないよう、フォールバックを足す。
ThemeData _withFallbacks(ThemeData t) {
  TextStyle fb(TextStyle? s) =>
      (s ?? const TextStyle()).copyWith(fontFamilyFallback: _fallbacks);
  return t.copyWith(
    textTheme: t.textTheme.apply(fontFamilyFallback: _fallbacks),
    primaryTextTheme: t.primaryTextTheme.apply(fontFamilyFallback: _fallbacks),
    appBarTheme: t.appBarTheme
        .copyWith(titleTextStyle: fb(t.appBarTheme.titleTextStyle)),
  );
}

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
