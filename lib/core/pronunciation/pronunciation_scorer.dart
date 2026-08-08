// =============================================================================
// pronunciation_scorer.dart
// 対応づけ済みのお手本カーブと録音ピッチから、音節ごとの声調の当たり外れを出す。
//
// 採点は2軸で行う。
//   - レベル誤差: 声域内での高さが合っているか
//   - 形状誤差:   上がる／下がる／平ら の動きが合っているか
//
// **形状だけで判定してはいけない。** タイ語5声調のうち中平声・低平声・高平声は
// いずれも平坦で、違いは声域内の高さだけにある。推移のみを見るとこの3つが
// 区別できない。
//
// 閾値は緩めに置いてある。判定が厳しすぎる発音練習は誰も続けられないため、
// 迷ったら甘い側に倒す。実データでの調整前提の定数。
// =============================================================================

import 'dtw.dart';
import 'tone_contour.dart';
import '../thai_tone_analyzer.dart';

/// レベル誤差の許容値（正規化済みの単位。1.0 が声域の半分）。
const double kLevelErrorThreshold = 0.45;

/// 形状誤差（傾きの差）の許容値。
const double kShapeErrorThreshold = 0.55;

/// 音節ごとの判定。
enum ToneVerdict {
  /// 高さも動きも合っている。
  correct,

  /// 片方だけ合っている。「惜しい」として返す。
  ///
  /// 2値にすると挫折するため、この段階を必ず設ける。
  close,

  /// どちらも外れている。
  wrong,

  /// 採点対象外（声調が判定できない音節、または対応する録音が無い）。
  unscored,
}

/// 1音節ぶんの採点結果。
class SyllableScore {
  final int syllableIndex;
  final ThaiTone tone;
  final ToneVerdict verdict;

  /// 声域内の高さのずれ。[ToneVerdict.unscored] のときは 0。
  final double levelError;

  /// 動き（傾き）のずれ。[ToneVerdict.unscored] のときは 0。
  final double shapeError;

  /// この音節のお手本カーブ（正規化済み）。カーブ描画に使う。
  final List<double> referenceValues;

  /// この音節に対応づいた録音側のピッチ（正規化済み）。カーブ描画に使う。
  final List<double> queryValues;

  const SyllableScore({
    required this.syllableIndex,
    required this.tone,
    required this.verdict,
    this.levelError = 0,
    this.shapeError = 0,
    this.referenceValues = const [],
    this.queryValues = const [],
  });
}

/// 正規化時間 0..1 に対する最小二乗の傾き。
///
/// 始点と終点の差ではなく回帰直線を使う。端の1点が検出誤りだったときに
/// 判定が反転するのを避けるため。
double contourSlope(List<double> values) {
  final n = values.length;
  if (n < 2) return 0;

  var sumT = 0.0, sumV = 0.0, sumTT = 0.0, sumTV = 0.0;
  for (var i = 0; i < n; i++) {
    final t = i / (n - 1);
    sumT += t;
    sumV += values[i];
    sumTT += t * t;
    sumTV += t * values[i];
  }
  final denominator = n * sumTT - sumT * sumT;
  if (denominator.abs() < 1e-9) return 0;
  return (n * sumTV - sumT * sumV) / denominator;
}

double _mean(List<double> values) {
  if (values.isEmpty) return 0;
  var sum = 0.0;
  for (final v in values) {
    sum += v;
  }
  return sum / values.length;
}

/// DTW の経路をもとに、音節ごとの採点を行う。
///
/// [queryZ] は正規化済み（無声フレームを除いた）録音ピッチ。
List<SyllableScore> scoreSyllables({
  required ReferenceContour reference,
  required List<double> queryZ,
  required List<DtwPathPoint> path,
  double levelThreshold = kLevelErrorThreshold,
  double shapeThreshold = kShapeErrorThreshold,
}) {
  // 音節ごとに、対応づいた録音側の添字を集める。
  // 1つの録音フレームが複数のお手本点に対応することがあるため重複を除く。
  final queryIndicesPerSyllable =
      List.generate(reference.syllableCount, (_) => <int>{});
  for (final point in path) {
    final syllable = reference.syllableIndexOfPoint(point.refIndex);
    if (syllable < reference.syllableCount) {
      queryIndicesPerSyllable[syllable].add(point.queryIndex);
    }
  }

  final scores = <SyllableScore>[];
  for (var s = 0; s < reference.syllableCount; s++) {
    final tone = reference.tones[s];

    final refValues = reference.values.sublist(
      s * kContourResolution,
      (s + 1) * kContourResolution,
    );
    final queryIndices = queryIndicesPerSyllable[s].toList()..sort();
    final queryValues = queryIndices.map((i) => queryZ[i]).toList();

    // 声調が不明な音節と、録音が対応しなかった音節は採点しない。
    if (tone == ThaiTone.unknown || queryValues.isEmpty) {
      scores.add(SyllableScore(
        syllableIndex: s,
        tone: tone,
        verdict: ToneVerdict.unscored,
        referenceValues: refValues,
        queryValues: queryValues,
      ));
      continue;
    }

    final levelError = (_mean(queryValues) - _mean(refValues)).abs();
    final levelOk = levelError <= levelThreshold;

    // 点が1つしかないと傾きが定義できない。高さだけで判断し、
    // 最良でも「惜しい」に留める（動きを確かめられていないため）。
    if (queryValues.length < 2) {
      scores.add(SyllableScore(
        syllableIndex: s,
        tone: tone,
        verdict: levelOk ? ToneVerdict.close : ToneVerdict.wrong,
        levelError: levelError,
        referenceValues: refValues,
        queryValues: queryValues,
      ));
      continue;
    }

    final shapeError =
        (contourSlope(queryValues) - contourSlope(refValues)).abs();
    final shapeOk = shapeError <= shapeThreshold;

    final ToneVerdict verdict;
    if (levelOk && shapeOk) {
      verdict = ToneVerdict.correct;
    } else if (levelOk || shapeOk) {
      verdict = ToneVerdict.close;
    } else {
      verdict = ToneVerdict.wrong;
    }

    scores.add(SyllableScore(
      syllableIndex: s,
      tone: tone,
      verdict: verdict,
      levelError: levelError,
      shapeError: shapeError,
      referenceValues: refValues,
      queryValues: queryValues,
    ));
  }

  return scores;
}

/// 音節ごとの判定から全体スコア（0〜100）を出す。
///
/// 「惜しい」を半分として数える。採点対象の音節が無ければ 0。
double overallScoreOf(List<SyllableScore> scores) {
  final scored =
      scores.where((s) => s.verdict != ToneVerdict.unscored).toList();
  if (scored.isEmpty) return 0;

  var total = 0.0;
  for (final s in scored) {
    switch (s.verdict) {
      case ToneVerdict.correct:
        total += 1;
      case ToneVerdict.close:
        total += 0.5;
      case ToneVerdict.wrong:
      case ToneVerdict.unscored:
        break;
    }
  }
  return total / scored.length * 100;
}
