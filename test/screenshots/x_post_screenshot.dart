// =============================================================================
// x_post_screenshot.dart
// X（Twitter）自動投稿用の画像と動画フレームを生成する。通常の `flutter test`
// では拾われない（_test.dart で終わらない）。CI から明示的に実行する:
//
//   flutter test test/screenshots/x_post_screenshot.dart \
//     --dart-define=X_POST_SENTENCE=build/x_post/sentence.json \
//     --dart-define=X_POST_OUT=build/x_post \
//     --dart-define=X_POST_AUDIO_MS=4200
//
// 実機ではなく flutter_test 上で DetailScreen をそのまま描画するので、
// サインインもシミュレータも要らずに実UIのピクセルが得られる。
// 端末フォントが無い環境なので、タイ語・日本語のフォントは明示的に読み込む。
//
// 出力:
//   image_1.png ... image_3.png  動画で見切れた先からスクロールして撮った画面
//   frames/frame_0001.png ...    「お手本を聞く」を押す操作の連番フレーム
//   frames.json                  フレームレートと音声を差し込む位置
// =============================================================================

import 'dart:convert';
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
import 'package:thai_memo/data/models/thai_sentence.dart';
import 'package:thai_memo/l10n/app_localizations.dart';
import 'package:thai_memo/l10n/app_localizations_ja.dart';
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

/// 1枚あたりの論理高さ（端末1画面ぶん）。
const double _tileHeight = 852;

/// 撮る枚数の上限。添付は4件までで、1件は読み上げ動画に使う。
const int _maxShots = 3;

/// 日本語グリフのフォールバック先。tools/x_post/fonts に置く。
const String _jpFamily = 'NotoSansJP';

/// 発音表記の IPA（ʉ ɔ など）はタイ語フォントに無いので NotoSans へ落とす。
const List<String> _fallbacks = ['NotoSans_regular', _jpFamily];

/// DetailScreen の AppBar 込みで測るための高さ。
const double _appBarHeight = kToolbarHeight;

/// 動画のフレームレート。読み上げの尺に合わせて枚数を決める。
const int _fps = 20;
const Duration _frameGap = Duration(milliseconds: 1000 ~/ _fps);

/// 押す前の静止・指マークを出してから押すまで・読み上げ後の余韻（フレーム数）。
const int _leadFrames = 12;
const int _pressFrames = 5;
const int _tailFrames = 12;

final _l10n = L10nJa();

void main() {
  const sentencePath = String.fromEnvironment(
    'X_POST_SENTENCE',
    defaultValue: 'build/x_post/sentence.json',
  );
  const outDir = String.fromEnvironment(
    'X_POST_OUT',
    defaultValue: 'build/x_post',
  );
  // 読み上げ音声の長さ。動画のフレーム数と、再生バーの進み方をこれに合わせる。
  const audioMs = int.fromEnvironment('X_POST_AUDIO_MS', defaultValue: 4000);

  testWidgets('例文詳細画面をスクロールしながらPNGに書き出す', (tester) async {
    final sentence = await _prepare(sentencePath);

    tester.view.devicePixelRatio = _pixelRatio;
    tester.view.physicalSize =
        const Size(_logicalWidth, _tileHeight) * _pixelRatio;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_host(sentence, tts: _SilentTtsService()));
    await tester.pumpAndSettle();

    final position =
        tester.state<ScrollableState>(find.byType(Scrollable).first).position;
    final offsets = _shotOffsets(tester, position);

    final dir = Directory(outDir)..createSync(recursive: true);
    // 前回の実行が残した枚数の方が多いことがある。古い画像を投稿しない。
    for (final file in dir.listSync()) {
      if (file is File && RegExp(r'image_\d+\.png$').hasMatch(file.path)) {
        file.deleteSync();
      }
    }

    // どの1枚も端末1画面ぶんのまま。下端まで行ったらそこで止まる（前の1枚と
    // 重なる）。切り詰めると本物の画面に見えない。
    var count = 0;
    var previous = -1.0;
    for (final wanted in offsets) {
      final offset = wanted.clamp(0.0, position.maxScrollExtent).toDouble();
      if (offset == previous) break;
      previous = offset;
      position.jumpTo(offset);
      await tester.pumpAndSettle();
      // toImage は実時間の非同期処理なので runAsync の中で回す。
      // 偽の時間軸のままだと後始末が終わらない。
      final png = (await tester.runAsync(() => _capture(tester)))!;
      File('$outDir/image_${++count}.png').writeAsBytesSync(png);
    }
    File('$outDir/screen.json').writeAsStringSync(
      json.encode({
        'width': (_logicalWidth * _pixelRatio).round(),
        'height': (_tileHeight * _pixelRatio).round(),
        'images': count,
      }),
    );
  });

  testWidgets('お手本を聞く操作を連番PNGに書き出す', (tester) async {
    final sentence = await _prepare(sentencePath);
    final tap = ValueNotifier<Offset?>(null);
    addTearDown(tap.dispose);

    tester.view.devicePixelRatio = _pixelRatio;
    tester.view.physicalSize =
        const Size(_logicalWidth, _tileHeight) * _pixelRatio;
    addTearDown(tester.view.reset);

    final tts = _ScriptedTtsService(
      const Duration(milliseconds: audioMs),
      sentence.thaiText.length,
    );
    await tester.pumpWidget(_host(sentence, tts: tts, tapMarker: tap));
    await tester.pumpAndSettle();

    // 端末1画面ぶんをそのまま映す。切り詰めると本物の画面に見えない。
    final listen = find.text(_l10n.sentenceListenModel).first;

    final frames = Directory('$outDir/frames');
    if (frames.existsSync()) frames.deleteSync(recursive: true);
    frames.createSync(recursive: true);

    var count = 0;
    Future<void> shoot() async {
      final png = (await tester.runAsync(() => _capture(tester)))!;
      final name = 'frame_${(++count).toString().padLeft(4, '0')}.png';
      File('${frames.path}/$name').writeAsBytesSync(png);
    }

    // 静止 → 指マーク → タップ → 再生 → 余韻。実際に触っているように見せる。
    for (var i = 0; i < _leadFrames; i++) {
      await tester.pump(_frameGap);
      await shoot();
    }
    tap.value = tester.getCenter(listen);
    for (var i = 0; i < _pressFrames; i++) {
      await tester.pump(_frameGap);
      await shoot();
    }
    await tester.tap(listen);
    await tester.pump(_frameGap);
    await shoot();
    tap.value = null;

    final playFrames = (audioMs / _frameGap.inMilliseconds).ceil();
    for (var i = 0; i < playFrames + _tailFrames; i++) {
      await tester.pump(_frameGap);
      await shoot();
    }

    // 再生を止め、繰り返し待ちのタイマーを消化してから終える。
    // 鳴りっぱなしのまま抜けると、後始末が終わらずテストが落ちる。
    final pause = find.byIcon(Icons.pause);
    if (pause.evaluate().isNotEmpty) await tester.tap(pause);
    await tester.pump(const Duration(milliseconds: 1200));

    File('$outDir/frames.json').writeAsStringSync(
      json.encode({
        'fps': _fps,
        'count': count,
        // 音声を鳴らし始める位置。タップの次のフレームで再生が始まる。
        'audio_delay_ms': (_leadFrames + _pressFrames + 1) * _frameGap.inMilliseconds,
      }),
    );
  });
}

/// フォントを読み、投稿する例文を読み込む。
Future<ThaiSentence> _prepare(String sentencePath) async {
  SharedPreferences.setMockInitialValues({});
  GoogleFonts.config.allowRuntimeFetching = false;
  await _loadFonts();

  // バンクの JSON は配信docと同じ形（syllables が文字列配列）なので、
  // 配信と同じ変換を通す。ThaiSentence.fromJson には直接渡せない。
  return DailySentenceService.toSentence(
    'x_post',
    json.decode(File(sentencePath).readAsStringSync()) as Map<String, dynamic>,
  );
}

/// 何回スクロールして撮るかを決め、その各スクロール位置を返す。
///
/// 添付は動画1本と画像3枚まで。1画面目は動画がそのまま映すので撮らず、
/// 動画で見切れた要素の頭が1枚目の先頭に来るところから始める。以降も同じで、
/// 画面に収まる範囲で最も下の切れ目（見出し・区切り線）まで送る。
/// 切れ目が見つからない回は画面ぶん送る。枚数は必要なぶんだけで、上限まで
/// 埋めない。
List<double> _shotOffsets(WidgetTester tester, ScrollPosition position) {
  final viewport = position.viewportDimension;
  final maxScroll = position.maxScrollExtent;
  final breaks = _breakPoints(tester);

  final offsets = <double>[];
  var offset = 0.0;
  while (offsets.length < _maxShots) {
    // まだ見えていないぶんが画面の1/3に満たないなら撮らない。残りわずかの
    // ために1枚増やすと、前の1枚とほとんど同じ画像が並ぶ。2枚で収まるなら
    // 2枚、1枚で収まるなら1枚。
    if (maxScroll - offset < viewport / 3) break;
    // 送り先は下端まで。ここを超えて狙うと clamp されて頭が切れる。
    final limit = offset + viewport > maxScroll ? maxScroll : offset + viewport;
    final candidates = breaks.where((b) => b > offset + 80 && b <= limit);
    final next = candidates.isEmpty
        ? limit
        : candidates.reduce((a, b) => a > b ? a : b);
    if (next <= offset) break;
    offset = next;
    offsets.add(offset);
  }
  return offsets;
}

/// 途中で切りたくない要素の頭（スクロール量に換算した位置）。
///
/// セクション見出しと、単語カードの各行を分ける区切り線を使う。
List<double> _breakPoints(WidgetTester tester) {
  const margin = 14.0;
  final points = <double>[];
  void add(Finder finder) {
    for (final element in finder.evaluate()) {
      final box = element.renderObject as RenderBox?;
      if (box == null || !box.hasSize) continue;
      final top = box.localToGlobal(Offset.zero).dy;
      points.add(top - _appBarHeight - margin);
    }
  }

  add(find.text(_l10n.detailUsageSection));
  add(find.text(_l10n.detailWordsSection));
  add(find.byType(Divider));
  return points.where((p) => p > 0).toList()..sort();
}

Widget _host(
  ThaiSentence sentence, {
  required TtsService tts,
  ValueListenable<Offset?>? tapMarker,
}) {
  final screen = DetailScreen(sentence: sentence, source: 'x_post');
  return ProviderScope(
    overrides: [
      ttsServiceProvider.overrideWithValue(tts),
      analyticsServiceProvider.overrideWithValue(_NoopAnalytics()),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: const Locale('ja'),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      theme: _themeWithFallbacks(buildAppLightTheme(ThaiFont.sarabun)),
      home: RepaintBoundary(
        key: const ValueKey('x-post-content'),
        child: tapMarker == null
            ? screen
            : Stack(
                children: [
                  Positioned.fill(child: screen),
                  ValueListenableBuilder<Offset?>(
                    valueListenable: tapMarker,
                    builder: (context, offset, _) =>
                        offset == null ? const SizedBox.shrink() : _Finger(offset),
                  ),
                ],
              ),
      ),
    ),
  );
}

/// タップ位置を示す丸。動画に指の代わりとして映す。
class _Finger extends StatelessWidget {
  const _Finger(this.offset);

  final Offset offset;

  @override
  Widget build(BuildContext context) {
    const size = 46.0;
    return Positioned(
      left: offset.dx - size / 2,
      top: offset.dy - size / 2,
      child: IgnorePointer(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: 0.34),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.66),
              width: 2,
            ),
          ),
        ),
      ),
    );
  }
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

/// google_fonts/ に同梱しているタイ語フォント（Sarabun）と、CI が置く日本語フォントを
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

  // google_fonts は "Sarabun_regular" のような family 名で解決する。
  // アプリの既定フォント（Sarabun）に合わせる。
  const weights = {
    'Regular': 'regular',
    'Medium': '500',
    'SemiBold': '600',
    'Bold': '700',
  };
  for (final entry in weights.entries) {
    await load('Sarabun_${entry.value}',
        ['google_fonts/Sarabun-${entry.key}.ttf']);
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

/// 音は鳴らさないが、読み上げの尺だけ本物どおりに振る舞う TTS。
///
/// 再生バーは TTS からの読み上げ位置の通知で進むので、これが無いと
/// 動画のバーが動かない。投稿する音声（audio.mp3）と同じ長さをかけて
/// 先頭から末尾まで通知する。
class _ScriptedTtsService extends Fake implements TtsService {
  _ScriptedTtsService(this.duration, this.textLength);

  final Duration duration;
  final int textLength;

  @override
  void Function(int start, int end)? onProgress;

  @override
  int get session => 0;

  @override
  Future<void> speak(
    String text, {
    bool slow = false,
    bool keepVoice = false,
  }) async {
    const steps = 24;
    for (var i = 1; i <= steps; i++) {
      await Future<void>.delayed(duration ~/ steps);
      final start = (textLength * i / steps).round();
      onProgress?.call(start, start);
    }
  }

  @override
  Future<void> stop({bool waitForCancel = false}) async {}

  @override
  Future<void> stopAll() async {}

  @override
  void dispose() {}
}
