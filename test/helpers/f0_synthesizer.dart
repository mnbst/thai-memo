// 声調の並びから、その通りに発音されたF0（Hz）系列を合成するテスト用ヘルパー。
//
// マイクを使わずに判定パイプラインを検証するために使う。特定の音節だけ別の声調に
// 差し替えられるので、「下降声を上昇声で発音した」といった誤りを再現できる。

import 'dart:math' as math;

import 'package:thai_memo/core/pronunciation/pitch_track.dart';
import 'package:thai_memo/core/pronunciation/tone_contour.dart';
import 'package:thai_memo/core/thai_tone_analyzer.dart';

/// 短母音・死音節の実際の長さ（長い音節に対する比）。
///
/// タイ語の母音の長短は音韻的な対立で、長短比はおよそ 1:1.5〜2。
/// お手本側の点数配分（[kShortSyllablePoints]）とは独立に置く。**同じ定数から
/// 導くと、配分が正しいかを検証できない**（お手本を変えると合成音声も同じだけ
/// 変わってしまい、常に一致する）。
const double kShortSyllableDuration = 0.6;

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
/// [declination] は文が進むにつれて全体が下がる量（実際の発話で必ず起きる）。
/// [finalLowering] は発話末でさらに下がる量。declination とは別の現象。
/// [contourScaleBySyllable] はその音節だけ振れ幅を縮める倍率。形は同じまま
/// 動きが小さくなる（短い音節や、お手本ほど大きく動けない発音の再現）。
/// 全音節を一律に縮めても、録音側は自分の広がりで正規化されるので元に戻る。
/// [unvoicedOnsetFrames] は各音節の頭に置く無声フレーム数。子音（破裂音・
/// 摩擦音）でピッチが取れない区間を再現する。実際の発話では必ず入る。
List<double?> synthesizeF0({
  required List<ThaiTone> tones,
  Map<int, ThaiTone> substitutions = const {},
  double medianSemitone = 45,
  double halfRangeSemitone = 4,
  int framesPerSyllable = 30,
  List<bool>? shortSyllables,
  List<int>? syllablePoints,
  double flatten = 1.0,
  double declination = kDeclinationRange,
  double finalLowering = kFinalLoweringRange,
  int unvoicedOnsetFrames = 0,
  Map<int, double> contourScaleBySyllable = const {},
}) {
  // 話者が実際に出す並びで組み立てる。declination も下降声の連続による
  // 下降幅の縮小も話者側で起きる現象なので、お手本と同じ変形を掛ける。
  final spoken = List.generate(
    tones.length,
    (i) => substitutions[i] ?? tones[i],
  );
  // 短母音・死音節は実際に短い。お手本の点数配分と同じ比で縮める。
  int framesOf(int s) => (shortSyllables != null &&
          s < shortSyllables.length &&
          shortSyllables[s])
      ? (framesPerSyllable * kShortSyllableDuration).round()
      : framesPerSyllable;
  final totalFrames = List.generate(tones.length, framesOf)
      .fold<int>(0, (a, b) => a + b);
  final points = syllablePoints ??
      [
        for (var i = 0; i < tones.length; i++)
          (shortSyllables != null &&
                  i < shortSyllables.length &&
                  shortSyllables[i])
              ? kShortSyllablePoints
              : kContourResolution,
      ];
  final raw = buildRawContour(
    spoken,
    shortSyllables: shortSyllables,
    syllablePoints: points,
  );
  final counts = syllablePointCounts(tones.length, points);
  final starts = <int>[0];
  for (final count in counts) {
    starts.add(starts.last + count);
  }

  final frames = <double?>[];
  for (var s = 0; s < tones.length; s++) {
    final contour = raw.sublist(starts[s], starts[s + 1]);
    // 短い音節は実際に短く発音される。お手本の点数配分と揃えないと、
    // 「長さを見込んだお手本」を検証したことにならない。
    final syllableFrames = framesOf(s);
    for (var f = 0; f < syllableFrames; f++) {
      // 音節の頭は子音で、ピッチが取れない。
      if (f < unvoicedOnsetFrames) {
        frames.add(null);
        continue;
      }
      final t = syllableFrames == 1 ? 0.0 : f / (syllableFrames - 1);
      final scale = contourScaleBySyllable[s] ?? 1.0;
      final mean = contour.reduce((a, b) => a + b) / contour.length;
      final scaled = mean + (sampleContour(contour, t) - mean) * scale;
      final z = scaled * flatten;
      // 話者の declination。文の頭で高く、終わりで低い。
      final progress = totalFrames <= 1 ? 0.5 : (frames.length) / (totalFrames - 1);
      // flatten は発話全体の抑揚を潰すので、declination と末尾の下がりにも掛ける。
      final drift = declination * (progress - 0.5) * flatten;
      // 発話末の追加の下がり。最後の音節の中で徐々に効く。
      // 発話末は音節全体が一定量下がる（傾きではない）。
      final finalDrop =
          s == tones.length - 1 ? finalLowering * flatten : 0.0;
      final semitone =
          medianSemitone + (z - drift - finalDrop) * halfRangeSemitone;
      frames.add(kSemitoneRefHz * math.pow(2, semitone / 12).toDouble());
    }
  }
  return frames;
}
