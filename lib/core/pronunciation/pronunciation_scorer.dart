// =============================================================================
// pronunciation_scorer.dart
// 対応づけ済みのお手本カーブと録音ピッチから、音節ごとの声調の当たり外れを出す。
//
// 判定は2つだけで行う。
//   - 形　　: その音節の中でピッチがどう動いたか（上がる／下がる／平ら）
//   - 入り方: **直前の音節が終わった高さ**から見て、上がって入ったか下がって
//             入ったか平らに入ったか
//
// **どちらも向きしか見ない。** 振れ幅も、下げ幅も、声域内の絶対的な高さも
// 採点しない。高さも動きの大きさも話者・場面・文中の位置で素直に動くので、
// 正しく発音していても弾かれてしまい、練習として続かない。実際、正しく高平声を
// 出しても平らに寄るのが普通で、お手本の上昇幅を要求するのは無理がある。
//
// 入り方の基準を**直前の音節の終わり際**に置くのは、人が実際にそう発音するから。
// 直前が終わった高さから次の音節に入るので、中心どうしの段差より終わり際からの
// 段差のほうが「その音節をどう出したか」に近い。
//
// 判定は形と入り方の**両方**が合ったときだけ correct。片方だけなら close。
// 両方外れていれば wrong。文頭には入り方が無いので、形だけで判断する。
//
// **代償を承知で緩めてある。** 高さを一切見ないので、次の取り違えは素通りする。
//   - 文頭の 中平→低平（どちらも平らで、比べる相手もいない）
//   - 末尾の 中平→低平（文末はもともと下がるので区別がつかない）
//   - 下降→高平（高平声は上がってから落ちるので形が重なる）
//   - 下げ幅・上げ幅が足りない発話全般（向きが合っていれば通る）
// 「正しく言えているのに惜しいと言われる」ほうが練習を止めると判断して、
// 見逃す側に倒している。
// =============================================================================

import 'dart:math' as math;

import 'dtw.dart';
import 'tone_contour.dart';
import '../thai_tone_analyzer.dart';

/// 「平ら」とみなす、音節の**始まりと終わりの差**の上限。
///
/// 形は**落ちている／上がっている／平ら**の3つに分けるだけで見る。動きの
/// 大きさは比べない。正しい方向に動いていても「振れ幅が足りない」で弾かれる。
///
/// **回帰の傾きではなく、始まりと終わりの差で見る。** 傾きは音節の中の細かい
/// 揺れを拾い、境目でしか差の無い声調（お手本の高平声と低平声）が判定の
/// 境界に張り付いた。実機で、聞けば全部合っている発話の中でその2つだけが
/// 「惜しい」になった。声調が持っているのは「どこから始まってどこへ行くか」
/// なので、そこだけを見る。
///
/// 端の1点ではなく前後25%の中央値を使う。1点だと検出誤りで向きが反転する。
const double kFlatRiseThreshold = 0.4;

/// 「平らに入った」とみなす段差の上限。
///
/// 直前の音節が終わった高さからの差を、**上がって入った／下がって入った／
/// 平らに入った**の3つに分けるだけで見る。差の大きさは問わない。
///
/// 正規化済みの声域（標準偏差）での値。中平 0.06 / 低平 -0.58 / 高平 1.11 と
/// いった声調どうしの高さの差は 0.5 以上あるので、この幅なら別の声調へ移る
/// 段差を潰さずに、同じ高さのまま続けた場合の細かい揺れだけを吸収できる。
const double kFlatStepThreshold = 0.3;

/// カーブの形が一致しているとみなす相関の下限。
///
/// 下降声・上昇声だけに使う。始まり終わりの差だけで見ると、**振れ幅が小さい発話が
/// 「平ら」に落ちる**（合成音声で、上昇声を 0.4 倍の振れ幅で言うと落ちた）。
/// 相関は振れ幅を無視するので、そこを救う。
///
/// 平らな3声調には使わない。お手本がほぼ平坦で、相関は細かい揺れを拾うだけ
/// （実機で正しい低平声が 0.09、中平声が -0.87）。
const double kShapeCorrelationThreshold = 0.4;

/// 向きが割れても同じ形とみなす、始まり終わりの差の食い違い。
///
/// お手本の高平声は上昇声の半分ほどしか上がらないので、[kFlatRiseThreshold] を
/// どちらに置いても正しい発話が割れる。差そのものが近ければ同じ形とする。
const double kRiseAgreement = 0.5;

/// 平らな3声調（中平・低平・高平）で使う、より広い許容。
///
/// **この3つは形では互いに区別できない。** 形が持っている情報は「逆向きに
/// 大きく動いていないか」だけで、区別そのものは入り方（直前の音からの位置）が
/// 受け持つ。だから形の側は広く取って、判断を位置に寄せる。
///
/// 実機で、話者が文の中盤を高いまま滑り降りたときに、中平声が音節の中で 0.68
/// ぶん下がって「惜しい」になった。お手本の declination（直線的な下がり）と
/// 実際の下がり方の食い違いで、声調の誤りではない。
///
/// 広げるほど取り違えを見逃す（合成音声で 0.5 なら 40/120、0.7 で 45、
/// 0.9 で 48、1.4 で 59）。**実機で観測された 0.68 を覆うところで止める。**
///
/// 文全体の滑りを推定して引いてから比べる案も測ったが、悪化した（40 → 47）。
/// 音節ごとの動きの中央値は、先頭・末尾の声調そのものを吸収してしまう。
/// detrend を捨てたときと同じ現象。
const double kFlatToneRiseAgreement = 0.7;

/// 動きを持つ声調か（下降声・上昇声）。
bool isContourTone(ThaiTone tone) =>
    tone == ThaiTone.falling || tone == ThaiTone.rising;

/// 形状誤差（始まり終わりの差の食い違い）。判定には使わず、表示のために残す。
const double kShapeErrorThreshold = 0.45;

/// 形（カーブの一致）を判定の根拠にしてよい、実際に声が出ていたフレームの最小数。
///
/// 高さは数フレームでも代表値が出るが、**形はそれでは決まらない**。実機で、
/// 5フレーム（50ms）しか取れなかった下降声が相関 -0.52 と出て弾かれた。
/// 出ていない形を根拠に誤りと言ってはいけない。足りなければ入り方で判断する。
const int kMinVoicedFramesForShape = 10;

/// 音節を採点するのに要る、実際に声が出ていたフレームの最小数。
///
/// ホップ10msなので50ms。これを下回る音節は平均も傾きも当てにならない。
/// **測れていないものを採点してはいけない。** 数フレームだけ拾えた音節に
/// 極端な値が出て、隣との段差が壊れる。
const int kMinVoicedFramesPerSyllable = 5;

/// 音節ごとの判定。
enum ToneVerdict {
  /// 形も入り方も合っている。
  correct,

  /// 片方だけ合っている。あるいは根拠が1つしか無く、それが外れている。
  close,

  /// 形も入り方も外れている。
  wrong,

  /// 採点対象外（声調が判定できない音節、または対応する録音が無い）。
  unscored,
}

/// 1音節ぶんの採点結果。
class SyllableScore {
  final int syllableIndex;
  final ThaiTone tone;
  final ToneVerdict verdict;

  /// 声域内の高さのずれ。**判定には使わない**（表示と切り分け用）。
  final double levelError;

  /// 動き（傾き）のずれ。判定には使わない（向きだけを見る）。
  final double shapeError;

  /// 直前の音節の終わり際から、この音節の中心までの段差（録音側）。
  /// 文頭では 0。
  final double queryStep;

  /// 同じ段差のお手本側。文頭では 0。
  final double referenceStep;

  /// 上2つのずれ。判定には使わない（向きだけを見る）が、切り分けのために残す。
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
  /// 形も入り方も「どのフレームがこの音節か」の上に乗っているので、境界の
  /// 置かれ方を見られるようにしておく。対応づいたフレームが無ければ両方 -1。
  final int queryStart;
  final int queryEnd;

  const SyllableScore({
    required this.syllableIndex,
    required this.tone,
    required this.verdict,
    this.levelError = 0,
    this.shapeError = 0,
    this.queryStep = 0,
    this.referenceStep = 0,
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

/// 差を向きに落とす。
ToneDirection directionOf(
  double delta, {
  double flatThreshold = kFlatRiseThreshold,
}) {
  if (delta > flatThreshold) return ToneDirection.rising;
  if (delta < -flatThreshold) return ToneDirection.falling;
  return ToneDirection.flat;
}

/// 音節の始まりから終わりまでで、ピッチがどれだけ動いたか。
///
/// 端の1点ではなく前後25%の中央値の差を採る。1点だと検出誤りで向きが反転する。
double contourRise(List<double> values) {
  if (values.length < 2) return 0;
  final window = math.max(math.min(3, values.length ~/ 2), (values.length * 0.25).round());
  return _median(values.sublist(values.length - window)) -
      _median(values.sublist(0, window));
}

/// 入り方の基準（直前の終わり際）が、お手本からどれだけ離れてよいか。
///
/// 入り方は直前が終わった高さを基準にするので、**その基準自体がお手本とずれて
/// いれば、段差はこの音節について何も語らない**。実機で、話者が下降声を下げきらずに
/// 終えたあと、続く中平声2つが「上がって入るはず」を満たせずに落ちた。その2つは
/// 自分の形も高さも合っており、崩れていたのは基準のほうだった。
///
/// 直前の判定が correct かどうかとは別の検査。形と入り方の両方が合っていても、
/// **終わった位置だけがずれている**ことはある（下降声をどこまで下げるかは
/// 話者差が大きい）。
///
/// 合成音声では、この検査を入れても見逃しは増えない（47 → 46/120）。
/// 基準がずれているときの段差は、もともと判定に寄与していなかった。
const double kBasisTolerance = 0.3;

/// 位置が違う組で「動いた」と数える最小の段差。
///
/// 符号だけで見ると、ほぼ 0 の揺れが「上がった」に化ける。合成音声で、
/// 下降声を中平声で発音した誤り（段差 0.000）が符号一致で素通りした。
/// 実機で通したい上がり幅（0.16）より小さく取る。
const double kMinStepToCount = 0.1;

/// 声域の中でのおおまかな位置。**数値ではなく順序**で持つ。
enum TonePosition { low, mid, high }

/// 声調の入り際・終わり際の位置。
const Map<ThaiTone, (TonePosition, TonePosition)> kTonePositions = {
  ThaiTone.mid: (TonePosition.mid, TonePosition.mid),
  ThaiTone.low: (TonePosition.low, TonePosition.low),
  ThaiTone.high: (TonePosition.high, TonePosition.high),
  ThaiTone.falling: (TonePosition.high, TonePosition.low),
  ThaiTone.rising: (TonePosition.low, TonePosition.high),
};

/// 直前の終わり際とこの音節の入り際で、声域内の位置が違うか。
///
/// **違うなら、上か下かは幅によらず決まる。** 低平声のあとの中平声は、
/// 直前をどこまで下げたかに関わらず「上がって入る」。実機で、低平声を
/// お手本より 0.32 浅く出した次の中平声が、上がり幅 0.16 では足りないとして
/// 落ちた。位置が違う組では**符号だけ**を見る。
///
/// 同じ位置の組（中平→中平など）は符号では決まらない。文全体の下がり
/// （declination）でどのみち下がるので、お手本の段差と比べる。
bool positionsDiffer(ThaiTone previous, ThaiTone current) {
  final from = kTonePositions[previous]?.$2;
  final to = kTonePositions[current]?.$1;
  if (from == null || to == null) return false;
  return from != to;
}

/// 段差を「どう入ったか」に落とす。
ToneDirection stepDirectionOf(double step) =>
    directionOf(step, flatThreshold: kFlatStepThreshold);

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
  // 音節の終わり際（お手本の正規化時間で後ろ25%）に対応づいた録音フレームだけ。
  final tailQuery =
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
    if (reference.isTailPoint(point.refIndex)) {
      tailQuery[syllable].add(queryZ[point.queryIndex]);
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

  /// 音節 [s] の終わり際の高さ（録音側）。次の音節がここから入る。
  ///
  /// 終わり際に対応づいたフレームが足りなければ、中心の高さで代用する。
  /// 無声の子音で音節の後半が丸ごと落ちることがある。
  double queryTail(int s) {
    final tail = tailQuery[s];
    if (tail.length >= 3) return _median(tail);
    return queryLevel(s);
  }

  /// 音節 [s] の高さ（お手本側）。
  ///
  /// 対応づけとは無関係に、お手本カーブの中心から決める。**対応づいた点だけから
  /// 採ってはいけない。** 下降声・上昇声はカーブが声域を大きく縦断するので、
  /// どの点が対応づいたかで中央値が跳ぶ。同じ文を2回読んだだけで、同じ音節の
  /// お手本の高さが 0.99 と -0.36 に振れたことがある。
  double refLevel(int s) => reference.centerLevel(s);

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

    // 入り方は**直前の音節が終わった高さから**測る。人は直前が終わった高さから
    // 次の音節に入るので、中心どうしの段差より実際の発音に近い。
    //
    // 直前が測れていない（声が拾えなかった）場合は比べようがないので null。
    //
    // **直前が誤っていたときも使わない。** 直前が違う声調で終わっていれば、
    // そこからの段差はこの音節について何も語らない。
    final measurablePrevious =
        s > 0 && queryValues[s - 1].length >= kMinVoicedFramesPerSyllable;
    // **基準がお手本からずれていたら、その段差は何も語らない。**
    final basisOff = measurablePrevious
        ? (queryTail(s - 1) - reference.tailLevel(s - 1)).abs()
        : 0.0;
    final hasPrevious = measurablePrevious &&
        scores[s - 1].verdict == ToneVerdict.correct &&
        basisOff <= kBasisTolerance;
    // 値そのものは切り分けのために出す（判定に使うかは [hasPrevious] で決まる）。
    final queryStep =
        measurablePrevious ? queryLevel(s) - queryTail(s - 1) : 0.0;
    final referenceStep =
        measurablePrevious ? refLevel(s) - reference.tailLevel(s - 1) : 0.0;
    final transitionError = (queryStep - referenceStep).abs();

    // **大きさは見ない。** 上がって入るべきところを上がって入っていればよく、
    // どれだけ上がったかは問わない。向きの3分割は境目で跳ねるので、段差そのものが
    // その幅に収まっていれば同じ入り方として扱う。
    final bool? stepAgrees = !hasPrevious
        ? null
        : positionsDiffer(reference.tones[s - 1], tone)
            ? queryStep.abs() >= kMinStepToCount &&
                queryStep.sign == referenceStep.sign
            : stepDirectionOf(queryStep) == stepDirectionOf(referenceStep) ||
                transitionError <= kFlatStepThreshold;

    // 形は始まりと終わりの差の向きで見る。動きの大きさは問わない。
    final queryRise = contourRise(queryValues[s]);
    final refRise = contourRise(refValues[s]);
    final shapeError = (queryRise - refRise).abs();
    final correlation = curveCorrelation(queryValues[s], refValues[s]);
    final riseAgrees = directionOf(queryRise) == directionOf(refRise) ||
        shapeError <=
            (isContourTone(tone) ? kRiseAgreement : kFlatToneRiseAgreement);
    final shapeMatches = isContourTone(tone)
        ? riseAgrees ||
            (correlation != null && correlation >= kShapeCorrelationThreshold)
        : riseAgrees && (hasPrevious || correlation == null || correlation >= 0);

    // 短母音・死音節は声調の動きを出しきる時間がない（tonal undershoot）。
    final isShort = shortSyllables != null &&
        s < shortSyllables.length &&
        shortSyllables[s];

    // 形が根拠になるのは、**形が出るだけの長さが取れたとき**だけ。
    final measuredEnough = queryValues[s].length >= kMinVoicedFramesForShape;

    // 短さが免除するのは「形を要求すること」であって、**出せた形を無視する理由に
    // はならない**。短くても形が出ていれば、それは正しく言えた証拠。
    final bool? shapeAgrees = !measuredEnough
        ? null
        : shapeMatches
            ? true
            : isShort
                ? null
                : false;

    // 形と入り方の両方が合えば correct、片方だけなら close、両方外れれば wrong。
    // **根拠が1つしか無いときは wrong にしない。** 文頭（入り方が無い）や
    // 短すぎて形が測れない音節を、1つの手がかりだけで断定してはいけない。
    final available = [shapeAgrees, stepAgrees].whereType<bool>().toList();
    final agreed = available.where((ok) => ok).length;
    final ToneVerdict verdict;
    if (available.isEmpty) {
      verdict = ToneVerdict.close;
    } else if (agreed == available.length) {
      verdict = ToneVerdict.correct;
    } else if (agreed > 0 || available.length < 2) {
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
      queryStep: queryStep,
      referenceStep: referenceStep,
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
