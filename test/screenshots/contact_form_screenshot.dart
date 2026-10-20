// =============================================================================
// contact_form_screenshot.dart
// ご意見・お問い合わせ画面（ContactFormScreen）を Firebase なしで描画して
// PNG に書き出す。文言・レイアウト変更の見た目確認用。
//
//   flutter test test/screenshots/contact_form_screenshot.dart \
//     --dart-define=OUT=build/contact.png \
//     --dart-define=LANG=ja      # ja / en
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
import 'package:thai_memo/presentation/screens/contact_form_screen.dart';

const _fallbacks = ['NotoSans_regular', 'NotoSansJP'];
const _out = String.fromEnvironment('OUT', defaultValue: 'build/contact.png');
const _lang = String.fromEnvironment('LANG', defaultValue: 'ja');

void main() {
  testWidgets('ご意見・お問い合わせ画面を撮る', (tester) async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await _loadFonts();
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final t = buildAppLightTheme(ThaiFont.sarabun);
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: const Locale(_lang),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      theme: t.copyWith(
        textTheme: t.textTheme.apply(fontFamilyFallback: _fallbacks),
        appBarTheme: t.appBarTheme.copyWith(
            titleTextStyle: (t.appBarTheme.titleTextStyle ?? const TextStyle())
                .copyWith(fontFamilyFallback: _fallbacks)),
        filledButtonTheme: FilledButtonThemeData(
            style: t.filledButtonTheme.style?.copyWith(
                textStyle: WidgetStatePropertyAll(
                    (t.filledButtonTheme.style?.textStyle?.resolve({}) ??
                            const TextStyle())
                        .copyWith(fontFamilyFallback: _fallbacks)))),
      ),
      home: const RepaintBoundary(
          key: ValueKey('shot'), child: ContactFormScreen()),
    ));
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
