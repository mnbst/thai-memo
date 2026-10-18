// =============================================================================
// guide_screenshot.dart
// 読み物のガイド画面（発音・語順・声調）を PNG に書き出す見た目確認用モック。
// `_test.dart` ではないので通常の `flutter test` では走らない。
//
//   flutter test test/screenshots/guide_screenshot.dart \
//     --dart-define=SCREEN=pron  # pron / word_order / tone
//     --dart-define=OUT=build/guide.png \
//     --dart-define=LANG=ja      # ja / en
//     --dart-define=H=4000       # 論理高さ。大きくすると全体を1枚に収める
//
// 日本語フォントは tools/store_screenshots/fetch_fonts.sh で取得しておく。
// =============================================================================

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:thai_memo/core/theme/app_theme.dart';
import 'package:thai_memo/l10n/app_localizations.dart';
import 'package:thai_memo/presentation/providers/settings_provider.dart';
import 'package:thai_memo/presentation/screens/pronunciation_guide_screen.dart';
import 'package:thai_memo/presentation/screens/tone_guide_screen.dart';
import 'package:thai_memo/presentation/screens/word_order_guide_screen.dart';

const _fallbacks = ['NotoSans_regular', 'NotoSansJP'];
const _screen = String.fromEnvironment('SCREEN', defaultValue: 'pron');
const _out = String.fromEnvironment('OUT', defaultValue: 'build/guide.png');
const _lang = String.fromEnvironment('LANG', defaultValue: 'ja');

const _screens = <String, Widget>{
  'pron': PronunciationGuideScreen(),
  'word_order': WordOrderGuideScreen(),
  'tone': ToneGuideScreen(),
};

void main() {
  testWidgets('ガイド画面を撮る', (tester) async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await _loadFonts();
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    const h = int.fromEnvironment('H', defaultValue: 844);
    tester.view.physicalSize = const Size(390 * 3, h * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: const Locale(_lang),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      theme: _withFallbacks(buildAppLightTheme(ThaiFont.sarabun)),
      // 実機と同じく設定画面などから push した形にして、戻るボタンを出す。
      builder: (context, child) =>
          RepaintBoundary(key: const ValueKey('shot'), child: child),
      home: const Scaffold(),
    ));
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.push(MaterialPageRoute<void>(builder: (_) => _screens[_screen]!));
    await tester.pumpAndSettle();
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
