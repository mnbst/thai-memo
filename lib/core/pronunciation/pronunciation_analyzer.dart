// =============================================================================
// pronunciation_analyzer.dart
// 発音練習の判定パイプライン全体。
//
// 入力はフレームごとのF0（Hz）と、例文の音節の声調列。マイクにもUIにも依存
// しない純粋な関数として組んであるので、録音なしでテストできる。
//
//   F0(Hz) → セミトーン化・オクターブ誤り除去 → 声域の推定 → 正規化
//          → お手本カーブと DTW で対応づけ → 音節ごとの採点
//
// 採点できないと判断した場合は結果を返さず [PronunciationFailure] を立てる。
// 当てにならない採点を見せるより、「もう一度」を出すほうが機能への信頼を保てる。
// =============================================================================

import 'dtw.dart';
import 'pitch_track.dart';
import 'pronunciation_scorer.dart';
import 'speaker_range.dart';
import 'tone_contour.dart';
import 'transcript_match.dart';
import 'word_verdict.dart';
import '../thai_tone_analyzer.dart';

/// 採点に必要な最小の有声フレーム比率。
///
/// 騒音環境や、マイクに声が届いていない録音を弾く。
const double kMinVoicedRatio = 0.35;

/// 採点できなかった理由。
enum PronunciationFailure {
  /// 採点できた。
  none,

  /// 声が拾えていない（無声フレームが多すぎる）。
  tooQuiet,

  /// 声域が決まらない。発話が短く、蓄積プロファイルも無い場合。
  noSpeakerRange,

  /// 音節が無い（お手本を組み立てられない）。
  noSyllables,

  /// 収録そのものが始められなかった／音声が1フレームも取れなかった。
  ///
  /// [tooQuiet]（声が小さい）と混同しないこと。こちらは環境ではなく
  /// 収録経路の問題で、ユーザーが静かな場所へ移動しても直らない。
  captureFailed,
}

/// 発音練習1回ぶんの結果。
class PronunciationResult {
  final List<SyllableScore> syllables;

  /// 声調と発音を合わせた 0〜100。
  /// [failure] が [PronunciationFailure.none] のときだけ意味を持つ。
  final double overallScore;

  /// 声調だけの 0〜100。[overallScore] との差が発音（通じたか）のぶん。
  ///
  /// 切り分け用に残してある。画面に出すのは [overallScore]。
  final double toneScore;

  final PronunciationFailure failure;

  /// 採点に使った声域。
  final SpeakerRange? speakerRange;

  /// この録音だけから推定できた声域。
  ///
  /// 取れた場合のみ非 null。呼び出し側はこれを [SpeakerPitchProfile] に
  /// 取り込んで永続化する。蓄積プロファイルで代用した回は反映しない
  /// （推定値を推定値で上書きして誤差が積み上がるのを避けるため）。
  final SpeakerRange? freshRange;

  /// 声が途切れた区間（採点に使う添字での [開始, 終了]）。
  ///
  /// 子音、とくに閉鎖音・摩擦音では声が止まる。**その位置は音節の切れ目の
  /// 手がかりになる**。いまは採点から外すためだけに使っているが、境界を
  /// お手本の時間配分ではなく録音から決められるかを見るために持ち出す。
  ///
  /// 共鳴音で繋がる境界（งาน→นะ）はここに現れない。全ての境界は取れない。
  final List<List<int>> voicelessGaps;

  const PronunciationResult({
    required this.syllables,
    required this.overallScore,
    required this.failure,
    double? toneScore,
    this.speakerRange,
    this.freshRange,
    this.voicelessGaps = const [],
  }) : toneScore = toneScore ?? overallScore;

  bool get isScored => failure == PronunciationFailure.none;

  /// 抑揚がほとんど無い発話だったか。
  ///
  /// 採点はできているが、声調を付けずに読み上げた可能性が高い状態。
  /// この録音から声域を推定できず（＝広がりが [kMinRangeSemitone] 未満）、
  /// 蓄積プロファイルで代替した場合に立つ。
  ///
  /// 平坦に読むと中平声の音節だけが偶然一致するため、点数だけでは半分近くまで
  /// 伸びてしまう。点数の代わりに「抑揚が付いていない」と伝えるほうが、
  /// 学習者が次に何をすべきか分かる。
  bool get isMonotone => isScored && speakerRange != null && freshRange == null;

  /// 失敗を表す結果を組み立てる。
  factory PronunciationResult.failed(PronunciationFailure failure) =>
      PronunciationResult(
        syllables: const [],
        overallScore: 0,
        failure: failure,
      );
}

/// 音節の「端」とみなす割合（前後それぞれ）。
///
/// 子音の無声区間はここに来るので、ここで途切れに当たるのはただにする。
/// 狭いと、ふつうの子音（実測で音節の4割を占めることがある）が中央に掛かって
/// 罰せられ、境界がずれる。
const double kBoundaryZoneFraction = 0.4;

/// 声が途切れた区間を数える最小のフレーム数。
///
/// ホップ10msなので30ms。閉鎖音の閉鎖区間はこれより長い。これを下回る途切れは
/// 声門の揺れや検出漏れで、子音の証拠にならない。
const int kMinVoicelessGapFrames = 3;

/// 2つの途切れを1つとみなす、間の有声フレーム数の上限。
///
/// 閉鎖の途中で声門が数フレームだけ鳴ることがあり、1つの子音が2つの途切れに
/// 割れて見える。実機で 125-127 と 130-154 に割れ、錨が手前の小さいほうに付いて
/// 大きいほうが次の音節の中に取り残された（その音節は有声2フレームで採点不能）。
const int kGapMergeFrames = 3;

/// 声が途切れた区間（[開始, 終了]、終了を含む）を拾う。
///
/// [voiced] は各フレームが実際に声だったか。false は補間で埋めたフレーム。
List<List<int>> findVoicelessGaps(List<bool> voiced) {
  final raw = <List<int>>[];
  var start = -1;
  for (var i = 0; i < voiced.length; i++) {
    if (!voiced[i]) {
      if (start < 0) start = i;
      continue;
    }
    if (start >= 0) {
      if (i - start >= kMinVoicelessGapFrames) raw.add([start, i - 1]);
      start = -1;
    }
  }
  if (start >= 0 && voiced.length - start >= kMinVoicelessGapFrames) {
    raw.add([start, voiced.length - 1]);
  }

  // 近すぎる途切れは1つの子音が割れたもの。
  final gaps = <List<int>>[];
  for (final gap in raw) {
    if (gaps.isNotEmpty && gap[0] - gaps.last[1] - 1 <= kGapMergeFrames) {
      gaps.last[1] = gap[1];
      continue;
    }
    gaps.add([...gap]);
  }
  return gaps;
}

/// 途切れで決まらなかった切れ目に、音量の谷を割り当てる。
///
/// **谷を途切れと同格に並べてはいけない。** 谷は「切れ目かもしれない」でしかなく、
/// 母音の中の揺れも拾う。実機で、途切れ7個に対し谷が9〜10個立ち、本物の切れ目と
/// 競合して点数が下がった（9本平均 90 → 5本平均 85）。
///
/// まず途切れだけで割り当て、**残った切れ目にだけ**谷を探す。探す範囲は錨を通る
/// 折れ線の上の予想位置のまわりで、隣の錨を越えない範囲に限る。
Map<int, List<int>> fillSeamsWithValleys({
  required ReferenceContour reference,
  required Map<int, List<int>> anchors,
  required List<List<int>> valleys,
  required List<double> referenceToQuery,
  required int queryLength,
}) {
  if (valleys.isEmpty) return anchors;

  final filled = <int, List<int>>{...anchors};
  final reach = queryLength * kValleySearchRatio;

  for (var syllable = 1; syllable < reference.syllableCount; syllable++) {
    final refIndex = reference.starts[syllable];
    if (filled.containsKey(refIndex)) continue;
    if (refIndex >= referenceToQuery.length) continue;

    final expected = referenceToQuery[refIndex];
    // 隣の錨を越えないこと（順序が崩れると音節が入れ替わる）。
    var lower = 0.0;
    var upper = (queryLength - 1).toDouble();
    filled.forEach((otherRef, gap) {
      if (otherRef < refIndex) {
        final end = gap[1].toDouble();
        if (end > lower) lower = end;
      } else if (otherRef > refIndex) {
        final start = gap[0].toDouble();
        if (start < upper) upper = start;
      }
    });

    List<int>? best;
    var bestDistance = double.infinity;
    for (final valley in valleys) {
      final center = (valley[0] + valley[1]) / 2;
      if (center <= lower || center >= upper) continue;
      final distance = (center - expected).abs();
      if (distance > reach || distance >= bestDistance) continue;
      best = valley;
      bestDistance = distance;
    }
    if (best != null) filled[refIndex] = best;
  }
  return filled;
}

/// 谷を切れ目とみなす、予想位置からの距離（録音長に対する割合）。
///
/// 途切れ（[kSeamMatchRatio]）より狭く取る。谷は証拠として弱いので、予想位置の
/// すぐ近くに立っているときだけ信じる。
const double kValleySearchRatio = 0.06;

/// 音量の谷を音節の切れ目とみなす、へこみの深さ（両隣の山に対する比）。
///
/// **共鳴音で繋がる切れ目は F0 にも無声区間にも現れない**（`ชิ้น` น → `นี้` น）。
/// 鼻音・側音は母音より弱いので、そこは音量が凹む。浅い揺れまで拾うと母音の中の
/// 微細な変動を切れ目にしてしまうので、はっきりへこんだところだけを採る。
const double kValleyDepthRatio = 0.6;

/// 音量の谷どうしの最小間隔（フレーム）。
///
/// 音節は 60ms より短くならない。近すぎる谷は同じへこみの揺れ。
const int kMinValleySeparation = 6;

/// 音量の谷（音節の切れ目の候補）を拾う。
///
/// [energy] はフレームごとの音量（RMS）。返すのは [開始, 終了] の形（途切れと
/// 同じ形にして、割り当てで区別せず扱えるようにする）。
///
/// 谷とみなすのは、**両隣の山の低いほうに対して [kValleyDepthRatio] 倍より
/// 深くへこんだ**局所最小。発話全体で音量が下がるだけの箇所は拾わない。
List<List<int>> findEnergyValleys(List<double> energy) {
  if (energy.length < 3) return const [];

  final valleys = <List<int>>[];
  var lastIndex = -kMinValleySeparation;
  var i = 1;
  while (i < energy.length - 1) {
    // 下がってきた先か（平らな底も含む）。
    if (energy[i] > energy[i - 1]) {
      i++;
      continue;
    }
    // 平らな底は1つの谷。端まで進めてから中央を採る。
    var end = i;
    while (end + 1 < energy.length && energy[end + 1] == energy[i]) {
      end++;
    }
    if (end + 1 >= energy.length || energy[end + 1] < energy[i]) {
      // まだ下っている途中。
      i = end + 1;
      continue;
    }

    final center = (i + end) ~/ 2;
    if (center - lastIndex < kMinValleySeparation) {
      i = end + 1;
      continue;
    }

    // 両側の山を探す。
    var leftPeak = energy[center];
    for (var k = i - 1; k >= 0 && center - k <= kMaxValleyReach; k--) {
      if (energy[k] > leftPeak) leftPeak = energy[k];
    }
    var rightPeak = energy[center];
    for (var k = end + 1;
        k < energy.length && k - center <= kMaxValleyReach;
        k++) {
      if (energy[k] > rightPeak) rightPeak = energy[k];
    }
    final peak = leftPeak < rightPeak ? leftPeak : rightPeak;
    if (peak > 0 && energy[center] <= peak * kValleyDepthRatio) {
      valleys.add([center, center]);
      lastIndex = center;
    }
    i = end + 1;
  }
  return valleys;
}

/// 谷の深さを測るときに、両隣の山をどこまで探すか（フレーム）。
///
/// 音節1つぶんの長さ（150ms前後）。これより遠い山は別の音節のもの。
const int kMaxValleyReach = 15;

/// 途切れを音節の切れ目に割り当てるとき、予想位置からどれだけ離れてよいか。
///
/// 帯（[kDtwBandRatio]）より広く取る。**この割り当ては帯そのものを引き直す**
/// ためのもので、帯の内側に収まっている必要はない。実機で、予算の誤差が
/// 8.75% に達して帯（6%）を超え、切れ目が途切れの手前に固定された。
const double kSeamMatchRatio = 0.15;

/// 音節の切れ目に、声の途切れを割り当てる。
///
/// **タイ語の音節は必ず子音で始まり、閉鎖音・摩擦音なら声が止まる。** だから
/// 途切れは音節の切れ目の部分集合になる（逆は成り立たない）。共鳴音で繋がる
/// 境界（`งาน`→`นะ`、`บรร`→`ยา`）には途切れが出ないので、**数を合わせない**。
///
/// 順序を保ったまま（追い越さずに）、予想位置に近いものから割り当てる。
/// 母音の途中で声が落ちる（軋み声）ことがあるので、遠すぎる途切れは捨てる。
///
/// 返すのは「お手本の点の添字 → 対応づいた途切れ [開始, 終了]」。
Map<int, List<int>> assignGapsToSeams({
  required ReferenceContour reference,
  required List<List<int>> voicelessGaps,
  required int queryLength,
}) {
  final seams = <int>[
    for (var s = 1; s < reference.syllableCount; s++) reference.starts[s],
  ];
  if (seams.isEmpty || voicelessGaps.isEmpty || queryLength < 2) {
    return const {};
  }

  final refLength = reference.values.length;
  final expected = [
    for (final seam in seams) seam / refLength * queryLength,
  ];
  /// 予想位置から途切れ **区間** までの距離。中に入っていれば 0。
  ///
  /// **中心までの距離で測ってはいけない。** 長い途切れは位置の幅を持っている。
  /// 中心で測ると、3フレームの途切れのほうが 770ms の間より「近い」ことになる。
  /// 実機で、`ให้` の直後の間（44-121、予想位置 44 はその中）ではなく手前の
  /// 3フレームの途切れ（36-38）が錨に選ばれ、**間より後ろの音節が丸ごと1つ
  /// ずれた**（点数 62.5、9音節中5個が採点不能）。
  double distanceTo(List<int> gap, double position) {
    if (position < gap[0]) return gap[0] - position;
    if (position > gap[1]) return position - gap[1];
    return 0;
  }
  final limit = queryLength * kSeamMatchRatio;

  // 単調な割り当て（追い越さない）のうち、ずれの合計が最小のものを選ぶ。
  //
  // 切れ目に途切れが付かないこと（繋がっている音節）と、途切れが切れ目に
  // 対応しないこと（軋み声で声が落ちた）の両方を許す。
  const infinity = double.infinity;
  double distanceOf(int seam, int gap) =>
      distanceTo(voicelessGaps[gap], expected[seam]);

  final best = List.generate(
    seams.length + 1,
    (_) => List<double>.filled(voicelessGaps.length + 1, infinity),
  );
  for (var g = 0; g <= voicelessGaps.length; g++) {
    best[seams.length][g] = 0;
  }
  for (var i = seams.length - 1; i >= 0; i--) {
    for (var g = voicelessGaps.length; g >= 0; g--) {
      // **切れ目に付けないことにだけ費用を置く。** 置かないと「何も割り当て
      // ない」が費用0で最適になり、どの切れ目にも錨が付かない。
      //
      // 逆に**途切れを飛ばすのは無料**にする。途切れは切れ目より多いのが普通で
      // （軋み声、子音の中の揺れ）、飛ばすたびに罰すると、手前の近い途切れに
      // 引きずられて奥の正しい途切れへ辿り着けない。
      var value = limit + best[i + 1][g]; // この切れ目には付けない
      if (g < voicelessGaps.length) {
        final skipGap = best[i][g + 1]; // この途切れは切れ目ではない
        if (skipGap < value) value = skipGap;
        final distance = distanceOf(i, g);
        if (distance <= limit) {
          final matched = distance + best[i + 1][g + 1];
          if (matched < value) value = matched;
        }
      }
      best[i][g] = value;
    }
  }

  final anchors = <int, List<int>>{};
  var seam = 0;
  var gap = 0;
  while (seam < seams.length && gap < voicelessGaps.length) {
    final distance = distanceOf(seam, gap);
    final matched =
        distance <= limit ? distance + best[seam + 1][gap + 1] : infinity;
    final skipSeam = limit + best[seam + 1][gap];
    final skipGap = best[seam][gap + 1];
    if (matched <= skipSeam && matched <= skipGap) {
      anchors[seams[seam]] = voicelessGaps[gap];
      seam++;
      gap++;
    } else if (skipSeam <= skipGap) {
      seam++;
    } else {
      gap++;
    }
  }
  return anchors;
}

/// 錨（[assignGapsToSeams]）を通る折れ線で、お手本の各点の予想位置を作る。
///
/// 錨と錨の間は予算比で分ける。**繋がっている音節（途切れが出ない境界）は
/// この区間の中で配分される**ので、予算の誤差が及ぶ範囲がその区間に限られる。
List<double> referenceToQueryFrom({
  required int referenceLength,
  required int queryLength,
  required Map<int, List<int>> anchors,
}) {
  final points = <int, double>{0: 0, referenceLength - 1: (queryLength - 1).toDouble()};
  anchors.forEach((refIndex, gap) {
    if (refIndex > 0 && refIndex < referenceLength - 1) {
      points[refIndex] = (gap[0] + gap[1]) / 2;
    }
  });
  final keys = points.keys.toList()..sort();

  final map = List<double>.filled(referenceLength, 0);
  for (var k = 0; k + 1 < keys.length; k++) {
    final fromRef = keys[k];
    final toRef = keys[k + 1];
    final fromQuery = points[fromRef]!;
    final toQuery = points[toRef]!;
    for (var i = fromRef; i <= toRef; i++) {
      final ratio = toRef == fromRef ? 0.0 : (i - fromRef) / (toRef - fromRef);
      map[i] = fromQuery + (toQuery - fromQuery) * ratio;
    }
  }
  return map;
}

/// 手がかりの無い切れ目を、予算どおりの位置に押さえる窓の幅（録音長に対する割合）。
///
/// **手がかりが無いなら、DTW に選ばせてはいけない。** 実機で、共鳴音で繋がり
/// （`ชิ้น` น → `นี้` น）かつ**両方とも同じ声調**という、音響的にも声調的にも
/// 境界を決められない組が出た。同じ文を9回録ると、2音節の合計は毎回 28〜38% と
/// ほぼ一定なのに、その中の分け方が毎回反転し、どちらかが有声5フレーム未満に
/// なって採点不能になった。
///
/// 錨と錨の間なら予算の誤差はその区間に閉じているので、予算どおりに置くほうが
/// 当てずっぽうよりましで、**何より毎回同じ結果になる**。
const double kUnanchoredSeamWindowRatio = 0.03;

/// 全ての音節の切れ目に「録音側のこの範囲を通れ」を作る。
///
/// 途切れが割り当たった切れ目はその途切れの中。割り当たらなかった切れ目は、
/// 錨を通る折れ線（[referenceToQueryFrom]）の上の位置を狭く押さえる。
Map<int, List<int>> seamWindowsFrom({
  required ReferenceContour reference,
  required Map<int, List<int>> anchors,
  required List<double> referenceToQuery,
  required int queryLength,
}) {
  final windows = <int, List<int>>{};
  final half = (queryLength * kUnanchoredSeamWindowRatio).round().clamp(1, queryLength);
  for (var syllable = 1; syllable < reference.syllableCount; syllable++) {
    final refIndex = reference.starts[syllable];
    final anchor = anchors[refIndex];
    if (anchor != null) {
      windows[refIndex] = anchor;
      continue;
    }
    if (refIndex >= referenceToQuery.length) continue;
    final center = referenceToQuery[refIndex].round();
    windows[refIndex] = [
      (center - half).clamp(0, queryLength - 1),
      (center + half).clamp(0, queryLength - 1),
    ];
  }
  return windows;
}

/// 録音1回を採点する。
///
/// [f0Hz] はフレームごとのF0。無声・低信頼のフレームは null。
/// [tones] は例文の音節の声調列（`WordBreakdown.syllables` を語順に連結したもの）。
/// [shortSyllables] は声調の形を出しきれない音節（短母音・死音節）。
/// [syllablePoints] は音節ごとの時間の取り分（[syllablePointsFor]）。
/// [energy] はフレームごとの音量。渡すと、共鳴音で繋がる切れ目（F0 にも無声区間
/// にも現れない）を音量の谷から拾える。
/// [profile] は過去の録音から蓄積した声域。初回は null でよい。
/// [recognition] は語ごとの「通じたか」（[matchTranscript]）。総合点に掛ける。
/// 端末が音声認識に対応していない場合は空、または全て
/// [WordRecognition.unavailable] でよい（減点しない）。
PronunciationResult analyzePronunciation({
  required List<double?> f0Hz,
  required List<ThaiTone> tones,
  List<bool>? shortSyllables,
  List<int>? syllablePoints,
  List<double> energy = const [],
  SpeakerPitchProfile? profile,
  List<WordRecognition> recognition = const [],
  double minVoicedRatio = kMinVoicedRatio,
}) {
  if (tones.isEmpty) {
    return PronunciationResult.failed(PronunciationFailure.noSyllables);
  }

  // 1フレームも届いていないのは「声が小さい」ではなく収録経路の問題。
  // 静かな場所へ移動しても直らないので、案内を分ける。
  if (f0Hz.isEmpty) {
    return PronunciationResult.failed(PronunciationFailure.captureFailed);
  }

  // 補間の前後を両方持つ。補間したフレームは時間軸を保つために要るが、
  // 実際の声ではないので採点には使わない。
  final measured = medianFilter(toSemitones(f0Hz));
  final semitones = interpolateShortGaps(measured);
  if (voicedRatio(measured) < minVoicedRatio) {
    return PronunciationResult.failed(PronunciationFailure.tooQuiet);
  }

  final freshRange = estimateSpeakerRange(semitones);
  final range = freshRange ?? profile?.range;
  if (range == null) {
    return PronunciationResult.failed(PronunciationFailure.noSpeakerRange);
  }

  // **発話の途中の無声区間を落としてはいけない。** 閉鎖音の閉鎖区間は 120ms を
  // 超えることがあり（[kMaxInterpolatedGap] の外）、そこを削ると時間軸が縮む。
  // しかも縮み方が音節ごとに違う（死音節ほど無声が長いので多く削られる）。
  // **時間軸の比例関係は DTW の帯が前提にしている**ので、これを壊すと境界が
  // 帯に張り付いて動けなくなる。
  //
  // 実機で 460 フレーム中 161 が消え、死音節の取り分が予算の 0.4〜0.8 倍に
  // 出ていた。母音の長短のモデルではなく、比べていた実測値のほうが歪んでいた。
  //
  // 長さの制限なしで補間して埋める。値は前後の線形補間なので声域も形も動かさず、
  // [queryVoiced] で「実際の声ではない」と印を付けるので採点にも入らない。
  // 前後の無音は補間されない（片側に声が無い）ので、そこだけを切り落とす。
  final filled = normalizeToSpeakerRange(
    interpolateShortGaps(measured, maxGap: measured.length),
    range,
  );
  // **端は「声が続いているところ」で決める。** 単発の有声フレームを発話の
  // 始まりにすると、その後の長い無音が丸ごと最初の音節に入る。
  final span = speechSpan(measured);
  final first = span?[0] ?? -1;
  final last = span?[1] ?? -1;

  final queryZ = <double>[];
  final queryVoiced = <bool>[];
  if (first >= 0) {
    for (var i = first; i <= last; i++) {
      final v = filled[i];
      if (v == null) continue;
      queryZ.add(v);
      queryVoiced.add(measured[i] != null);
    }
  }
  if (queryZ.isEmpty) {
    return PronunciationResult.failed(PronunciationFailure.tooQuiet);
  }

  final reference = ReferenceContour.fromTones(
    tones,
    shortSyllables: shortSyllables,
    syllablePoints: syllablePoints,
  );
  // 声の途切れを音節の切れ目へ寄せるため、お手本のどの点が音節の端かを渡す。
  final atBoundary = List.generate(
    reference.values.length,
    (i) => reference.isEdgePoint(i, kBoundaryZoneFraction),
  );
  // 声の途切れと音量の谷を音節の切れ目に割り当て、そこを通る折れ線で帯を引き直す。
  final gaps = findVoicelessGaps(queryVoiced);
  // 音量は録音そのものの添字なので、切り落とした先頭ぶんをずらして合わせる。
  final trimmedEnergy = energy.isEmpty || first < 0
      ? const <double>[]
      : energy.sublist(
          first.clamp(0, energy.length),
          (last + 1).clamp(0, energy.length),
        );
  // まず途切れだけで決める。谷は残った切れ目の穴埋めにだけ使う。
  final gapAnchors = assignGapsToSeams(
    reference: reference,
    voicelessGaps: gaps,
    queryLength: queryZ.length,
  );
  final anchors = fillSeamsWithValleys(
    reference: reference,
    anchors: gapAnchors,
    valleys: findEnergyValleys(trimmedEnergy),
    referenceToQuery: referenceToQueryFrom(
      referenceLength: reference.values.length,
      queryLength: queryZ.length,
      anchors: gapAnchors,
    ),
    queryLength: queryZ.length,
  );
  final referenceToQuery = referenceToQueryFrom(
    referenceLength: reference.values.length,
    queryLength: queryZ.length,
    anchors: anchors,
  );
  final path = dtwAlign(
    reference.values,
    queryZ,
    queryVoiced: queryVoiced,
    referenceAtBoundary: atBoundary,
    referenceToQuery: referenceToQuery,
    boundaryWindows: seamWindowsFrom(
      reference: reference,
      anchors: anchors,
      referenceToQuery: referenceToQuery,
      queryLength: queryZ.length,
    ),
  );
  final scores = scoreSyllables(
    reference: reference,
    queryZ: queryZ,
    queryVoiced: queryVoiced,
    path: path,
  );

  // 声調と発音を半々で見る。声調だけで点を出すと「全部通じていないのに高得点」
  // になり、発音の軸が点数に効かない。
  final toneScore = overallScoreOf(scores);

  return PronunciationResult(
    syllables: scores,
    overallScore: combinedScore(toneScore, recognition),
    toneScore: toneScore,
    failure: PronunciationFailure.none,
    speakerRange: range,
    freshRange: freshRange,
    voicelessGaps: findVoicelessGaps(queryVoiced),
  );
}
