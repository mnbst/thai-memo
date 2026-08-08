// =============================================================================
// speaker_range.dart
// 話者の声域推定と、それに基づくピッチの正規化。
//
// タイ語の声調は絶対音高ではなく「その話者の声域内での相対的な高さ」で決まる。
// 男性と女性では実際の周波数がまるで違うのに、同じ声調として通じるのはこのため。
// したがって採点の前に、録音を話者の声域で正規化する必要がある。
//
// ただし事前キャリブレーション（「あー」と発声させる工程）は要らない。
// 例文には複数の声調が混ざるため、**録音そのものから声域が推定できる**。
// 発話が短い・平坦な声調ばかりで推定が不安定なときのために、過去の録音から
// 得た声域を [SpeakerPitchProfile] として蓄積し、フォールバックに使う。
// =============================================================================

import 'dart:math' as math;

/// 声域の推定に必要な最小の有声フレーム数。
///
/// ホップ10msなら30フレーム＝0.3秒ぶんの有声区間。これを下回る録音からは
/// 声域を推定しない。
const int kMinVoicedFramesForRange = 30;

/// 声域として認める最小の幅（セミトーン）。
///
/// 平坦な声調ばかりを含む発話ではレンジが潰れ、正規化すると微小な揺れが
/// 増幅されてしまう。下回った場合は推定失敗として扱い、蓄積プロファイルに委ねる。
const double kMinRangeSemitone = 2.0;

/// 正規化後の値を丸める範囲。
///
/// 裏返った声や検出誤りが極端な値になって採点を壊さないようにする。
const double kNormalizedClamp = 1.5;

/// 声域プロファイルの移動平均でさかのぼる最大の試行数。
///
/// 上限を置かないと古い録音に引きずられ、声の調子の変化に追従しなくなる。
const int kProfileMaxSamples = 20;

/// 話者の声域。
class SpeakerRange {
  /// 声の中心（セミトーン）。
  final double medianSemitone;

  /// 声域の幅（セミトーン）。第5〜第95パーセンタイルの差。
  final double rangeSemitone;

  const SpeakerRange({
    required this.medianSemitone,
    required this.rangeSemitone,
  });

  @override
  String toString() =>
      'SpeakerRange(median: ${medianSemitone.toStringAsFixed(2)}, '
      'range: ${rangeSemitone.toStringAsFixed(2)})';
}

/// 録音を跨いで蓄積する声域プロファイル。
///
/// UIには出さない暗黙のキャリブレーション。使うほど推定が安定する。
/// 単語1語だけを練習するフェーズ2では、1発話から声域を取れないため
/// これが前提になる。
class SpeakerPitchProfile {
  final SpeakerRange range;

  /// 移動平均に反映済みの試行数。[kProfileMaxSamples] で頭打ちにする。
  final int sampleCount;

  const SpeakerPitchProfile({
    required this.range,
    required this.sampleCount,
  });

  /// 新しい推定値を移動平均で取り込む。
  SpeakerPitchProfile merge(SpeakerRange fresh) {
    final n = math.min(sampleCount, kProfileMaxSamples);
    return SpeakerPitchProfile(
      range: SpeakerRange(
        medianSemitone:
            (range.medianSemitone * n + fresh.medianSemitone) / (n + 1),
        rangeSemitone:
            (range.rangeSemitone * n + fresh.rangeSemitone) / (n + 1),
      ),
      sampleCount: math.min(sampleCount + 1, kProfileMaxSamples),
    );
  }
}

/// ソート済みでない数値列のパーセンタイルを線形補間で求める。
double percentile(List<double> sorted, double p) {
  assert(sorted.isNotEmpty);
  if (sorted.length == 1) return sorted.first;
  final pos = p * (sorted.length - 1);
  final lower = pos.floor();
  final upper = math.min(lower + 1, sorted.length - 1);
  final frac = pos - lower;
  return sorted[lower] * (1 - frac) + sorted[upper] * frac;
}

/// 1回の発話から声域を推定する。
///
/// 外れ値に強い第5／第95パーセンタイルで幅を取る。最大値と最小値を使うと
/// 検出誤りの1フレームで声域が倍になる。
///
/// 有声フレームが足りない、または幅が狭すぎる場合は null を返す。
/// 呼び出し側は蓄積プロファイルにフォールバックする。
SpeakerRange? estimateSpeakerRange(
  List<double?> semitones, {
  int minVoicedFrames = kMinVoicedFramesForRange,
  double minRangeSemitone = kMinRangeSemitone,
}) {
  final voiced = semitones.whereType<double>().toList()..sort();
  if (voiced.length < minVoicedFrames) return null;

  final range = percentile(voiced, 0.95) - percentile(voiced, 0.05);
  if (range < minRangeSemitone) return null;

  return SpeakerRange(
    medianSemitone: percentile(voiced, 0.5),
    rangeSemitone: range,
  );
}

/// セミトーン系列を話者の声域で正規化する。
///
/// 中心を0、声域の端を概ね ±1 にした無次元の値へ移す。お手本カーブも
/// 同じ尺度で定義してあるので、そのまま比較できる。
List<double?> normalizeToSpeakerRange(
  List<double?> semitones,
  SpeakerRange range,
) {
  final half = range.rangeSemitone / 2;
  if (half <= 0) return List<double?>.filled(semitones.length, null);

  return semitones.map((v) {
    if (v == null) return null;
    final z = (v - range.medianSemitone) / half;
    return z.clamp(-kNormalizedClamp, kNormalizedClamp);
  }).toList();
}

/// 数値列を自分自身の中央値と広がりで正規化する（中央値0・半広がり1）。
///
/// [normalizeToSpeakerRange] が録音に対して行うのと同じ変換を、任意の系列に
/// 適用するためのもの。お手本カーブ側にも同じ変換を掛けて、両者を同一の尺度に
/// 載せるために使う。
///
/// これを省くと、お手本カーブの「±1＝声域の端」という取り決めと、録音側の
/// パーセンタイル正規化の尺度が一致しない。実際の声調カーブは声域の端まで
/// 振り切らないため、正しく発音しても録音側の値が2割ほど大きく出て、
/// 系統的な誤差として採点に乗ってしまう。
///
/// [minHalfSpread] は、全音節が同じ声調の文などで広がりがほぼ0になったときに
/// 微小な差が増幅されるのを防ぐ下限。
List<double> normalizeSelf(
  List<double> values, {
  double minHalfSpread = 0.2,
}) {
  if (values.isEmpty) return const [];

  final sorted = [...values]..sort();
  final median = percentile(sorted, 0.5);
  final halfSpread = math.max(
    (percentile(sorted, 0.95) - percentile(sorted, 0.05)) / 2,
    minHalfSpread,
  );
  return values.map((v) => (v - median) / halfSpread).toList();
}

/// 今回の録音と蓄積プロファイルから、実際に使う声域を決める。
///
/// 今回の推定が取れればそれを使い、取れなければ蓄積プロファイルに委ねる。
/// どちらも無ければ null（採点不能）。
SpeakerRange? resolveSpeakerRange({
  required List<double?> semitones,
  SpeakerPitchProfile? profile,
}) =>
    estimateSpeakerRange(semitones) ?? profile?.range;
