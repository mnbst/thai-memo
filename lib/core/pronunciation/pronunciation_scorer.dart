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

import 'dart:math' as math;

import 'dtw.dart';
import 'tone_contour.dart';
import '../thai_tone_analyzer.dart';

// 判定は2つで行う。
//   - 形　　: その音節の中でピッチがどう動いたか（上がる／下がる／平ら）
//   - つながり: 直前の音節との段差
//
// **声域内の絶対的な高さは採点しない。** 高さは話者・場面・文中の位置で素直に
// 動くので、正しく発音していても弾かれてしまい、練習として続かない。
// 一方、隣との段差は声調の情報を保つ。中平声と低平声のように形が同じで
// 高さだけが違う対立も、隣との段差の変化として捕まえられる。
//
// つながりは**直前の音節との段差だけ**を見る。声調は前から順に聞こえてくるもので、
// 「直前と比べて上がったか下がったか」がそのまま手がかりになる。後ろとの段差は
// 同じ情報を2度数えるだけで、しかも次の音節が誤ったときに巻き添えを増やす。
//
// そのぶん直前が誤ると自分の段差も崩れるので、**自身の高さがほぼ一致していて形も
// 合っているとき**の逃げ道（[kExactLevelEscape]）でそこを守る。
//
// **どちらを根拠にするかは声調で決まる。**
//   下降声・上昇声 → 動きそのものが情報。向きが合っていれば合格（振れ幅は問わない）
//   中平・低平・高平 → どれも平らで形では区別できない。直前との対比だけで判断
//
// 両方を全声調に課すと、「形は合っているのに違います」が出る。声調ごとに
// 情報の乗っている場所が違うので、根拠もそれに合わせる。
//
// 形の判定は**落ちている／上がっている／平ら**の3択まで粗くする。傾きの大きさを
// 比べると、正しい方向に動いていても「振れ幅が足りない」で弾かれてしまい、
// 練習として続かない。実際、正しく高平声を出しても平らに寄るのが普通で、
// お手本の上昇幅を要求するのは無理がある。

// 合成音声での実測（calibration_test.dart が範囲を守る）:
//   正しい発話    : 形状 最大 0.239 / つながり 最大 0.103
//   声調の取り違え: 形状 最小 0.559 / つながり 最小 0.391
//
// 直前が誤った音節は、自分の段差も崩れて見える。「そのつながりが崩れている」のは
// 事実なので、[kExactLevelEscape] で救えない範囲は許容する。
//
// 文頭には比べる相手がいない。そこだけは段差を使わず、ピッチのグラフ
// （形と、声域内の高さ）だけで判断する。

/// 「平ら」とみなす傾きの上限。
///
/// 形は**落ちている／上がっている／平ら**の3つに分けるだけで見る。傾きの大きさを
/// 比べると、正しい方向に動いていても「振れ幅が足りない」で弾かれてしまう。
///
/// この値はタイ語の声調体系とも合う。中平・低平・高平は平ら、下降と上昇だけが
/// 動く声調で、実際の傾きも 中平 -0.29 / 低平 -0.46 / 高平 +0.76 に対し
/// 下降 -1.86 / 上昇 +1.30 とはっきり分かれる。
/// 平らな3つの区別は形ではなく「つながり」（隣との段差）が受け持つ。
const double kFlatSlopeThreshold = 0.8;

/// カーブの形が一致しているとみなす相関の下限。
///
/// 高さの関門（[kContourLevelGate]）と組みで使うので、形の側は粗くてよい。
/// 実機で、下降声が相関 0.45・高さのずれ 0.00 という「形はやや崩れているが
/// 高さは完璧」な発話が落ちた。声調の取り違えは相関が 0.1 以下か負に出るので、
/// この帯には入ってこない。
const double kShapeCorrelationThreshold = 0.4;

/// 形状誤差（傾きの差）。判定には使わず、表示と切り分けのために残す。
const double kShapeErrorThreshold = 0.45;

/// つながり（隣との段差）の誤差の許容値。声調ごとに変える。
///
/// 声調によって、どこに情報が乗っているかが違う。
///
/// - **下降声・上昇声**は動きそのものが情報なので、形が合っていれば足りる。
///   高さの関係は緩めてよい
/// - **中平・低平・高平**は形が同じで高さの関係しか手がかりが無いので、
///   ここは締める必要がある
/// - **高平声**はその中でも実際の発話で下がりやすく（特に文末）、やや緩める
/// 音節の中心で高さを測るようにしてから引き直した値。合成音声での分布は
/// 正しい発話 0.03（無声子音を入れても 0.105）に対し、取り違えは 0.28〜1.12。
///
/// 実機でも確認済み。9音節の発話で、正しく出せていた7音節は 0.020〜0.197 に
/// 収まり、合成音声と同じ範囲に乗った。外れた1音節（高平声を上げそこねた）は
/// 0.828 で、はっきり分かれている。
const Map<ThaiTone, double> kTransitionThresholdByTone = {
  // 下降声・上昇声はふだん形で通るので、この値が効くのは短い音節や
  // 形が測れなかったときだけ。締めると短母音の undershoot を許せなくなる
  // （上昇声を平坦に言った短い音節で 0.434）。
  ThaiTone.falling: 0.45,
  ThaiTone.rising: 0.45,
  ThaiTone.high: 0.40,
  ThaiTone.mid: 0.35,
  ThaiTone.low: 0.35,
};

/// 上の表に無い声調に使う値。
const double kTransitionErrorThreshold = 0.35;

/// 下降声・上昇声を「形が合っている」で通すときに、なお要求する高さの一致。
///
/// 形の一致だけで通していたとき、**上昇声を高平声で発音した誤りが素通りした**
/// （どちらも右上がりなので相関 0.90、しかし高さは 1.03 も違う）。
/// 形は声調の情報の大半を持つが、全部ではない。
///
/// **隣との段差ではなく、その音節自身の高さで見る。** 段差で見ると、直前が誤った
/// ときに巻き添えになる。実機で、末尾の下降声が相関 0.99・高さのずれ 0.04 と
/// 完璧なのに、隣が崩れているだけで落ちた。
///
/// 絶対的な高さは本来は採点しない（話者・場面で素直に動く）。ここでは
/// **明らかに崩れている場合だけを弾く**関門として、合格ラインよりずっと緩く置く。
/// 実機の下降声・上昇声は正しく出せていれば 0.00〜0.31 に収まり、
/// 合成音声での取り違えは 0.71 以上に出る。
const double kContourLevelGate = 0.5;

/// 直前が崩れているときに、その音節自身の高さだけで通す上限。
///
/// つながりは直前との段差だけを見るので、**直前が誤るとこの音節の段差も崩れる**。
/// 実機で、中平声が高さのずれ 0.07・相関 0.99 と完璧なのに、隣が崩れている
/// だけで落ちた。
///
/// このとき段差はこの音節について何も語っていないので、自身の高さで判断する。
/// 絶対的な高さは普段は採点しないため、**ほぼ一致しているときだけ**に限る
/// （形の一致も併せて要求する）。合成音声で最も差の小さい取り違えでも
/// 中平→上昇 が 0.19 だが、そちらは形が合わないので通らない。
const double kExactLevelEscape = 0.35;

/// 直前が当てにならないときに、その音節自身の高さだけで通す上限。
///
/// 直前がずれていれば、段差が崩れていても**原因がどちらの音節かは分からない**。
/// 実機で、高平声を上げそこねた次の低平声が段差 1.501 で誤りにされた。その音節
/// 自身は高さのずれ 0.01・相関 0.98 で、聞けば正しく言えている。
///
/// そこで直前が誤っていたときだけ、自身の高さの許容を広げる。誤りが1つなら
/// 判定に影響しない（誤った音節自身は、その直前が正しいので通常の上限で見る）。
const double kBrokenNeighborEscape = 0.50;

/// 直前との段差が使えないときに、声域内の高さだけで通す上限。
///
/// 文頭には比べる相手がいない。平らな3声調（中平・低平・高平）は形では互いに
/// 区別できないので、ここだけは**声域内の高さそのもの**を根拠にするしかない。
///
/// 高さは話者・場面で素直に動くため普段は採点しないが、録音側もお手本側も
/// 同じ手順で正規化してあり、declination の効かない文頭は**文中で最も高さが
/// 安定している位置**でもある。合成音声では、文頭の取り違えは 0.53〜1.19 に出る。
const double kGraphLevelGate = 0.40;

/// 形（カーブの一致）を判定の根拠にしてよい、実際に声が出ていたフレームの最小数。
///
/// 高さは数フレームでも代表値が出るが、**形はそれでは決まらない**。実機で、
/// 5フレーム（50ms）しか取れなかった下降声が相関 -0.52 と出て弾かれた。
/// 出ていない形を根拠に誤りと言ってはいけない。足りなければつながりで判断する。
const int kMinVoicedFramesForShape = 10;

/// 音節を採点するのに要る、実際に声が出ていたフレームの最小数。
///
/// ホップ10msなので50ms。これを下回る音節は平均も傾きも当てにならない。
/// **測れていないものを採点してはいけない。** 数フレームだけ拾えた音節に
/// 極端な値が出て、隣との段差が壊れる。
const int kMinVoicedFramesPerSyllable = 5;

/// その声調の合格ライン。
///
/// 末尾の音節も途中と同じ扱いで、直前との段差で見る。端だからと合格ラインを
/// 上乗せすると緩すぎになった（中平声を下降声・高平声で発音しても通ってしまった）。
double transitionThresholdFor(ThaiTone tone) =>
    kTransitionThresholdByTone[tone] ?? kTransitionErrorThreshold;

/// 音節ごとの判定。
enum ToneVerdict {
  /// 形かつながり、**どちらかが合っていれば合格**とする。
  ///
  /// 両方を要求すると、正しく発音していても弾かれることが多く練習にならない。
  /// 見逃しは増えるが、続けられるほうを採る。
  correct,

  /// どちらも外れているが、まだ許容の2倍以内。
  close,

  /// どちらも大きく外れている。
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

  /// 直前の音節との段差のずれ。文頭では 0。
  ///
  /// 直前が正しく発音できていなかったときは判定に使わないが、切り分けのために
  /// 値そのものは入れてある。
  final double transitionError;

  /// 採点に使った、この音節の高さ（録音側）。切り分け用。
  final double queryLevel;

  /// 採点に使った、この音節の高さ（お手本側）。切り分け用。
  ///
  /// **[referenceValues] から採り直してはいけない。** 採点は音節内の位置で
  /// 中心を決めているので、対応づいた点から計算し直すと別の値になる。
  final double referenceLevel;

  /// お手本カーブとの形の一致（-1〜1）。比べようがない場合は null。
  final double? shapeCorrelation;

  /// この音節のお手本カーブ（正規化済み）。カーブ描画に使う。
  final List<double> referenceValues;

  /// この音節に対応づいた録音側のピッチ（正規化済み）。カーブ描画に使う。
  final List<double> queryValues;

  /// お手本でこの音節に割り当てた点数（＝お手本側の時間の取り分）。
  ///
  /// DTW の境界はこの取り分のまわりでしか動けないので、実際の長さと食い違って
  /// いないかを見られるようにしておく。
  final int referencePoints;

  /// この音節に対応づいた録音側フレームの範囲（無声フレームを含む）。
  ///
  /// 高さも形も「どのフレームがこの音節か」の上に乗っているので、境界の置かれ方を
  /// 見られるようにしておく。対応づいたフレームが無ければ両方 -1。
  final int queryStart;
  final int queryEnd;

  const SyllableScore({
    required this.syllableIndex,
    required this.tone,
    required this.verdict,
    this.levelError = 0,
    this.shapeError = 0,
    this.transitionError = 0,
    this.queryLevel = 0,
    this.referenceLevel = 0,
    this.shapeCorrelation,
    this.referenceValues = const [],
    this.queryValues = const [],
    this.queryStart = -1,
    this.queryEnd = -1,
    this.referencePoints = 0,
  });
}

/// ピッチの動きの向き。
enum ToneDirection { rising, falling, flat }

/// 動きを持つ声調か（下降声・上昇声）。
///
/// この2つは動きそのものが情報なので、**向きが合っていれば合格**とする。
/// 振れ幅は問わない。短い音節では出しきれないし、正しく発音しても
/// お手本ほど大きくは動かない。
///
/// 残り3つ（中平・低平・高平）はどれも平らで、形では互いに区別できない。
/// そちらは**直前との対比だけ**で判断する（文頭だけは高さそのもの）。
bool isContourTone(ThaiTone tone) =>
    tone == ThaiTone.falling || tone == ThaiTone.rising;

/// 2つのカーブの形がどれだけ一致しているか（-1〜1）。
///
/// 相関係数なので、**位置のずれと振れ幅の違いは自動的に無視される**。
/// 見たいのは「グラフとしての形が同じか」であって、同じ高さで同じ大きさに
/// 動いたかではない。短い音節で振れ幅が足りなくても、形が同じなら 1 に近づく。
///
/// 1 に近い＝同じ形、0 付近＝無関係、-1 に近い＝逆向き。
/// どちらかが平坦（分散がほぼ0）のときは比べようがないので null を返す。
double? curveCorrelation(List<double> a, List<double> b) {
  final n = a.length < b.length ? a.length : b.length;
  if (n < 3) return null;

  final meanA = _mean(a.sublist(0, n));
  final meanB = _mean(b.sublist(0, n));

  var covariance = 0.0;
  var varianceA = 0.0;
  var varianceB = 0.0;
  for (var i = 0; i < n; i++) {
    final da = a[i] - meanA;
    final db = b[i] - meanB;
    covariance += da * db;
    varianceA += da * da;
    varianceB += db * db;
  }
  if (varianceA < 1e-9 || varianceB < 1e-9) return null;

  return covariance / (math.sqrt(varianceA) * math.sqrt(varianceB));
}

/// 傾きを向きに落とす。
ToneDirection directionOf(
  double slope, {
  double flatThreshold = kFlatSlopeThreshold,
}) {
  if (slope > flatThreshold) return ToneDirection.rising;
  if (slope < -flatThreshold) return ToneDirection.falling;
  return ToneDirection.flat;
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

/// 音節の高さを代表する値（位置が使えないときの控え）。
///
/// 端を落として中央値を採る。実測フレームが少ない音節（10フレーム程度）では、
/// 平均を採ると入り際に引っ張られて高さが大きく振れる。同じ発話を2回録って、
/// 同じ音節の段差が 0.53 と 1.42 に振れたことがある。
double _level(List<double> values) {
  if (values.isEmpty) return 0;
  if (values.length < 5) return _median(values);

  // 前後2割ずつを落とす。
  final margin = (values.length * 0.2).round();
  final core = values.sublist(margin, values.length - margin);
  return _median(core.isEmpty ? values : core);
}

double _median(List<double> values) {
  final sorted = [...values]..sort();
  final middle = sorted.length ~/ 2;
  if (sorted.length.isOdd) return sorted[middle];
  return (sorted[middle - 1] + sorted[middle]) / 2;
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
/// [queryZ] は正規化済みの録音ピッチ。[queryVoiced] は各フレームが実際に
/// 声だったか（false は無声区間を補間で埋めたフレーム）。
///
/// **お手本と録音は、対応づいた同じ区間どうしで比べる。** 子音でピッチが取れない
/// 区間があると、録音側は音節の一部しか声が出ていない。お手本の全体と比べると、
/// 隠れた部分（下降声のピークなど）が「出せていない」ことにされてしまう。
/// DTWの経路をそのまま使い、声が出ているフレームとその相手だけを取り出す。
List<SyllableScore> scoreSyllables({
  required ReferenceContour reference,
  required List<double> queryZ,
  required List<bool> queryVoiced,
  required List<DtwPathPoint> path,
  List<bool>? shortSyllables,
}) {
  // 音節ごとに、対応づいた (お手本, 録音) の組を集める。長さが揃うので
  // 傾きも平均もそのまま比べられる。
  final refValues =
      List.generate(reference.syllableCount, (_) => <double>[]);
  final queryValues =
      List.generate(reference.syllableCount, (_) => <double>[]);
  // 音節の中心（お手本の正規化時間で中央60%）に対応づいた録音フレームだけ。
  final centerQuery =
      List.generate(reference.syllableCount, (_) => <double>[]);
  // 対応づいた録音フレームの範囲。無声フレームも含む（境界の位置を見るため）。
  final spanStart = List.filled(reference.syllableCount, -1);
  final spanEnd = List.filled(reference.syllableCount, -1);

  for (final point in path) {
    if (point.queryIndex >= queryVoiced.length) continue;

    final span = reference.syllableIndexOfPoint(point.refIndex);
    if (span < reference.syllableCount) {
      if (spanStart[span] < 0 || point.queryIndex < spanStart[span]) {
        spanStart[span] = point.queryIndex;
      }
      if (point.queryIndex > spanEnd[span]) spanEnd[span] = point.queryIndex;
    }
    // 補間で埋めたフレームは実際の声ではないので採点に使わない。
    // 対応づけ（DTW）には必要だが、当たり外れの根拠にはできない。
    if (!queryVoiced[point.queryIndex]) continue;

    final syllable = reference.syllableIndexOfPoint(point.refIndex);
    if (syllable >= reference.syllableCount) continue;

    refValues[syllable].add(reference.values[point.refIndex]);
    queryValues[syllable].add(queryZ[point.queryIndex]);
    if (reference.isCenterPoint(point.refIndex)) {
      centerQuery[syllable].add(queryZ[point.queryIndex]);
    }
  }

  /// 音節 [s] の高さ（録音側）。
  ///
  /// **お手本の中心に対応づいたフレームだけ**から採る。対応づいた全フレームを
  /// 端から数えて削ると、DTW の対応づけが少し動いただけで「音節のどこを見たか」が
  /// 変わってしまう。位置はお手本側で決めるほうが動かない。
  double queryLevel(int s) {
    final center = centerQuery[s];
    if (center.length >= 3) return _median(center);
    return _level(queryValues[s]);
  }

  /// 音節 [s] の高さ（お手本側）。
  ///
  /// 対応づけとは無関係に、お手本カーブの中心から決める。**対応づいた点だけから
  /// 採ってはいけない。** 下降声・上昇声はカーブが声域を大きく縦断するので、
  /// どの点が対応づいたかで中央値が跳ぶ。同じ文を2回読んだだけで、同じ音節の
  /// お手本の高さが 0.99 と -0.36 に振れたことがある。
  double refLevel(int s) => reference.centerLevel(s);

  /// 音節 [a] から [b] への段差が、お手本からどれだけずれているか。
  /// どちらかに録音が対応していなければ測れない。
  double? transition(int a, int b) {
    // 測れていない音節との段差は当てにならない。
    if (queryValues[a].length < kMinVoicedFramesPerSyllable ||
        queryValues[b].length < kMinVoicedFramesPerSyllable) {
      return null;
    }
    final queryStep = queryLevel(b) - queryLevel(a);
    final refStep = refLevel(b) - refLevel(a);
    return (queryStep - refStep).abs();
  }

  final scores = <SyllableScore>[];
  for (var s = 0; s < reference.syllableCount; s++) {
    final tone = reference.tones[s];

    // 声調が不明な音節と、声がほとんど measure できなかった音節は採点しない。
    if (tone == ThaiTone.unknown ||
        queryValues[s].length < kMinVoicedFramesPerSyllable) {
      scores.add(SyllableScore(
        syllableIndex: s,
        tone: tone,
        verdict: ToneVerdict.unscored,
        queryLevel: queryLevel(s),
        referenceLevel: refLevel(s),
        referenceValues: refValues[s],
        queryValues: queryValues[s],
        queryStart: spanStart[s],
        queryEnd: spanEnd[s],
        referencePoints: reference.pointsOf(s),
      ));
      continue;
    }

    final levelError = (queryLevel(s) - refLevel(s)).abs();

    // **直前との段差だけ**を見る。末尾の音節も途中と同じ扱いで、後ろを見ない。
    //
    // 直前が測れていない（声が拾えなかった）場合は比べようがないので null。
    final incoming = s > 0 ? transition(s - 1, s) : null;
    final transitionError = incoming ?? 0.0;
    // 段差がこの音節について語るのは、**直前がお手本どおりの高さで出ていたとき
    // だけ**。ずれたまま段差だけ合って Correct になった音節は、そのずれを次の
    // 段差へ持ち越す。実機で、高さが 0.45 ずれた下降声（形が合うので Correct）の
    // 次の中平声が、自身の高さのずれ 0.01 なのに段差 0.446 で落とされた。
    //
    // **判定ではなく高さで見る。** Correct は「直前からの段差が合っていた」と
    // いう意味しか持たない。
    final previousReliable = s == 0 ||
        (scores[s - 1].verdict == ToneVerdict.correct &&
            scores[s - 1].levelError <= kExactLevelEscape);
    final transitionThreshold = transitionThresholdFor(tone);
    final linkOk = incoming == null || incoming <= transitionThreshold;

    // 点が1つしかないと傾きが定義できない。つながりだけで判断し、
    // 最良でも「惜しい」に留める（動きを確かめられていないため）。
    if (queryValues[s].length < 2) {
      scores.add(SyllableScore(
        syllableIndex: s,
        tone: tone,
        verdict: linkOk ? ToneVerdict.close : ToneVerdict.wrong,
        levelError: levelError,
        transitionError: transitionError,
        queryLevel: queryLevel(s),
        referenceLevel: refLevel(s),
        referenceValues: refValues[s],
        queryValues: queryValues[s],
        queryStart: spanStart[s],
        queryEnd: spanEnd[s],
        referencePoints: reference.pointsOf(s),
      ));
      continue;
    }

    final querySlope = contourSlope(queryValues[s]);
    final refSlope = contourSlope(refValues[s]);
    final shapeError = (querySlope - refSlope).abs();

    // 短母音・死音節は声調の動きを出しきる時間がない（tonal undershoot）。
    // 形を要求しても出せないので、この音節は隣との高低差だけで判断する。
    final isShort = shortSyllables != null &&
        s < shortSyllables.length &&
        shortSyllables[s];

    // 形はカーブそのものの一致だけで見る。相関なので位置のずれも振れ幅の違いも
    // 無視され、「グラフとして同じ形か」だけが残る。
    //
    // 振れ幅は**問わない**。実測では、形がほぼ一致（corr=0.73〜0.99）していても
    // 振れ幅がお手本の4割ほどしか出ない発話が普通にあり、そこを弾くと練習にならない。
    //
    // この代償として、**下降声を中平声で発音した場合を見逃す**（どちらも
    // 右下がりの曲線なので相関は高い）。実測の「弱い下降」（お手本の38%）と
    // 合成した「中平声で代用」（46%）は数値的に重なっており、両者を分ける
    // 閾値は存在しない。弾く側に倒すと正しい発音まで巻き込む。
    // **形は、形が出るだけの長さが取れたときだけ根拠にする。** 5フレームしか
    // 拾えなかった音節の相関は当てにならない（実機で -0.52 が出た）。
    final measuredEnough =
        queryValues[s].length >= kMinVoicedFramesForShape;
    final correlation = curveCorrelation(queryValues[s], refValues[s]);
    final directionOk = directionOf(querySlope) == directionOf(refSlope);
    final shapeOk = !measuredEnough
        ? false
        : correlation != null
            ? correlation >= kShapeCorrelationThreshold
            : directionOk;

    // 平らな3声調では、相関はお手本のわずかな傾きに対する細かい揺れを拾うだけで
    // 意味を持たない。実機で、低平声が corr=0.09、中平声が corr=-0.87 と出た
    // （どちらも高さは 0.34 と 0.01 でほぼ合っている）。**平らなお手本に対して
    // 相関を要求してはいけない。** 向き（上がる／下がる／平ら）だけで見る。
    final shapeAgrees = isContourTone(tone) ? shapeOk : directionOk;

    // 判断の根拠を声調で使い分ける。
    //   下降声・上昇声 → 動きが情報なので、向きが合っていれば合格
    //   平らな3つ　　 → 形では互いに区別できないので、直前との対比で判断
    //
    // 短い音節（短母音・死音節）は動きを出しきる時間がないので、形が出ていなくても
    // 責めない。ただし**形が出ていたなら、それは短くても正しく言えた証拠**なので
    // 合格の根拠にしてよい。短さが免除するのは「形を要求すること」であって、
    // 出せた形を無視する理由にはならない。
    //
    // 実機で、文頭の短い下降声（พรุ่ง）が corr=0.99 と形は完璧なのに、
    // 隣の音節の誤りに巻き込まれて「惜しい」に落ちていた。文頭は隣が片側に
    // しか無いので、その1つが崩れると逃げ場が無い。
    /// つながりだけで決める場合の判定。
    ///
    /// **両隣が崩れていると、段差はこの音節について何も語らない。** その場合だけ、
    /// 自身の高さがほぼ一致していて形も合っていることを逃げ道にする。
    ToneVerdict byLink() {
      if (linkOk) return ToneVerdict.correct;
      final escape =
          previousReliable ? kExactLevelEscape : kBrokenNeighborEscape;
      if (shapeAgrees && levelError <= escape) return ToneVerdict.correct;
      if (transitionError <= transitionThreshold * 2) return ToneVerdict.close;
      return ToneVerdict.wrong;
    }

    /// 段差が使えない場合の判定。文頭、または直前の声が拾えなかったとき。
    ///
    /// 比べられる相手がいないので、**その音節のピッチのグラフそのもの**だけで見る。
    /// 下降声・上昇声は形、平らな3つは形では区別できないので声域内の高さ。
    ToneVerdict byGraph() {
      if (isContourTone(tone) && shapeOk) {
        return levelError <= kContourLevelGate
            ? ToneVerdict.correct
            : ToneVerdict.close;
      }
      // 平らな3つは形では互いに区別できないが、**平らであるべき音節が逆向きに
      // 動いていれば別の声調**なので、そこだけは形で弾ける。
      // ここでの形の要求は合格ライン（[kShapeCorrelationThreshold]）より
      // ずっと緩く、「はっきり食い違っている」ときだけ落とす。お手本がほぼ平坦で
      // 相関が細かい揺れを拾うため、締めると正しい発話を巻き込む。
      final graphOk = !measuredEnough ||
          ((correlation == null || correlation >= 0) && directionOk);
      if (levelError <= kGraphLevelGate && graphOk) {
        return ToneVerdict.correct;
      }
      if (levelError <= kGraphLevelGate * 2) return ToneVerdict.close;
      return ToneVerdict.wrong;
    }

    final ToneVerdict verdict;
    if (incoming == null) {
      verdict = byGraph();
    } else if (isContourTone(tone)) {
      if (shapeOk) {
        // **形が合っていても、それだけでは通さない。** 上昇声を高平声で発音すると
        // どちらも右上がりなので形は一致するが、高さは 1.03 違う。
        // 形だけで判定していたとき、これが素通りしていた。
        verdict = levelError <= kContourLevelGate
            ? ToneVerdict.correct
            : ToneVerdict.close;
      } else if (isShort || !measuredEnough) {
        // 短くて動きを出しきれない、あるいは形が出るだけ測れていない。
        // どちらも出ていない形を責める理由にはならないので、つながりで判断する。
        verdict = byLink();
      } else {
        verdict = linkOk ? ToneVerdict.close : ToneVerdict.wrong;
      }
    } else {
      // 中平・低平・高平はどれも平らで、形では互いに区別できない。
      verdict = byLink();
    }

    scores.add(SyllableScore(
      syllableIndex: s,
      tone: tone,
      verdict: verdict,
      levelError: levelError,
      shapeError: shapeError,
      transitionError: transitionError,
      queryLevel: queryLevel(s),
      referenceLevel: refLevel(s),
      shapeCorrelation: correlation,
      referenceValues: refValues[s],
      queryValues: queryValues[s],
      queryStart: spanStart[s],
      queryEnd: spanEnd[s],
      referencePoints: reference.pointsOf(s),
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
