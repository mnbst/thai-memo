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
/// [clauseStarts] は新しい節が始まる音節の添字。話者は節ごとに声を上げ直す
/// ので、declination と末尾の下がりは**節ごとに**掛ける。
/// [pauseFrames] は節の切れ目に置く無音のフレーム数。
/// [clauseFinalLowering] は**文中の**節末で下がる量。文末（[finalLowering]）とは
/// 別に置く。話者によって下がらないこと（0）も、逆に上がること（負）もある。
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
  double carryoverStrength = 0.0,
  double carryoverReach = 1.0,
  Map<int, double> levelOffsetBySyllable = const {},
  List<int> clauseStarts = const [],
  int pauseFrames = 0,
  double clauseFinalLowering = kClauseFinalLoweringRange,
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
  // 節の区切り（0 と末尾を含む）。話者の declination は節ごとにやり直される。
  final segments = <int>[
    0,
    ...clauseStarts.where((s) => s > 0 && s < tones.length),
    tones.length,
  ]..sort();
  int segmentOf(int syllable) {
    for (var c = segments.length - 2; c >= 0; c--) {
      if (syllable >= segments[c]) return c;
    }
    return 0;
  }
  final segmentFrames = [
    for (var c = 0; c + 1 < segments.length; c++)
      [
        for (var s = segments[c]; s < segments[c + 1]; s++) framesOf(s),
      ].fold<int>(0, (a, b) => a + b),
  ];
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
    clauseStarts: clauseStarts,
  );
  final counts = syllablePointCounts(tones.length, points);
  final starts = <int>[0];
  for (final count in counts) {
    starts.add(starts.last + count);
  }

  final frames = <double?>[];
  var framesInSegment = 0;
  for (var s = 0; s < tones.length; s++) {
    final segment = segmentOf(s);
    if (s > 0 && segments.contains(s)) {
      // 節の切れ目。息継ぎのぶん声が止まる。
      for (var f = 0; f < pauseFrames; f++) {
        frames.add(null);
      }
      framesInSegment = 0;
    }
    final contour = raw.sublist(starts[s], starts[s + 1]);
    // 短い音節は実際に短く発音される。お手本の点数配分と揃えないと、
    // 「長さを見込んだお手本」を検証したことにならない。
    final syllableFrames = framesOf(s);
    for (var f = 0; f < syllableFrames; f++) {
      // 音節の頭は子音で、ピッチが取れない。声は出ていないが時間は進むので、
      // declination の進み具合には数える。
      if (f < unvoicedOnsetFrames) {
        frames.add(null);
        framesInSegment++;
        continue;
      }
      final t = syllableFrames == 1 ? 0.0 : f / (syllableFrames - 1);
      final scale = contourScaleBySyllable[s] ?? 1.0;
      final mean = contour.reduce((a, b) => a + b) / contour.length;
      final scaled = mean + (sampleContour(contour, t) - mean) * scale;
      // 声調の引っ張られ（carryover）。直前の音節が終わった高さから入るため、
      // 音節の入りが直前に寄り、時間とともに本来の高さへ戻る。
      // 下降声（低く終わる）の直後の高平声で最も大きく出る。
      var carried = 0.0;
      if (carryoverStrength > 0 && s > 0) {
        final previous = raw.sublist(starts[s - 1], starts[s]);
        final gap = previous.last - contour.first;
        final decay = carryoverReach <= 0
            ? 0.0
            : math.max(0.0, 1 - t / carryoverReach);
        carried = carryoverStrength * gap * decay;
      }
      // 音節まるごとの上下（形は保ったまま高さだけずれた発話）。
      final offset = levelOffsetBySyllable[s] ?? 0.0;
      final z = (scaled + carried + offset) * flatten;
      // 話者の declination。節の頭で高く、終わりで低い。
      final segmentTotal = segmentFrames[segment];
      final progress =
          segmentTotal <= 1 ? 0.5 : framesInSegment / (segmentTotal - 1);
      // flatten は発話全体の抑揚を潰すので、declination と末尾の下がりにも掛ける。
      final drift = declination * (progress - 0.5) * flatten;
      // 節末の追加の下がり。節末は音節全体が一定量下がる（傾きではない）。
      // 文末と文中の節末は別の量（後者は話者によって下がらないこともある）。
      final atSegmentEnd = s == segments[segment + 1] - 1;
      final drop = segment + 2 == segments.length
          ? finalLowering
          : clauseFinalLowering;
      final finalDrop = atSegmentEnd ? drop * flatten : 0.0;
      framesInSegment++;
      final semitone =
          medianSemitone + (z - drift - finalDrop) * halfRangeSemitone;
      frames.add(kSemitoneRefHz * math.pow(2, semitone / 12).toDouble());
    }
  }
  return frames;
}
