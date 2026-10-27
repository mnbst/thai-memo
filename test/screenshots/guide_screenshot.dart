// =============================================================================
// guide_screenshot.dart
// 読み物のガイド画面（タイ文字・発音・語順・声調）を PNG に書き出す見た目確認用モック。
// `_test.dart` ではないので通常の `flutter test` では走らない。
//
//   flutter test test/screenshots/guide_screenshot.dart \
//     --dart-define=SCREEN=script  # script / pron / word_order / tone
//     --dart-define=OUT=build/guide.png \
//     --dart-define=LANG=ja      # ja / en
//     --dart-define=H=4000       # 論理高さ。大きくすると全体を1枚に収める
//     --dart-define=FROM=5つの声調  # 指定すると、この見出しを含む欄（Card）だけを切り出す
//     --dart-define=TO=子音クラス    # 指定すると、FROM の見出しからこの見出しの手前まで
//
// FROM/TO は X 投稿（tools/x_post/pick_study_post.py）がガイドの1欄を貼るのに使う。
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
import 'package:thai_memo/core/theme/app_theme.dart';
import 'package:thai_memo/l10n/app_localizations.dart';
import 'package:thai_memo/presentation/providers/settings_provider.dart';
import 'package:thai_memo/presentation/screens/pronunciation_guide_screen.dart';
import 'package:thai_memo/presentation/screens/thai_script_guide_screen.dart';
import 'package:thai_memo/presentation/screens/tone_guide_screen.dart';
import 'package:thai_memo/presentation/screens/word_order_guide_screen.dart';

const _fallbacks = ['NotoSans_regular', 'NotoSansJP'];
const _screen = String.fromEnvironment('SCREEN', defaultValue: 'pron');
const _out = String.fromEnvironment('OUT', defaultValue: 'build/guide.png');
const _lang = String.fromEnvironment('LANG', defaultValue: 'ja');
const _from = String.fromEnvironment('FROM');
const _to = String.fromEnvironment('TO');
// 切り出す欄の上下に残す余白（論理px）。
const _margin = 6.0;

const _screens = <String, Widget>{
  'script': ThaiScriptGuideScreen(),
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

    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: const Locale(_lang),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      theme: _withFallbacks(buildAppLightTheme(ThaiFont.sarabun)),
      // 実機と同じく設定画面などから push した形にして、戻るボタンを出す。
      builder: (context, child) =>
          RepaintBoundary(key: const ValueKey('shot'), child: child),
      home: const Scaffold(),
    )));
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.push(MaterialPageRoute<void>(builder: (_) => _screens[_screen]!));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));

    final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('shot')));
    final crop = _from.isEmpty ? null : _sectionRect(tester, h.toDouble());
    final bytes = await tester.runAsync(() async {
      var image = await boundary.toImage(pixelRatio: 3);
      if (crop != null) image = await _crop(image, crop, 3);
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

/// FROM の見出しを含む欄（Card）の範囲。TO を渡したときは、FROM の見出しから
/// TO の見出しの手前までにする（複数の欄をまとめて切り出すとき）。
Rect _sectionRect(WidgetTester tester, double height) {
  // 見出しは本文にも同じ語が出るので、完全一致を先に探す。
  Finder heading(String text) {
    final exact = find.text(text, findRichText: true);
    return (exact.evaluate().isNotEmpty
            ? exact
            : find.textContaining(text, findRichText: true))
        .first;
  }

  final Rect rect;
  if (_to.isEmpty) {
    final card =
        find.ancestor(of: heading(_from), matching: find.byType(Card)).first;
    rect = tester.getRect(card).inflate(_margin);
  } else {
    rect = Rect.fromLTRB(0, tester.getTopLeft(heading(_from)).dy - _margin, 390,
        tester.getTopLeft(heading(_to)).dy - _margin);
  }
  if (rect.bottom <= rect.top || rect.bottom > height) {
    throw StateError('欄の範囲がおかしい: $_from〜$_to ($rect / H=$height)');
  }
  return Rect.fromLTRB(0, rect.top.clamp(0, height), 390, rect.bottom);
}

Future<ui.Image> _crop(ui.Image image, Rect rect, double ratio) {
  final src = Rect.fromLTRB(rect.left * ratio, rect.top * ratio,
      rect.right * ratio, rect.bottom * ratio);
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawImageRect(image, src, Offset.zero & src.size,
      Paint()..filterQuality = FilterQuality.high);
  return recorder.endRecording().toImage(src.width.round(), src.height.round());
}

ThemeData _withFallbacks(ThemeData t) {
  TextStyle fb(TextStyle? s) =>
      (s ?? const TextStyle()).copyWith(fontFamilyFallback: _fallbacks);
  return t.copyWith(
    textTheme: t.textTheme.apply(fontFamilyFallback: _fallbacks),
    primaryTextTheme: t.primaryTextTheme.apply(fontFamilyFallback: _fallbacks),
    appBarTheme: t.appBarTheme
        .copyWith(titleTextStyle: fb(t.appBarTheme.titleTextStyle)),
    // ボタンは textTheme を通らないので、ここにも日本語の代替フォントを足す。
    outlinedButtonTheme: OutlinedButtonThemeData(
        style: _buttonFallbacks(t.outlinedButtonTheme.style, fb)),
    filledButtonTheme: FilledButtonThemeData(
        style: _buttonFallbacks(t.filledButtonTheme.style, fb)),
    textButtonTheme: TextButtonThemeData(
        style: _buttonFallbacks(t.textButtonTheme.style, fb)),
    elevatedButtonTheme: ElevatedButtonThemeData(
        style: _buttonFallbacks(t.elevatedButtonTheme.style, fb)),
  );
}

ButtonStyle? _buttonFallbacks(
    ButtonStyle? style, TextStyle Function(TextStyle?) fb) {
  if (style == null) return null;
  final base = style.textStyle?.resolve(<WidgetState>{});
  return style.copyWith(textStyle: WidgetStatePropertyAll(fb(base)));
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
  for (final path in _materialIconsCandidates()) {
    if (File(path).existsSync()) {
      await load('MaterialIcons', path);
      break;
    }
  }
  await load('NotoSansJP', 'tools/x_post/fonts/NotoSansJP-Regular.otf');
}

/// MaterialIcons-Regular.otf の在り処。実行形態でパスが変わるので、
/// dart 実行ファイルから上へ辿りつつ FLUTTER_ROOT も見る（x_post_screenshot.dart と同じ）。
List<String> _materialIconsCandidates() {
  const relative = 'artifacts/material_fonts/MaterialIcons-Regular.otf';
  final paths = <String>[];
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root != null) paths.add('$root/bin/cache/$relative');
  var dir = File(Platform.resolvedExecutable).parent;
  for (var i = 0; i < 5; i++) {
    paths.add('${dir.path}/$relative');
    dir = dir.parent;
  }
  return paths;
}
