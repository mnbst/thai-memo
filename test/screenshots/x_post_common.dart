// =============================================================================
// x_post_common.dart
// SNS 投稿用の画面書き出し（tiktok_video_screenshot.dart / tip_card_screenshot.dart）
// で共有する部品。フォントの読み込み、テーマのフォールバック、描画の取り出し、
// タップ位置の丸、TTS・計測の差し替え。
// =============================================================================

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thai_memo/data/models/thai_sentence.dart';
import 'package:thai_memo/services/analytics_service.dart';
import 'package:thai_memo/services/daily_sentence_service.dart';
import 'package:thai_memo/services/sentence_audio_cache.dart';
import 'package:thai_memo/services/tts_service.dart';

/// 端末の論理幅・高さ（iPhone 15 Pro 相当）と描画倍率。
const double postLogicalWidth = 393;
const double postTileHeight = 852;
const double postPixelRatio = 3;

/// 日本語グリフのフォールバック先。tools/x_post/fonts に置く。
const String _jpFamily = 'NotoSansJP';

/// 発音表記の IPA（ʉ ɔ など）はタイ語フォントに無いので NotoSans へ落とす。
const List<String> _fallbacks = ['NotoSans_regular', _jpFamily];

/// フォントを読み、投稿する例文を読み込む。
Future<ThaiSentence> preparePostSentence(String sentencePath) async {
  SharedPreferences.setMockInitialValues({});
  await loadPostFonts();

  // バンクの JSON は配信docと同じ形（syllables が文字列配列）なので、
  // 配信と同じ変換を通す。ThaiSentence.fromJson には直接渡せない。
  return DailySentenceService.toSentence(
    'x_post',
    json.decode(File(sentencePath).readAsStringSync()) as Map<String, dynamic>,
  );
}

/// 描画面を端末1画面ぶんにする。[height] を渡すとその高さ（論理）にする。
void setPostView(WidgetTester tester, {double height = postTileHeight}) {
  tester.view.devicePixelRatio = postPixelRatio;
  tester.view.physicalSize = Size(postLogicalWidth, height) * postPixelRatio;
  addTearDown(tester.view.reset);
}

/// [key] の RepaintBoundary を PNG にする。toImage は実時間の非同期処理なので
/// 呼び出し側は runAsync の中で回す。偽の時間軸のままだと後始末が終わらない。
Future<Uint8List> capturePost(WidgetTester tester, Key key) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(key));
  final image = await boundary.toImage(pixelRatio: postPixelRatio);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

/// タップ位置を示す丸。動画に指の代わりとして映す。
class PostFinger extends StatelessWidget {
  const PostFinger(this.offset, {super.key, this.dark = false});

  final Offset offset;

  /// 明るい背景（クイズ画面など）でも見えるよう、濃い色で塗る。
  final bool dark;

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
            color: dark
                ? Colors.black.withValues(alpha: 0.28)
                : Colors.white.withValues(alpha: 0.34),
            border: Border.all(
              color: dark
                  ? Colors.black.withValues(alpha: 0.5)
                  : Colors.white.withValues(alpha: 0.66),
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
ThemeData postThemeWithFallbacks(ThemeData theme) {
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
Future<void> loadPostFonts() async {
  GoogleFonts.config.allowRuntimeFetching = false;
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
    await load(
        'Sarabun_${entry.value}', ['google_fonts/Sarabun-${entry.key}.ttf']);
    await load(
        'NotoSans_${entry.value}', ['google_fonts/NotoSans-${entry.key}.ttf']);
  }
  // アイコンは flutter_test の既定フォントには入っていない。SDK 同梱を読む。
  await load('MaterialIcons', _materialIconsCandidates(), firstOnly: true);
  await load(_jpFamily, ['tools/x_post/fonts/NotoSansJP-Regular.otf']);
  // 声調記号（— ^ / など）は fontFamily: 'monospace' で描く。テストには
  // 無いので、記号を持つ NotoSans を同じ名前で読ませる（無いと豆腐になる）。
  await load('monospace', ['google_fonts/NotoSans-Regular.ttf']);
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

/// 計測は投稿用の描画では不要。呼ばれても何もしない。
class NoopPostAnalytics extends Fake implements AnalyticsService {
  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}

/// TTS はプラグイン実体を持たないので、呼ばれても何もしない。
/// TtsService を継承すると FlutterTts のチャネルを掴むので、実装だけ真似る。
class SilentPostTtsService extends Fake implements TtsService {
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
class ScriptedPostTtsService extends Fake implements TtsService {
  ScriptedPostTtsService(this.duration, this.textLength);

  final Duration duration;
  final int textLength;

  /// 読み上げを始めるたびに呼ぶ。動画に音声を重ねる位置を記録するのに使う。
  void Function()? onSpeak;

  /// 立てると以降は鳴らさない（画面を切り替える前に、繰り返しを止める）。
  bool silenced = false;

  @override
  void Function(int start, int end)? onProgress;

  @override
  int get session => 0;

  @override
  Future<bool> speakSentence(
    SentenceAudioSource source, {
    int fromChar = 0,
    bool keepVoice = false,
    TtsSpeed speed = TtsSpeed.normal,
    void Function(bool loading)? onLoading,
    bool Function()? stillWanted,
  }) async {
    await speak(source.text);
    return true;
  }

  @override
  Future<void> speak(
    String text, {
    bool slow = false,
    bool keepVoice = false,
    TtsSpeed speed = TtsSpeed.normal,
  }) async {
    if (silenced) return;
    onSpeak?.call();
    const steps = 24;
    for (var i = 1; i <= steps; i++) {
      await Future<void>.delayed(duration ~/ steps);
      if (silenced) return;
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
