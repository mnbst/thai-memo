// 声調の並びから、その通りに発音されたF0（Hz）系列を合成するテスト用ヘルパー。
//
// マイクを使わずに判定パイプラインを検証するために使う。特定の音節だけ別の声調に
// 差し替えられるので、「下降声を上昇声で発音した」といった誤りを再現できる。

import 'dart:math' as math;

import 'package:thai_memo/core/pronunciation/pitch_track.dart';
import 'package:thai_memo/core/pronunciation/tone_contour.dart';
import 'package:thai_memo/core/thai_tone_analyzer.dart';

/// カーブを正規化時間 [t]（0..1）で線形補間する。
double sampleContour(List<double> contour, double t) {
  final position = (t * (contour.length - 1)).clamp(0, contour.length - 1);
  final lower = position.floor();
  final upper = math.min(lower + 1, contour.length - 1);
  final fraction = position - lower;
  return contour[lower] * (1 - fraction) + contour[upper] * fraction;
}

/// 声調の並びに従うF0系列（Hz）を合成する。
///
/// [substitutions] に音節の添字と声調を渡すと、その音節だけ別の声調で
/// 発音したことにできる。
/// [flatten] を指定すると、全体を平坦に（抑揚なく）発音したことにできる。
List<double?> synthesizeF0({
  required List<ThaiTone> tones,
  Map<int, ThaiTone> substitutions = const {},
  double medianSemitone = 45,
  double halfRangeSemitone = 4,
  int framesPerSyllable = 30,
  double flatten = 1.0,
}) {
  final frames = <double?>[];
  for (var s = 0; s < tones.length; s++) {
    final tone = substitutions[s] ?? tones[s];
    final contour = kToneContours[tone] ?? kToneContours[ThaiTone.unknown]!;
    for (var f = 0; f < framesPerSyllable; f++) {
      final t = framesPerSyllable == 1 ? 0.0 : f / (framesPerSyllable - 1);
      final z = sampleContour(contour, t) * flatten;
      final semitone = medianSemitone + z * halfRangeSemitone;
      frames.add(kSemitoneRefHz * math.pow(2, semitone / 12).toDouble());
    }
  }
  return frames;
}
