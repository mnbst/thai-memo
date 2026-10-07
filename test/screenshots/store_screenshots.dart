// =============================================================================
// store_screenshots.dart
// App Store のスクリーンショット（見出し＋端末の枠＋アプリの画面）を合成する。
// 通常の `flutter test` では拾われない（_test.dart で終わらない）。
//
//   tools/store_screenshots/fetch_fonts.sh
//   flutter test test/screenshots/store_screenshots.dart
//
// 素材は tools/store_screenshots/capture.sh がシミュレータから撮った
// build/store_shots/raw/<device>/<lang>/<shot_id>.png。見出しと並び順は
// tools/store_screenshots/captions.json。素材がある組み合わせだけ書き出す。
//
// 出力: build/store_shots/out/<device>/<lang>/01.png ...（B 案・既定の並び）
//       build/store_shots/out_a/iphone/<lang>/01.jpg ...（A 案・旧1枚目が先頭）
// =============================================================================

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const String _rawDir = 'build/store_shots/raw';
const String _outDir = 'build/store_shots/out';

/// A/B テストの A 案（旧1枚目が先頭）。iPhone だけ。
const String _outAbDir = 'build/store_shots/out_a';
const String _captionsPath = 'tools/store_screenshots/captions.json';
const String _font = 'StoreCaption';

const List<String> _langs = ['ja', 'en'];

// アプリの深藍（AppColors.indigo）を背景に敷き、金を強調色にする。
const Color _text = Color(0xFFF6F2EA);
const Color _accent = Color(0xFFE7BE6A);
const Color _bgTop = Color(0xFF22355A);
const Color _bgBottom = Color(0xFF101A2E);
const Color _bezel = Color(0xFF14151A);

/// 強調しない行の文字の大きさ（強調する行に対する比）。
const double _plainScale = 0.6;

/// 出力する端末ごとの寸法と見た目。寸法は App Store Connect が受け付ける値。
class _Device {
  const _Device({
    required this.id,
    required this.size,
    required this.captionTop,
    required this.fontSize,
    required this.captionGap,
    required this.bottomGap,
    required this.bezelRatio,
    required this.cornerRatio,
    required this.isPhone,
    this.phoneWidthRatio,
  });

  final String id;
  final Size size;
  final double captionTop;
  final double fontSize;
  final double captionGap;
  final double bottomGap;

  /// 画面の幅に対する枠の太さ・角の丸み。
  final double bezelRatio;
  final double cornerRatio;
  final bool isPhone;

  /// 指定すると、端末を画面幅に対するこの割合の幅で描き、下端は切る。
  /// 縦長の iPhone は高さに収めると小さくなり、中の文字が読めないため。
  final double? phoneWidthRatio;
}

const _devices = [
  _Device(
    id: 'iphone',
    size: Size(1320, 2868),
    captionTop: 130,
    fontSize: 176,
    captionGap: 80,
    bottomGap: 0,
    bezelRatio: 0.032,
    cornerRatio: 0.13,
    isPhone: true,
    phoneWidthRatio: 0.84,
  ),
  _Device(
    id: 'ipad',
    size: Size(2064, 2752),
    captionTop: 130,
    fontSize: 176,
    captionGap: 90,
    bottomGap: 110,
    bezelRatio: 0.03,
    cornerRatio: 0.035,
    isPhone: false,
  ),
];

void main() {
  testWidgets('ストア用スクショを合成する', (tester) async {
    await _loadFont();
    final config = json.decode(File(_captionsPath).readAsStringSync())
        as Map<String, dynamic>;
    final shots =
        (config['shots'] as List<dynamic>).cast<Map<String, dynamic>>();
    final abFirst =
        (config['ab_first'] as Map<String, dynamic>?) ?? const {};

    var written = 0;
    for (final device in _devices) {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = device.size;
      for (final lang in _langs) {
        // 見出しの大きさは端末・言語ごとに1つにそろえる。1枚ずつ枠に
        // 収めると、長い見出しだけ小さくなって並べたときにばらつく。
        final fontSize =
            _fittedFontSize(device, [for (final s in shots) s[lang] as String]);
        final composed = <Uint8List>[];
        for (final shot in shots) {
          final raw = File('$_rawDir/${device.id}/$lang/${shot['id']}.png');
          if (!raw.existsSync()) continue;
          final image = (await tester.runAsync(() => _decode(raw)))!;

          // 言語で画面の並びが変わるものは「端末/言語」で上書きできる。
          final zooms = shot['zoom'] as Map<String, dynamic>?;
          final zoom = (zooms?['${device.id}/$lang'] ?? zooms?[device.id])
              as List<dynamic>?;
          await tester.pumpWidget(
            _StoreShot(
              device: device,
              caption: shot[lang] as String,
              fontSize: fontSize,
              screen: image,
              zoom: zoom == null ? null : _rect(zoom.cast<num>()),
            ),
          );
          await tester.pump();

          final png = (await tester.runAsync(() => _capture(tester)))!;
          image.dispose();
          composed.add(png);
          _write('$_outDir/${device.id}/$lang', composed.length, 'png', png);
          written++;
        }

        // A/B テストの A 案: 旧1枚目を先頭に置き、枚数は B 案と同じにする。
        final legacy = abFirst[lang] as String?;
        if (device.isPhone && legacy != null && composed.isNotEmpty) {
          final dir = '$_outAbDir/${device.id}/$lang';
          _write(dir, 1, 'jpg', File(legacy).readAsBytesSync());
          for (var i = 0; i < composed.length - 1; i++) {
            _write(dir, i + 2, 'png', composed[i]);
          }
        }
      }
    }
    tester.view.reset();
    if (written == 0) {
      fail('素材がない。store_mock_screens.dart か capture.sh で $_rawDir に作る');
    }
  });
}

void _write(String dir, int index, String ext, List<int> bytes) {
  final file = File('$dir/${index.toString().padLeft(2, '0')}.$ext');
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(bytes);
  // ignore: avoid_print
  print('WROTE ${file.path}');
}

Rect _rect(List<num> v) => Rect.fromLTWH(
      v[0].toDouble(),
      v[1].toDouble(),
      v[2].toDouble(),
      v[3].toDouble(),
    );

/// すべての見出しが幅に収まる、共通の文字の大きさ。
double _fittedFontSize(_Device device, List<String> captions) {
  // 丸め誤差で折り返さないよう、枠よりわずかに狭く見積もる。
  final available = device.size.width * 0.9 * 0.98;
  var widest = 0.0;
  for (final caption in captions) {
    final painter = TextPainter(
      text: _captionSpan(caption, device.fontSize),
      textDirection: TextDirection.ltr,
    )..layout();
    if (painter.width > widest) widest = painter.width;
    painter.dispose();
  }
  if (widest <= available) return device.fontSize;
  return device.fontSize * available / widest;
}

class _StoreShot extends StatelessWidget {
  const _StoreShot({
    required this.device,
    required this.caption,
    required this.fontSize,
    required this.screen,
    this.zoom,
  });

  final _Device device;
  final String caption;
  final double fontSize;
  final ui.Image screen;

  /// 拡大して重ねる範囲（素材に対する割合）。
  final Rect? zoom;

  @override
  Widget build(BuildContext context) {
    final size = device.size;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: RepaintBoundary(
        key: const ValueKey('store-shot'),
        child: Container(
          width: size.width,
          height: size.height,
          clipBehavior: Clip.hardEdge,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [_bgTop, _bgBottom],
            ),
          ),
          child: Column(
            children: [
              SizedBox(height: device.captionTop),
              // 見出しの高さは「小さい行＋大きい行」の2行ぶんで固定する。
              // 字形によって行の高さがわずかに変わり、端末の枠の大きさが
              // 1枚ずつずれるのを防ぐ。
              SizedBox(
                width: size.width * 0.9,
                height: device.fontSize * 1.28 * (1 + _plainScale) * 1.08,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final line in caption.split('\n'))
                        Text.rich(
                          _captionSpan(line, fontSize),
                          textAlign: TextAlign.center,
                          softWrap: false,
                          // 「&」などフォールバックに落ちる字があっても行の
                          // 高さを変えない。高くなると見出しごと縮む。
                          strutStyle: StrutStyle(
                            fontFamily: _font,
                            fontSize: line.contains('**')
                                ? fontSize
                                : fontSize * _plainScale,
                            height: 1.28,
                            forceStrutHeight: true,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              SizedBox(height: device.captionGap),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(bottom: device.bottomGap),
                  child: _DeviceFrame(
                    device: device,
                    screen: screen,
                    zoom: zoom,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// `**強調**` を強調色・大きい字にし、それ以外を小さい字にした見出し。
TextSpan _captionSpan(String caption, double fontSize) {
  TextStyle style(double size, Color color) => TextStyle(
        fontFamily: _font,
        fontSize: size,
        height: 1.28,
        letterSpacing: size * 0.01,
        color: color,
      );
  final parts = caption.split('**');
  return TextSpan(
    style: style(fontSize * _plainScale, _text),
    children: [
      for (var i = 0; i < parts.length; i++)
        TextSpan(
          text: parts[i],
          style: i.isOdd ? style(fontSize, _accent) : null,
        ),
    ],
  );
}

/// 端末の枠。残りの高さに収まる大きさで、画面の縦横比を保つ。
/// [zoom] があれば、その範囲を端末より広く拡大して同じ高さに重ねる。
class _DeviceFrame extends StatelessWidget {
  const _DeviceFrame({required this.device, required this.screen, this.zoom});

  final _Device device;
  final ui.Image screen;
  final Rect? zoom;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final aspect = screen.width / screen.height;
        final k = 1 + 2 * device.bezelRatio;
        // 枠込みの幅・高さが空きに収まる画面幅。横は 9 割まで使う。
        // phoneWidthRatio があれば幅だけで決め、はみ出た下端は切る。
        final widthRatio = device.phoneWidthRatio;
        final screenWidth = widthRatio != null
            ? constraints.maxWidth * widthRatio / k
            : [
                constraints.maxWidth * 0.9 / k,
                constraints.maxHeight / (1 / aspect + 2 * device.bezelRatio),
              ].reduce((a, b) => a < b ? a : b);
        final bezel = screenWidth * device.bezelRatio;
        final screenHeight = screenWidth / aspect;
        final outerRadius = screenWidth * device.cornerRatio;
        final innerRadius = outerRadius - bezel;

        final body = Container(
          width: screenWidth + bezel * 2,
          height: screenHeight + bezel * 2,
          padding: EdgeInsets.all(bezel),
          decoration: BoxDecoration(
            color: _bezel,
            borderRadius: BorderRadius.circular(outerRadius),
            border: Border.all(
              color: const Color(0xFF6A6E7A),
              width: bezel * 0.14,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: screenWidth * 0.06,
                offset: Offset(0, screenWidth * 0.025),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(innerRadius),
            child: Stack(
              children: [
                Positioned.fill(
                  child: RawImage(image: screen, fit: BoxFit.fill),
                ),
                if (device.isPhone) _island(screenWidth),
              ],
            ),
          ),
        );

        final zoom = this.zoom;
        return OverflowBox(
          alignment: Alignment.topCenter,
          maxHeight: double.infinity,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              ..._buttons(screenWidth, bezel),
              body,
              if (zoom != null)
                _zoomCallout(
                  zoom,
                  canvasWidth: constraints.maxWidth,
                  frameWidth: screenWidth + bezel * 2,
                  screenSize: Size(screenWidth, screenHeight),
                  bezel: bezel,
                ),
            ],
          ),
        );
      },
    );
  }

  /// 画面の一部を、ほぼ画面幅いっぱいまで拡大した切り抜き。
  /// 元の位置と同じ高さを中心に置き、どこを拡大したかが分かるようにする。
  Widget _zoomCallout(
    Rect zoom, {
    required double canvasWidth,
    required double frameWidth,
    required Size screenSize,
    required double bezel,
  }) {
    final width = canvasWidth * 0.94;
    final src = Rect.fromLTWH(
      zoom.left * screen.width,
      zoom.top * screen.height,
      zoom.width * screen.width,
      zoom.height * screen.height,
    );
    final height = width * src.height / src.width;
    final centerY =
        bezel + (zoom.top + zoom.height / 2) * screenSize.height;
    final radius = width * 0.04;
    return Positioned(
      left: (frameWidth - width) / 2,
      top: centerY - height / 2,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: _accent, width: width * 0.006),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.45),
              blurRadius: width * 0.06,
              offset: Offset(0, width * 0.02),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: CustomPaint(painter: _CropPainter(screen, src)),
        ),
      ),
    );
  }

  /// Dynamic Island。シミュレータのスクショには写らないので描き足す。
  /// 寸法は論理幅 440pt の端末での実寸（126x37pt、上端から 11pt）。
  Widget _island(double screenWidth) {
    final pt = screenWidth / 440;
    return Positioned(
      top: 11 * pt,
      left: (screenWidth - 126 * pt) / 2,
      child: Container(
        width: 126 * pt,
        height: 37 * pt,
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(19 * pt),
        ),
      ),
    );
  }

  /// 側面のボタン。iPhone は左に音量など、右に電源。iPad は上面に電源。
  List<Widget> _buttons(double screenWidth, double bezel) {
    final w = bezel * 0.32;
    Widget button(double left, double top, double width, double height) =>
        Positioned(
          left: left,
          top: top,
          child: Container(
            width: width,
            height: height,
            decoration: BoxDecoration(
              color: const Color(0xFF2A2B31),
              borderRadius: BorderRadius.circular(w),
            ),
          ),
        );
    if (!device.isPhone) {
      return [
        button(screenWidth * 0.82, -w, screenWidth * 0.06, w * 2),
      ];
    }
    final right = screenWidth + bezel * 2 - w;
    return [
      button(-w, screenWidth * 0.36, w * 2, screenWidth * 0.07),
      button(-w, screenWidth * 0.5, w * 2, screenWidth * 0.14),
      button(-w, screenWidth * 0.68, w * 2, screenWidth * 0.14),
      button(right, screenWidth * 0.56, w * 2, screenWidth * 0.22),
    ];
  }
}

class _CropPainter extends CustomPainter {
  _CropPainter(this.image, this.src);

  final ui.Image image;
  final Rect src;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawImageRect(
      image,
      src,
      Offset.zero & size,
      Paint()..filterQuality = FilterQuality.high,
    );
  }

  @override
  bool shouldRepaint(_CropPainter old) =>
      old.image != image || old.src != src;
}

Future<ui.Image> _decode(File file) async {
  final codec = await ui.instantiateImageCodec(file.readAsBytesSync());
  final frame = await codec.getNextFrame();
  codec.dispose();
  return frame.image;
}

Future<void> _loadFont() async {
  const path = 'tools/store_screenshots/fonts/NotoSansJP-Black.otf';
  final file = File(path);
  if (!file.existsSync()) {
    fail('$path がない。tools/store_screenshots/fetch_fonts.sh を先に実行する');
  }
  final loader = FontLoader(_font)
    ..addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));
  await loader.load();
}

Future<Uint8List> _capture(WidgetTester tester) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('store-shot')),
  );
  final image = await boundary.toImage();
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}
