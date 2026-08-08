// =============================================================================
// tone_contour.dart
// タイ語5声調の標準ピッチカーブ（お手本）。
//
// 縦軸は話者の声域で正規化した無次元の値（0＝声の中心、±1＝声域の端）で、
// speaker_range.dart の正規化と同じ尺度に載せてある。横軸は音節内の正規化時間を
// [kContourResolution] 点でサンプルしたもの。
//
// これにより、例文の音節列（ThaiToneAnalyzer が判定した声調の列）から
// お手本カーブが機械的に組み立てられる。録音済みのお手本音声は要らず、
// 生成済みの全例文にそのまま適用できる。
//
// カーブの値は標準タイ語の記述音声学に基づく近似で、最終的には実データで
// 調整する前提の定数。
// =============================================================================

import 'speaker_range.dart';
import '../thai_tone_analyzer.dart';

/// 1音節あたりのサンプル点数。
const int kContourResolution = 10;

/// 声調ごとの標準ピッチカーブ。
///
/// - 中平声: 中央付近で平坦、末尾がわずかに下降
/// - 低平声: 低い位置で平坦〜わずかに下降
/// - 下降声: 少し上がってから急降下。ピークは前寄り
/// - 高平声: 上昇しながら高い位置へ。最後にわずかに落ちる
/// - 上昇声: 低く始まり、いったん沈んでから上昇
const Map<ThaiTone, List<double>> kToneContours = {
  ThaiTone.mid: [0.05, 0.05, 0.05, 0.04, 0.02, 0.00, -0.03, -0.07, -0.12, -0.18],
  ThaiTone.low: [
    -0.45, -0.48, -0.52, -0.56, -0.60, -0.64, -0.68, -0.72, -0.76, -0.80,
  ],
  ThaiTone.falling: [
    0.55, 0.75, 0.85, 0.85, 0.75, 0.55, 0.25, -0.10, -0.45, -0.70,
  ],
  ThaiTone.high: [0.25, 0.35, 0.45, 0.55, 0.65, 0.75, 0.85, 0.90, 0.85, 0.70],
  ThaiTone.rising: [
    -0.35, -0.48, -0.55, -0.58, -0.55, -0.45, -0.25, 0.05, 0.35, 0.60,
  ],
  // 声調が判定できなかった音節。整列のために形は必要なので中平声の形を借りるが、
  // 採点からは除外する（ToneVerdict.unscored）。
  ThaiTone.unknown: [
    0.05, 0.05, 0.05, 0.04, 0.02, 0.00, -0.03, -0.07, -0.12, -0.18,
  ],
};

/// [Syllable.tone] が持つ文字列表現から [ThaiTone] へ戻す。
///
/// サーバー由来・SQLite由来の音節データは声調を文字列で持っているため、
/// お手本カーブを引くには一度 enum に戻す必要がある。
/// 未知の文字列は [ThaiTone.unknown]（採点対象外）に落とす。
ThaiTone toneFromName(String name) {
  switch (name) {
    case 'mid':
      return ThaiTone.mid;
    case 'low':
      return ThaiTone.low;
    case 'falling':
      return ThaiTone.falling;
    case 'high':
      return ThaiTone.high;
    case 'rising':
      return ThaiTone.rising;
    default:
      return ThaiTone.unknown;
  }
}

/// 例文全体のお手本カーブ。
class ReferenceContour {
  /// 全音節を連結した点列。長さは `tones.length * kContourResolution`。
  ///
  /// 録音側と同じ尺度に載せるため、[normalizeSelf] で中央値0・半広がり1に
  /// 正規化済み。[kToneContours] の生の値ではない。
  final List<double> values;

  /// 音節ごとの声調（`values` と同じ順）。
  final List<ThaiTone> tones;

  const ReferenceContour({required this.values, required this.tones});

  /// 音節の数。
  int get syllableCount => tones.length;

  /// 連結後の点の添字から、それが属する音節の添字を返す。
  int syllableIndexOfPoint(int pointIndex) => pointIndex ~/ kContourResolution;

  /// 音節の声調列からお手本カーブを組み立てる。
  ///
  /// 連結したあと、録音側と同じ手順で正規化する。文ごとに声調の混ざり方が
  /// 違うので、正規化は「この文を正しく読んだときの広がり」を基準にすることになる。
  /// 低い声調ばかりの文で録音側の広がりだけが引き伸ばされる、といった不整合を防げる。
  factory ReferenceContour.fromTones(List<ThaiTone> tones) {
    final raw = <double>[];
    for (final tone in tones) {
      raw.addAll(kToneContours[tone] ?? kToneContours[ThaiTone.unknown]!);
    }
    return ReferenceContour(values: normalizeSelf(raw), tones: tones);
  }
}
