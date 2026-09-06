// =============================================================================
// x_post_screenshot.dart
// X（Twitter）自動投稿用のスクリーンショット生成。通常の `flutter test` では
// 拾われない（_test.dart で終わらない）。CI から明示的に実行する:
//
//   flutter test test/screenshots/x_post_screenshot.dart \
//     --dart-define=X_POST_SENTENCE=build/x_post/sentence.json \
//     --dart-define=X_POST_OUT=build/x_post
//
// 実機ではなく flutter_test 上で DetailScreen をそのまま描画するので、
// サインインもシミュレータも要らずに実UIのピクセルが得られる。
// 端末フォントが無い環境なので、タイ語・日本語のフォントは明示的に読み込む。
// =============================================================================

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thai_memo/core/theme/app_theme.dart';
import 'package:thai_memo/data/models/thai_sentence.dart';
import 'package:thai_memo/l10n/app_localizations.dart';
import 'package:thai_memo/presentation/providers/analytics_provider.dart';
import 'package:thai_memo/presentation/providers/settings_provider.dart';
import 'package:thai_memo/presentation/providers/tts_provider.dart';
import 'package:thai_memo/presentation/screens/detail_screen.dart';
import 'package:thai_memo/services/analytics_service.dart';
import 'package:thai_memo/services/daily_sentence_service.dart';
import 'package:thai_memo/services/tts_service.dart';

/// 端末の論理幅（iPhone 15 Pro 相当）と描画倍率。
const double _logicalWidth = 393;
const double _pixelRatio = 3;

/// 縦に切り出す1枚あたりの論理高さ。X の画像は4枚まで。
const double _tileHeight = 852;
const int _maxTiles = 4;

/// 日本語グリフのフォールバック先。tools/x_post/fonts に置く。
const String _jpFamily = 'NotoSansJP';

/// 発音表記の IPA（ʉ ɔ など）はタイ語フォントに無いので NotoSans へ落とす。
const List<String> _fallbacks = ['NotoSans_regular', _jpFamily];

void main() {
  final sentencePath = const String.fromEnvironment(
    'X_POST_SENTENCE',
    defaultValue: 'build/x_post/sentence.json',
  );
  final outDir = const String.fromEnvironment(
    'X_POST_OUT',
    defaultValue: 'build/x_post',
  );

  testWidgets('例文詳細画面をX投稿用のPNGに書き出す', (tester) async {
    SharedPreferences.setMockInitialValues({});
    GoogleFonts.config.allowRuntimeFetching = false;
    await _loadFonts();

    // バンクの JSON は配信docと同じ形（syllables が文字列配列）なので、
    // 配信と同じ変換を通す。ThaiSentence.fromJson には直接渡せない。
    final sentence = DailySentenceService.toSentence(
      'x_post',
      json.decode(File(sentencePath).readAsStringSync())
          as Map<String, dynamic>,
    );

    tester.view.devicePixelRatio = _pixelRatio;
    tester.view.physicalSize =
        const Size(_logicalWidth, _tileHeight * _maxTiles) * _pixelRatio;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_host(sentence));
    await tester.pumpAndSettle();

    // 中身の実寸に合わせて画面を詰め直す。余白だけの帯を出さないため。
    final position =
        tester.state<ScrollableState>(find.byType(Scrollable).first).position;
    final contentHeight = position.viewportDimension + position.maxScrollExtent;
    final totalHeight = (contentHeight + _appBarHeight)
        .clamp(_tileHeight, _tileHeight * _maxTiles)
        .toDouble();
    tester.view.physicalSize =
        Size(_logicalWidth, totalHeight) * _pixelRatio;
    await tester.pumpAndSettle();

    // toImage は実時間の非同期処理なので runAsync の中で回す。
    // 偽の時間軸のままだと後始末が終わらない。
    final png = (await tester.runAsync(() => _capture(tester)))!;
    Directory(outDir).createSync(recursive: true);
    File('$outDir/screen.png').writeAsBytesSync(png);
    File('$outDir/screen.json').writeAsStringSync(
      json.encode({
        'width': (_logicalWidth * _pixelRatio).round(),
        'height': (totalHeight * _pixelRatio).round(),
        'tile_height': (_tileHeight * _pixelRatio).round(),
      }),
    );
  });
}

/// DetailScreen の AppBar 込みで測るための高さ。
const double _appBarHeight = kToolbarHeight;

Widget _host(ThaiSentence sentence) {
  return ProviderScope(
    overrides: [
      ttsServiceProvider.overrideWithValue(_SilentTtsService()),
      analyticsServiceProvider.overrideWithValue(_NoopAnalytics()),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: const Locale('ja'),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      theme: _themeWithFallbacks(buildAppLightTheme(ThaiFont.notoSansThai)),
      home: RepaintBoundary(
        key: const ValueKey('x-post-content'),
        child: DetailScreen(sentence: sentence, source: 'x_post'),
      ),
    ),
  );
}

/// 日本語と IPA は端末のフォントに落ちる作りなので、テスト環境では明示的に
/// フォールバックを足さないと豆腐になる。
///
/// ボタンのテキストはテーマが `const TextStyle(...)`（family 指定なし）を
/// 持っていて textTheme を通らないので、そこも個別に埋める。
ThemeData _themeWithFallbacks(ThemeData theme) {
  return theme.copyWith(
    textTheme: theme.textTheme.apply(fontFamilyFallback: _fallbacks),
    appBarTheme: theme.appBarTheme.copyWith(
      titleTextStyle: _withFallbacks(theme.appBarTheme.titleTextStyle),
    ),
    elevatedButtonTheme:
        ElevatedButtonThemeData(style: _patch(theme.elevatedButtonTheme.style)),
    filledButtonTheme:
        FilledButtonThemeData(style: _patch(theme.filledButtonTheme.style)),
    outlinedButtonTheme:
        OutlinedButtonThemeData(style: _patch(theme.outlinedButtonTheme.style)),
    textButtonTheme:
        TextButtonThemeData(style: _patch(theme.textButtonTheme.style)),
  );
}

TextStyle? _withFallbacks(TextStyle? style) => style?.copyWith(
      fontFamily: style.fontFamily ?? _fallbacks.first,
      fontFamilyFallback: _fallbacks,
    );

ButtonStyle? _patch(ButtonStyle? style) {
  if (style == null) return null;
  final original = style.textStyle;
  return style.copyWith(
    textStyle: WidgetStateProperty.resolveWith(
      (states) => _withFallbacks(original?.resolve(states)),
    ),
  );
}

/// google_fonts/ に同梱しているタイ語フォントと、CI が置く日本語フォントを
/// テストのフォントコレクションへ登録する。
Future<void> _loadFonts() async {
  Future<void> load(
    String family,
    List<String> paths, {
    bool firstOnly = false,
  }) async {
    final loader = FontLoader(family);
    var any = false;
    for (final path in paths) {
      final file = File(path);
      if (!file.existsSync()) continue;
      any = true;
      loader.addFont(
        Future.value(ByteData.sublistView(file.readAsBytesSync())),
      );
      if (firstOnly) break;
    }
    if (any) await loader.load();
  }

  // google_fonts は "NotoSansThai_regular" のような family 名で解決する。
  const weights = {
    'Regular': 'regular',
    'Medium': '500',
    'SemiBold': '600',
    'Bold': '700',
  };
  for (final entry in weights.entries) {
    await load('NotoSansThai_${entry.value}',
        ['google_fonts/NotoSansThai-${entry.key}.ttf']);
    await load('NotoSans_${entry.value}',
        ['google_fonts/NotoSans-${entry.key}.ttf']);
  }
  // アイコンは flutter_test の既定フォントには入っていない。SDK 同梱を読む。
  await load('MaterialIcons', _materialIconsCandidates(), firstOnly: true);
  await load(_jpFamily, ['tools/x_post/fonts/NotoSansJP-Regular.otf']);
}

/// MaterialIcons-Regular.otf の在り処。実行形態でパスが変わるので、
/// dart 実行ファイルから上へ辿りつつ FLUTTER_ROOT も見る。
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

Future<Uint8List> _capture(WidgetTester tester) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('x-post-content')),
  );
  final image = await boundary.toImage(pixelRatio: _pixelRatio);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

/// 計測は投稿用の描画では不要。呼ばれても何もしない。
class _NoopAnalytics extends Fake implements AnalyticsService {
  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}

/// TTS はプラグイン実体を持たないので、呼ばれても何もしない。
/// TtsService を継承すると FlutterTts のチャネルを掴むので、実装だけ真似る。
class _SilentTtsService extends Fake implements TtsService {
  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();

  @override
  void dispose() {}
}
