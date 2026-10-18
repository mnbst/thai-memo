// =============================================================================
// settings_screenshot.dart
// 設定画面（SettingsScreen）を Firebase なしで描画して PNG に書き出す。
// 文言・レイアウト変更の見た目確認用。`_test.dart` ではないので通常の
// `flutter test` では走らない。
//
//   flutter test test/screenshots/settings_screenshot.dart \
//     --dart-define=OUT=build/settings.png \
//     --dart-define=PLAN=trial   # trial / free / premium
//     --dart-define=LANG=ja      # ja / en
//     --dart-define=H=2400       # 論理高さ。大きくすると全項目を1枚に収める
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
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thai_memo/core/theme/app_theme.dart';
import 'package:thai_memo/l10n/app_localizations.dart';
import 'package:thai_memo/presentation/providers/analytics_provider.dart';
import 'package:thai_memo/presentation/providers/auth_provider.dart';
import 'package:thai_memo/presentation/providers/leaderboard_provider.dart';
import 'package:thai_memo/presentation/providers/remaining_quota_provider.dart';
import 'package:thai_memo/presentation/providers/settings_provider.dart';
import 'package:thai_memo/presentation/providers/streak_provider.dart';
import 'package:thai_memo/presentation/providers/vocab_stats_provider.dart';
import 'package:thai_memo/presentation/screens/settings_screen.dart';
import 'package:thai_memo/services/analytics_service.dart';
import 'package:thai_memo/services/firebase_auth_service.dart';

const _fallbacks = ['NotoSans_regular', 'NotoSansJP'];
const _out = String.fromEnvironment('OUT', defaultValue: 'build/settings.png');
const _plan = String.fromEnvironment('PLAN', defaultValue: 'trial');
const _lang = String.fromEnvironment('LANG', defaultValue: 'ja');

void main() {
  testWidgets('設定画面を撮る', (tester) async {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
        appName: 'x',
        packageName: 'x',
        version: '1.4.22',
        buildNumber: '1',
        buildSignature: '');
    await _loadFonts();
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    const h = int.fromEnvironment('H', defaultValue: 844);
    tester.view.physicalSize = const Size(390 * 3, h * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final now = DateTime.now();
    final plan = PlanStatus.values.byName(_plan);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        analyticsServiceProvider.overrideWithValue(_Noop()),
        planStatusProvider.overrideWithValue(AsyncValue.data(plan)),
        effectivePremiumProvider.overrideWithValue(plan != PlanStatus.free),
        userDocSnapshotProvider.overrideWith((ref) => Stream.value(
            UserDocSnapshot(
                data: {'premium_trial_expires_at': null}, isFromCache: false))),
        lifetimeMigrationOfferedProvider.overrideWith((ref) async => false),
        myNicknameProvider.overrideWith((ref) => Stream.value('ソムチャイ')),
        vocabStatsProvider.overrideWith(
            (ref) => Stream.value(const VocabStats(estimatedVocab: 320))),
        authControllerProvider.overrideWith((ref) => AuthController(
            _Auth(), () => lookupL10n(const Locale(_lang)),
            clearLocalData: () async {})),
        settingsControllerProvider.overrideWith((ref) => _Settings()),
        streakProvider.overrideWith((ref) => _Streak(StreakSummary.compute([
              for (var i = 0; i < 5; i++)
                now
                    .subtract(Duration(days: i))
                    .toIso8601String()
                    .substring(0, 10)
            ], now))),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: const Locale(_lang),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        theme: _withFallbacks(buildAppLightTheme(ThaiFont.sarabun)),
        home: const RepaintBoundary(
            key: ValueKey('shot'), child: SettingsScreen()),
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

class _Noop extends Fake implements AnalyticsService {
  @override
  dynamic noSuchMethod(Invocation i) => Future<void>.value();
}

class _Auth extends Fake implements FirebaseAuthService {
  @override
  String? get displayName => 'Taro';
  @override
  String? get email => 'taro@example.com';
  @override
  bool get isLinkedAccount => true;
}

class _Settings extends StateNotifier<SettingsState>
    implements SettingsController {
  _Settings() : super(SettingsState.initial().copyWith(isFirstLaunch: false));
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Streak extends StateNotifier<StreakSummary> implements StreakController {
  _Streak(super.s);
  @override
  dynamic noSuchMethod(Invocation i) => Future<void>.value();
}

/// 日本語グリフを持たないフォントで豆腐にならないよう、フォールバックを足す。
/// ボタンはテーマの textStyle がフォント指定なしで上書きするので個別に足す。
ThemeData _withFallbacks(ThemeData t) {
  TextStyle fb(TextStyle? s) =>
      (s ?? const TextStyle()).copyWith(fontFamilyFallback: _fallbacks);
  ButtonStyle? btn(ButtonStyle? s) => s?.copyWith(
        textStyle: WidgetStatePropertyAll(fb(s.textStyle?.resolve({}))),
      );
  return t.copyWith(
    textTheme: t.textTheme.apply(fontFamilyFallback: _fallbacks),
    primaryTextTheme: t.primaryTextTheme.apply(fontFamilyFallback: _fallbacks),
    appBarTheme: t.appBarTheme
        .copyWith(titleTextStyle: fb(t.appBarTheme.titleTextStyle)),
    textButtonTheme: TextButtonThemeData(style: btn(t.textButtonTheme.style)),
    elevatedButtonTheme:
        ElevatedButtonThemeData(style: btn(t.elevatedButtonTheme.style)),
    outlinedButtonTheme:
        OutlinedButtonThemeData(style: btn(t.outlinedButtonTheme.style)),
    filledButtonTheme:
        FilledButtonThemeData(style: btn(t.filledButtonTheme.style)),
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
