// =============================================================================
// pronunciation_scorer.dart
// 対応づけ済みのお手本カーブと録音ピッチから、音節ごとの声調の当たり外れを出す。
//
// 判定は3つで行う。**根拠になるのは上2つだけ**で、3つ目は correct を取り消す
// 方向にしか働かない。
//   - 形　　: その音節の中でピッチがどう動いたか（上がる／下がる／平ら）
//   - 高さ　: 声域の中の位置がお手本からどれだけ離れているか（[kLevelDisagreement]）
//   - 入り方: 直前の音節が終わった高さに対して、**入り際が上に来るはずの組で
//             下から入っていないか**（[entryOrder]）
//
// **形は向きしか見ない。** 振れ幅も下げ幅も採点しない。話者・場面・文中の位置で
// 素直に動くので、正しく発音していても弾かれてしまい、練習として続かない。
// 正しく高平声を出しても平らに寄るのが普通で、お手本の上昇幅を要求するのは無理。
//
// **入り方は幅を見ない。順序だけを見る。** 上に入るはずのところで下から入って
// いれば、上げ幅がいくつであれ別の声調。同じ高さで入っていれば許容する。
// 段差の大きさで判定していた頃は、話者が上げきれないだけで落ちていた。
// 順序なら基準（直前の終わり際）が多少ずれても壊れないので、高さのずれは
// 免除できる。ただし**直前が誤っていたら順序も語らない**（別の声調で終わって
// いれば、そこから見た上下はこの音節について何も意味しない）。
//
// **順序が合っていることは根拠にしない。** 「違わない」だけで「その声調だった」
// 証拠にはならないので、落とす方向にだけ使う。結果として、ほとんどの音節は
// 形と高さで決まる。
//
// 判定は根拠が**全て**合ったときだけ correct。割れれば close。全部外れれば
// wrong。ただし**根拠が1つしか無いときは wrong にしない**（文頭や、短すぎて
// 形が測れない音節を、1つの手がかりだけで断定してはいけない）。
//
// **代償を承知で緩めてある。**
//   - 文頭の 中平→低平（どちらも平らで、比べる相手もいない）
//   - 上昇→低平（子音の無声区間が 90ms を超える音節に限る。形を根拠にできる
//     長さが残らない）
//   - 下げ幅・上げ幅が足りない発話全般（向きと順序が合っていれば通る）
// 逆に、**上げそこねは 0.5 を超えると「惜しい」になる**（[kLevelDisagreement]）。
// 高さを見ない設計だった頃はここも通していた。実機で「正しく言えたのに惜しい」が
// 出るなら、まずこの閾値を疑うこと。
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

/// 入り方が使えないとき、高さのずれだけで correct を取り消す境目。
///
/// **これだけは高さそのものを見る。** 基準（直前の音節が終わった高さ）が
/// 信用できない音節では入り方が使えず、形しか根拠が残らない。上昇声と高平声は
/// **どちらも上がる形**なので、そこでは区別が消える（合成音声で 29/67 が素通り）。
///
/// 高さを判定に持ち込むのは、**correct を close へ落とす方向にだけ**。
/// 誤りだと言い切るには弱い（話者・文中の位置で素直に動く）が、「合っている」
/// と言い切るのを止める根拠にはなる。wrong の側へは効かせない。
///
/// 0.5 は正規化済みの声域での値。声調どうしの高さの差（0.5〜1.1）より小さく、
/// 正しい発話で出るずれ（合成音声60文で最大 0.4 台）より大きい。狭めても
/// 見逃しは減らず（0.5 で 283、0.6 で 292、0.8 で 332/1440）、正しい発話の
/// 誤検出は 3/360 のまま動かない。
const double kLevelDisagreement = 0.5;

/// 直前の終わり際に対して、この声調の入り際が上（1）か下（-1）か。
/// 同じ位置なら 0（順序では決まらないので検査しない）。
///
/// **幅ではなく順序だけを見る。** 上に入るはずの組で下から入っていれば、
/// 上げ幅がいくつであっても別の声調。基準（直前の終わり際）が多少ずれていても
/// 順序は壊れないので、[kBasisTolerance] で入り方を捨てた音節でも使える。
int entryOrder(ThaiTone previous, ThaiTone current) {
  final from = kTonePositions[previous]?.$2;
  final to = kTonePositions[current]?.$1;
  if (from == null || to == null || from == to) return 0;
  return to.index > from.index ? 1 : -1;
}

// 連続して発音すると音節の継ぎ目に段差が立たず、ピッチが1本の線で繋がる
// （合成側の carryover 0.6 で再現すると、見逃し 283 → 325/1440、
// 誤検出 3 → 16/360）。これに対する2つの手当てを測って、**どちらも悪化した**。
//   - 継ぎ目を形の根拠から外す（前後15%を捨てる）: 素直 283 → 413、
//     引きずり 325 → 409。しかも短い音節が採点に足りる長さを割り、
//     **採点できる音節そのものが 1440 → 963 に減る**。
//   - お手本側の継ぎ目を隣の声調へ直線で繋ぐ（前後25%）: 素直 283 → 419、
//     引きずり 325 → 409。上昇→低平 の見逃しが 0 → 37 に戻る。
// 繋がっている区間は**声調の違いがいちばん出るところ**でもあるので、削っても
// 均しても信号のほうが先に消える。効いたのは入り際の順序（[entryOrder]）だった。

/// お手本を音節全体ではなく、その音節の**有声区間（母音）**に張り直すか。
///
/// 声調が乗るのは母音以降で、頭の無声子音の間はピッチが存在しない。いまは
/// お手本を音節まるごとに張っているので、母音はカーブの後半に当たり、声調の
/// 動きを子音のぶんまで薄めて測っている。
///
/// **効果は話者のモデル次第で、合成音声だけでは決められない。**
/// 合成側の前提を切り替えて（[synthesizeF0] の `toneOnVoiced`）測った結果:
///
/// | 話者の前提 | 無声区間 | 音節全体に張る（現行） | 有声区間に張る |
/// |---|---|---|---|
/// | 声調は母音内で完結 | 60ms | 誤検出 3 / 見逃し 259 | 誤検出 4 / 見逃し 159 |
/// | 声調は母音内で完結 | 120ms | 誤検出 3 / 見逃し 291 | 誤検出 3 / 見逃し 153 |
/// | 声調は音節全体 | 60ms | 誤検出 3 / 見逃し 316 | 誤検出 12 / 見逃し 170 |
/// | 声調は音節全体 | 120ms | 誤検出 14 / 見逃し 372 | 誤検出 35 / 見逃し 189 |
///
/// （360件中の誤検出／1440件中の見逃し。カーブの頭を捨てる割合を 0.5・0.75 と
/// 中間に置いても誤検出は 12／35 のまま減らない。効いているのはカーブのずらし方
/// ではなく、中心・終わり際を有声区間で数え直すこと）
///
/// **実機の録音で確かめるまで false のまま。** 話者が音節全体のモデルに近いと、
/// 頭の長い子音（ph / th / kh / s）を持つ音節で「正しく言えたのに惜しい」が
/// 増える。この判定は見逃す側に倒す方針なので、そちらの誤りのほうが重い。
/// 確かめ方: 頭が有気音の音節を含む文を正しく発音し、その音節が correct のまま
/// かどうかを見る。true にすると calibration_test の 120ms の検査と
/// clause_break_test の誤判定率が落ちる（＝誤検出が増える）ので、そこも見直すこと。
const bool kLayReferenceOnVoiced = false;

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

  /// 形が合っていたか。null は「形を根拠にできなかった」（短すぎる／短母音）。
  final bool? shapeAgrees;

  /// 入り方が合っていたか。null は「入り方を根拠にできなかった」
  /// （文頭／直前が測れない／基準がずれていて不一致だった）。
  final bool? stepAgrees;

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
    this.shapeAgrees,
    this.stepAgrees,
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
///
/// **端を落としてから見る案を測ったが、落とすほど悪化する。** 合成音声60文で
/// 見逃しは 482（そのまま）→ 498（前後8%を落とす）→ 552（同15%）→
/// 605/1440（中央付近の 20〜40% と 60〜80% の2点だけで見る）。
/// 窓を狭めるほど測れる動きが小さくなり、向きの3分割（[kFlatRiseThreshold]）で
/// 「平ら」に落ちる。**この判定を壊しているのは端の汚れではなく、動きが
/// 小さく出ること**なので、窓は広く採る。
///
/// どの案でも 上昇→低平 は 64/67 のまま動かない。あれは端の汚れではなく
/// お手本の上昇声が前半で沈むことが原因（[kToneContours] を参照）。
double contourRise(List<double> values) {
  if (values.length < 2) return 0;
  final window = math.max(math.min(3, values.length ~/ 2), (values.length * 0.25).round());
  return _median(values.sublist(values.length - window)) -
      _median(values.sublist(0, window));
}

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
  // **高平声の入り際は「高い側」に置く。** 記述としては中くらいから始まって
  // 上がる（mid-rising）が、ここが持つのは物理的な出発点ではなく**順序の期待**で、
  // 中平声と同じ位置に置くと高平声が連続したときに順序の期待が壊れる
  // （実機で 高平→高平 の正しい発話が「下がって入るはず」を満たせず落ちた）。
  // 合成音声でも mid に置くと 高平→高平 の見逃しが 21/36、high なら 4/36、
  // 引きずり条件の誤検出も 16 → 9/360 に減る。
  ThaiTone.high: (TonePosition.high, TonePosition.high),
  ThaiTone.falling: (TonePosition.high, TonePosition.low),
  // **上昇声は上まで届かない。** Chao 213 で、戻るのは中くらいまで
  // （高平声 35 のように上までは行かない）。
  ThaiTone.rising: (TonePosition.low, TonePosition.mid),
};

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
  // 音節の入り際（お手本の正規化時間で前25%）に対応づいた録音フレームだけ。
  final headQuery =
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
    if (reference.isHeadPoint(point.refIndex)) {
      headQuery[syllable].add(queryZ[point.queryIndex]);
    }
  }

  // お手本を音節全体ではなく**有声区間に張り直す**。
  //
  // 声調が乗るのは母音以降で、頭の無声子音の間はピッチが存在しない。お手本を
  // 音節まるごとに張ると、母音がカーブの後半に当たり、声調の動きを子音のぶんまで
  // 薄めて測ることになる。DTW の対応づけ（時間軸を保つために無声区間が要る）は
  // そのまま使い、**採点のときだけ**その音節の有声フレームにカーブを張り直す。
  if (kLayReferenceOnVoiced) {
    for (var s = 0; s < reference.syllableCount; s++) {
      if (spanStart[s] < 0) continue;
      final voicedValues = <double>[];
      for (var i = spanStart[s]; i <= spanEnd[s]; i++) {
        if (i >= queryVoiced.length || !queryVoiced[i]) continue;
        voicedValues.add(queryZ[i]);
      }
      if (voicedValues.length < 2) continue;

      final slice = reference.values
          .sublist(reference.starts[s], reference.starts[s + 1]);
      queryValues[s]
        ..clear()
        ..addAll(voicedValues);
      refValues[s]
        ..clear()
        ..addAll(resampleContour(slice, voicedValues.length));

      final n = voicedValues.length;
      final margin = (n * 0.2).round();
      final tail = (n * 0.25).round().clamp(1, n);
      centerQuery[s]
        ..clear()
        ..addAll(voicedValues.sublist(margin, n - margin));
      tailQuery[s]
        ..clear()
        ..addAll(voicedValues.sublist(n - tail));
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

  /// 音節 [s] の入り際の高さ（録音側）。取れなければ中心の高さで代用する。
  double queryHead(int s) {
    final head = headQuery[s];
    if (head.length >= 3) return _median(head);
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
    //
    // **節の頭も文頭と同じ扱いにする。** 節の切れ目では息を継いで声を上げ直す
    // ので、切れ目の手前が終わった高さは次の音節の入り方について何も語らない。
    final measurablePrevious = s > 0 &&
        !reference.isClauseStart(s) &&
        queryValues[s - 1].length >= kMinVoicedFramesPerSyllable;
    // **到達点は入り際ではなく中心。** 物理的には「直前の終わり → この音節の
    // 入り際」が入り方だが、入り際は測定が最も当てにならない点で、
    //   - 子音でまだ声が出ていない（有声フレームが無く、中心の値で代用になる）
    //   - 直前の声調の引きずり（carryover）が最も強く残る
    // 合成音声で入り際に変えると、正しい発話が 0→3/90 落ち、見逃しも
    // 44→46/120 に増えた。声調の位置が最も安定して出るのは中心。
    //
    // **中心どうしで測る案も測った**（両側とも最も安定した点にする）。
    // 正しい発話が 1/90 落ち、見逃しも 46/120 に増えた。人は直前が終わった
    // 高さから次に入るので、起点は終わり際が正しい。
    //
    // **実際に声が出始めたところ（母音の頭）を使う案も測った。** 時間の位置では
    // なく対応づいた組の先頭を採れば子音には当たらず、正しい発話は 0/90 のまま
    // だったが、見逃しが 44 → 52〜56/120 に増えた。声調は**音節の中で高さが
    // 決まっていく**もので、出だしでは互いに最も近い。区別が乗っているのは中心。
    final queryStep =
        measurablePrevious ? queryLevel(s) - queryTail(s - 1) : 0.0;
    final referenceStep =
        measurablePrevious ? refLevel(s) - reference.tailLevel(s - 1) : 0.0;
    final transitionError = (queryStep - referenceStep).abs();

    // **入り方は順序だけで見る。** 入り際が直前の終わり際より上に来るはずの組で
    // 下から入っていれば、上げ幅がいくつであれ別の声調。同じ高さで入っていれば
    // 許容する（幅も向きの3分割も見ない）。
    //
    // **合っていることの根拠にはしない。** 順序が期待どおりでも、それは
    // 「違わない」だけで「その声調だった」証拠にはならない。落とす方向にだけ使う。
    //
    // **直前が誤っていたら順序も語らない。** 直前が別の声調で終わっていれば、
    // そこから見た上下はこの音節について何も意味しない。高さのずれ
    // （[kBasisTolerance] 相当）は免除する — ずれていても順序は壊れないため。
    final bool? stepAgrees = !measurablePrevious ||
            scores[s - 1].verdict != ToneVerdict.correct
        ? null
        : () {
            final expected = entryOrder(reference.tones[s - 1], tone);
            if (expected == 0) return null;
            final observed = queryHead(s) - queryTail(s - 1);
            // **低平声だけは入りを実際に見る。** 5声調でこれだけが「声域の底に
            // 居ること」そのもので、動きを持たない。形では中平声と区別できず、
            // 期待どおり下がって入ったかどうかが唯一の手がかりになる。
            // 逆でないことを求めるだけでは、下がらずに平らのまま続けた発話が
            // 通ってしまう（合成音声で 低平→中平 の取り違え 41/68）。
            //
            // **中平声には同じ要求をしない。** あちらは声域の中立点で、そこへ
            // 入る動きは前の声調しだいで消える。要求すると誤検出が増えるだけ
            // だった（短母音条件で 6 → 12/360、見逃しは 189 → 186 とほぼ不変）。
            if (tone == ThaiTone.low) {
              // **直前が中〜高で終わっているときだけ要求する。** 下降声と低平声は
              // 自分が低く終わるので、そこからさらに下がりようがない。とくに
              // 下降声はどこまで下げるかの話者差が大きく、終点を基準に厳しくすると
              // 正しい発話を落とす。
              final from = kTonePositions[reference.tones[s - 1]]?.$2;
              if (from == null || from == TonePosition.low) return null;
              return observed * expected > kMinStepToCount ? null : false;
            }
            if (observed * expected < -kMinStepToCount) return false;
            return null;
          }();

    // 形は始まりと終わりの差の向きで見る。動きの大きさは問わない。
    final queryRise = contourRise(queryValues[s]);
    final refRise = contourRise(refValues[s]);
    final shapeError = (queryRise - refRise).abs();
    final correlation = curveCorrelation(queryValues[s], refValues[s]);
    final riseAgrees = directionOf(queryRise) == directionOf(refRise) ||
        shapeError <=
            (isContourTone(tone) ? kRiseAgreement : kFlatToneRiseAgreement);
    // 動きを持つ声調では、**逆向きに動いていれば形は合っていない**。
    // 始まり終わりの差は正規化後には小さく出て（実測で 0.3〜0.6）、向きの
    // 3分割（[kFlatRiseThreshold] = 0.4）ではどちらも「平ら」に落ちる。
    // 上昇声のところを低平声で発音した誤りが、相関 -0.69 と**はっきり逆向き**
    // なのに「どちらも平ら」で一致していた（合成音声で 64/67 が素通り）。
    // 相関が閾値ぶん負なら、動きの大きさに関わらず落とす。
    final shapeMatches = isContourTone(tone)
        ? riseAgrees &&
            !(correlation != null && correlation <= -kShapeCorrelationThreshold)
        : riseAgrees &&
            (stepAgrees != null || correlation == null || correlation >= 0);

    // 形が根拠になるのは、**形が出るだけの長さが取れたとき**だけ。
    final measuredEnough = queryValues[s].length >= kMinVoicedFramesForShape;

    // 短さが免除するのは「形を要求すること」であって、**出せた形を無視する理由に
    // はならない**。短くても形が出ていれば、それは正しく言えた証拠。
    // **短さを理由に形を免除しない。** お手本側は既に短い音節で振れ幅を
    // [kShortSyllableDamping] 倍に縮めており、undershoot は織り込み済み。
    // ここでもう一度免除すると二重の割引になり、**入り方も使えない場面で根拠が
    // ゼロになって採点不能が並ぶ**（実機で9音節中6つが短母音の文が出た）。
    //
    // 合成音声では差が出ない（合成側もお手本と同じ倍率で縮めるので、短い音節では
    // 形が必ず一致する）。効くのは実機だけ。
    final bool? shapeAgrees = !measuredEnough ? null : shapeMatches;

    // 形と入り方の両方が合えば correct、片方だけなら close、両方外れれば wrong。
    // **根拠が1つしか無いときは wrong にしない。** 文頭（入り方が無い）や
    // 短すぎて形が測れない音節を、1つの手がかりだけで断定してはいけない。
    final available = [shapeAgrees, stepAgrees].whereType<bool>().toList();
    final agreed = available.where((ok) => ok).length;
    ToneVerdict verdict;
    if (available.isEmpty) {
      // **根拠が1つも無い音節を「惜しい」と言ってはいけない。** 短母音で形を
      // 要求できず、かつ直前がずれていて入り方も使えない、という重なりが実機で
      // 起きる。何も測れていないのだから、判定できないと言う（点数の分母からも
      // 外れる）。判定できないことと、判定して駄目だったことを混ぜない。
      verdict = ToneVerdict.unscored;
    } else if (agreed == available.length) {
      verdict = ToneVerdict.correct;
    } else if (agreed > 0 || available.length < 2) {
      verdict = ToneVerdict.close;
    } else {
      verdict = ToneVerdict.wrong;
    }

    // 入り方が使えない音節では、形だけで correct になる。上昇声と高平声は
    // どちらも上がる形なので、そこは高さで分ける（[kLevelDisagreement]）。
    if (verdict == ToneVerdict.correct &&
        stepAgrees == null &&
        levelError > kLevelDisagreement) {
      verdict = ToneVerdict.close;
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
      shapeAgrees: shapeAgrees,
      stepAgrees: stepAgrees,
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
