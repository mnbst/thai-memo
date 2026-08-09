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

/// 長い音節1つぶんのサンプル点数。
const int kContourResolution = 10;

/// 短母音＋生音節（กัน, นั้น）1つぶんのサンプル点数。
///
/// 短母音だが末子音が鳴り続けるので、閉鎖音で切られる死音節ほどは短くない。
/// 実機で บรร（บรรยากาศ の第1音節）が発話の 6.4%／7.2%（予算 8.7%）に出ており、
/// この帯で合っている。
const int kHalfLongSyllablePoints = 8;

/// 短母音＋死音節（รัก, จะ）1つぶんのサンプル点数。
///
/// お手本の点数は**そのままお手本側の時間の割り当て**になる。全音節を同じ点数に
/// すると「どの音節も発話時間の等分」と主張することになり、DTW の帯（対角線から
/// 6%）が実際の長さの偏りを吸収しきれない。
///
/// 実機で、10フレームしか無い音節の境界が**帯の限界にぴったり張り付いた**
/// （お手本の位置 0.200 に対し録音の位置 0.141、差 0.059 対 許容 0.06）。
/// DTW はもっと動きたかったのに動けず、隣の音節が 40 フレームを飲み込んで、
/// その2音節だけが誤判定になった。
///
/// タイ語の母音の長短は**音韻的な対立**（語が変わる）で、話者や文脈で消えない。
/// 長短比はおよそ 1:1.5〜2 とされるので、10 に対して 6 を当てる。
/// 声調による長さの違いや文末の伸びは、観測できていないので入れない。
const int kShortSyllablePoints = 6;

/// 母音の長短と音節の種類から、時間の取り分（点数）を決める。
///
/// **「短母音 または 死音節」でまとめてはいけない。** 長母音に閉鎖音が付いた
/// だけの音節（มาก, พูด）は長い。実機で、この判定で「短い」とされた音節が
/// 実際には発話の 16%（予算は 7%）を占め、そのずれで隣の音節の境界が
/// DTW の帯に張り付いた。
///
/// 声調の**振れ幅**を縮めるかどうか（[kShortSyllableDamping]）とは別の判断。
/// あちらは「動きを出しきる時間があるか」で、閉鎖音で切られる死音節は
/// 長母音でも当てはまる。長さと、動きの完了は別物。
int syllablePointsFor({required bool shortVowel, required bool dead}) {
  if (!shortVowel) return kContourResolution;
  return dead ? kShortSyllablePoints : kHalfLongSyllablePoints;
}

/// 音節ごとのサンプル点数。[points] を渡さない場合は全音節を長母音として扱う。
List<int> syllablePointCounts(int syllableCount, List<int>? points) =>
    List.generate(
      syllableCount,
      (i) => (points != null && i < points.length)
          ? points[i]
          : kContourResolution,
    );

/// カーブを正規化時間 [t]（0..1）で線形補間する。
double sampleContourAt(List<double> contour, double t) {
  final position = (t * (contour.length - 1)).clamp(0, contour.length - 1);
  final lower = position.floor();
  final upper = lower + 1 < contour.length ? lower + 1 : contour.length - 1;
  final fraction = position - lower;
  return contour[lower] * (1 - fraction) + contour[upper] * fraction;
}

/// [contour] を [length] 点に張り直す。
List<double> resampleContour(List<double> contour, int length) {
  if (length == contour.length) return [...contour];
  return List.generate(
    length,
    (i) => sampleContourAt(contour, length == 1 ? 0.5 : i / (length - 1)),
  );
}

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

/// 実際の発話で、文の頭から終わりまでにピッチが下がる量（正規化前の単位）。
///
/// declination と呼ばれる現象で、話者が意図してやっているわけではない。
/// 放置すると**文末に近い音節ほど理論値より低く出て、レベル誤差として不当に
/// 罰せられる**。文末の丁寧語尾（ครับ / ค่ะ）は毎回この位置に来るため、
/// 影響が常に同じ語へ集中する。
///
/// **正規化の前に足してはいけない。** 傾きのぶん分母が膨らみ、声調どうしの
/// 高さの差が縮んで、平坦声調の取り違えを見逃すようになる（実測で
/// 中平→低平 のレベル誤差が 0.562 → 0.457 に落ちた）。正規化を済ませてから足す。
///
/// 録音側から推定して取り除く方法も試したが、6音節程度の文では推定した傾きが
/// 先頭・末尾の音節の声調そのものを吸収してしまい、さらに悪化した（同 0.051）。
/// 位置で決まる既知の量として、お手本側に持たせるのが正しい。
const double kDeclinationRange = 0.5;

/// 発話の最後の音節で、さらに下がる量（正規化後の単位）。
///
/// declination（文全体にかかる直線的な下がり）とは別に、発話末では追加で
/// ピッチが落ちる（final lowering）。直線の傾きだけでは末尾の下がりを見込めず、
/// **末尾の語だけが毎回「低すぎる」と判定される**。
///
/// 文末の丁寧語尾（ครับ / ค่ะ）は必ずこの位置に来るので、影響が同じ語へ集中する。
///
/// **音節の中で傾きとして当ててはいけない。** 下降声の下がりに上乗せされて
/// お手本が急降下し、到達できない形になる。位置のずれ（一定の下げ幅）として
/// 当てる。採点で見るのは形と前後の対比なので、位置として当てれば
/// 対比だけに効いて形は歪まない。
const double kFinalLoweringRange = 0.35;

/// 下降声が連続したときに、2つ目の下降幅を縮める割合。
///
/// 下降声は高く始まって急に落ちる。直前も下降声だと低い位置で終わっているため、
/// 高い開始位置まで戻りきれず、**下降の幅が実際には小さくなる**。
/// お手本を毎回フルの下降で描くと、連続した2つ目が必ず「足りない」と判定される。
///
/// 縮めるのは2つ目だけ。1つ目は前の音節に引きずられないので変えない。
const double kRepeatedFallingDamping = 0.75;

/// 音節が短くて声調の形を出しきれないときに、振れ幅を縮める割合。
///
/// 短母音や死音節では時間が足りず、上昇声・下降声でも動きが完了しない
/// （tonal undershoot）。お手本をフルの動きで描くと、正しく発音していても
/// 「動きが足りない」と判定されてしまう。
const double kShortSyllableDamping = 0.6;

/// カーブの振れ幅を平均のまわりで縮める。
List<double> _damped(List<double> contour, double factor) {
  final mean = contour.reduce((a, b) => a + b) / contour.length;
  return contour.map((v) => mean + (v - mean) * factor).toList();
}

/// 声調の並びから、正規化前のお手本カーブを組み立てる。
///
/// 声調そのものの形に、下降声の連続による下降幅の縮小だけを掛ける。
/// declination はここでは足さない（[kDeclinationRange] の説明を参照）。
///
/// 合成音声を作るテスト側からも使う。話者も同じ影響を受けるので、
/// お手本と同じ変形を掛けないと比較にならない。
List<double> buildRawContour(
  List<ThaiTone> tones, {
  List<bool>? shortSyllables,
  List<int>? syllablePoints,
}) {
  final counts = syllablePointCounts(tones.length, syllablePoints);
  final values = <double>[];
  for (var i = 0; i < tones.length; i++) {
    final tone = tones[i];
    var contour = kToneContours[tone] ?? kToneContours[ThaiTone.unknown]!;
    if (tone == ThaiTone.falling &&
        i > 0 &&
        tones[i - 1] == ThaiTone.falling) {
      contour = _damped(contour, kRepeatedFallingDamping);
    }
    if (shortSyllables != null &&
        i < shortSyllables.length &&
        shortSyllables[i]) {
      contour = _damped(contour, kShortSyllableDamping);
    }
    // 点数＝お手本側の時間の割り当て。短い音節は短く置く。
    values.addAll(resampleContour(contour, counts[i]));
  }

  return values;
}

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
  /// 全音節を連結した点列。
  ///
  /// 録音側と同じ尺度に載せるため、[normalizeSelf] で中央値0・半広がり1に
  /// 正規化済み。[kToneContours] の生の値ではない。
  ///
  /// **音節の長さは一定ではない**（[syllablePointCounts]）。点の添字から音節を
  /// 求めるときは必ず [syllableIndexOfPoint] を使うこと。
  final List<double> values;

  /// 音節ごとの声調（`values` と同じ順）。
  final List<ThaiTone> tones;

  /// 音節 i の点が始まる添字。長さは `tones.length + 1` で、末尾は全体の長さ。
  final List<int> starts;

  const ReferenceContour({
    required this.values,
    required this.tones,
    required this.starts,
  });

  /// 音節の数。
  int get syllableCount => tones.length;

  /// 連結後の点の添字から、それが属する音節の添字を返す。
  int syllableIndexOfPoint(int pointIndex) {
    for (var i = syllableCount - 1; i >= 0; i--) {
      if (pointIndex >= starts[i]) return i;
    }
    return 0;
  }

  /// 音節 [index] に割り当てた点数（＝お手本側の時間の取り分）。
  int pointsOf(int index) => starts[index + 1] - starts[index];

  /// その点が音節の中心（正規化時間の中央60%）にあるか。
  ///
  /// 声調の高さは**音節の中心で測る**のが定石で、入り際・抜け際は隣の音節から
  /// 移る途中なので、その音節の高さを表さない。
  bool isCenterPoint(int pointIndex) {
    final syllable = syllableIndexOfPoint(pointIndex);
    final length = starts[syllable + 1] - starts[syllable];
    final margin = (length * 0.2).round();
    final position = pointIndex - starts[syllable];
    return position >= margin && position < length - margin;
  }

  /// 音節 [index] の高さ（中央60%の中央値）。
  ///
  /// **対応づいた点だけから採ってはいけない。** 下降声・上昇声はカーブが声域を
  /// 大きく縦断するので、DTW でどの点が対応づいたかによって中央値が跳ぶ。
  /// 位置で決めれば、同じ文なら必ず同じ値になる。
  double centerLevel(int index) {
    final length = starts[index + 1] - starts[index];
    final margin = (length * 0.2).round();
    final start = starts[index] + margin;
    final end = starts[index + 1] - margin;
    if (start >= end || end > values.length) return 0;

    final core = values.sublist(start, end)..sort();
    final middle = core.length ~/ 2;
    if (core.length.isOdd) return core[middle];
    return (core[middle - 1] + core[middle]) / 2;
  }

  /// その点が音節の端（前後 [fraction] ずつ）にあるか。
  ///
  /// 子音の無声区間はここに来る。**中央より広く取る**（実測で 120ms の
  /// 無声子音は音節の4割を占め、25%では収まらなかった）。
  bool isEdgePoint(int pointIndex, double fraction) {
    final syllable = syllableIndexOfPoint(pointIndex);
    final length = starts[syllable + 1] - starts[syllable];
    final edge = (length * fraction).round().clamp(1, length);
    final position = pointIndex - starts[syllable];
    return position < edge || position >= length - edge;
  }

  /// その点が音節の入り際（正規化時間の前25%）にあるか。
  ///
  /// 声調はここから始まる。**上昇声と高平声を分けているのはこの位置**
  /// （上昇声は直前より低く入り、高平声は高く入る）。
  bool isHeadPoint(int pointIndex) {
    final syllable = syllableIndexOfPoint(pointIndex);
    final length = starts[syllable + 1] - starts[syllable];
    final head = (length * 0.25).round().clamp(1, length);
    return pointIndex - starts[syllable] < head;
  }

  /// その点が音節の末尾（正規化時間の後ろ25%）にあるか。
  ///
  /// 次の音節に入るときの基準は、直前の音節の**中心ではなく終わり際**。人は
  /// 直前が終わった高さから次の音節に入る。
  bool isTailPoint(int pointIndex) {
    final syllable = syllableIndexOfPoint(pointIndex);
    final length = starts[syllable + 1] - starts[syllable];
    final tail = (length * 0.25).round().clamp(1, length);
    final position = pointIndex - starts[syllable];
    return position >= length - tail;
  }

  /// 音節 [index] の終わり際の高さ（後ろ25%の中央値）。
  ///
  /// [centerLevel] と同じく、**位置で決めて対応づけからは採らない**。
  double tailLevel(int index) {
    final length = starts[index + 1] - starts[index];
    final tail = (length * 0.25).round().clamp(1, length);
    final start = starts[index + 1] - tail;
    final end = starts[index + 1];
    if (start >= end || end > values.length) return 0;

    final core = values.sublist(start, end)..sort();
    final middle = core.length ~/ 2;
    if (core.length.isOdd) return core[middle];
    return (core[middle - 1] + core[middle]) / 2;
  }

  /// 音節の声調列からお手本カーブを組み立てる。
  ///
  /// 連結したあと、録音側と同じ手順で正規化する。文ごとに声調の混ざり方が
  /// 違うので、正規化は「この文を正しく読んだときの広がり」を基準にすることになる。
  /// 低い声調ばかりの文で録音側の広がりだけが引き伸ばされる、といった不整合を防げる。
  factory ReferenceContour.fromTones(
    List<ThaiTone> tones, {
    List<bool>? shortSyllables,
    List<int>? syllablePoints,
  }) {
    // 正規化は声調の中身だけから決める。declination を含めると分母が膨らみ、
    // 声調どうしの高さの差が縮んでしまう。
    final values = normalizeSelf(
      buildRawContour(
        tones,
        shortSyllables: shortSyllables,
        syllablePoints: syllablePoints,
      ),
    );

    final counts = syllablePointCounts(tones.length, syllablePoints);
    final starts = <int>[0];
    for (final count in counts) {
      starts.add(starts.last + count);
    }

    // 正規化を済ませてから declination の傾きを足す。
    final total = values.length;
    if (total >= 2) {
      for (var k = 0; k < total; k++) {
        values[k] -= kDeclinationRange * (k / (total - 1) - 0.5);
      }

      // 発話末の追加の下がり。音節全体を一定量だけ下げる。
      // 傾きとして当てると下降声の下がりに上乗せされて形が歪む。
      final lastStart = starts[tones.length - 1];
      for (var k = lastStart; k < total; k++) {
        values[k] -= kFinalLoweringRange;
      }
    }

    // **足したあとで、もう一度正規化する。** 録音側は declination も発話末の
    // 下がりも含んだ状態で声域を推定している。お手本だけ足す前の分布で
    // 正規化すると、2つの尺度がずれて全音節に共通の高さのずれが出る。
    // 合成音声（正しい発話）で、音節の長さが揃っていないだけで
    // 高さのずれが 0.05 から 0.45 に跳んだ。
    final rescaled = normalizeSelf(values);
    return ReferenceContour(values: rescaled, tones: tones, starts: starts);
  }
}
