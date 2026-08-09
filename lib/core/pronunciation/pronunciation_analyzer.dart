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

/// 声が途切れた区間（[開始, 終了]、終了を含む）を拾う。
///
/// [voiced] は各フレームが実際に声だったか。false は補間で埋めたフレーム。
List<List<int>> findVoicelessGaps(List<bool> voiced) {
  final gaps = <List<int>>[];
  var start = -1;
  for (var i = 0; i < voiced.length; i++) {
    if (!voiced[i]) {
      if (start < 0) start = i;
      continue;
    }
    if (start >= 0) {
      if (i - start >= kMinVoicelessGapFrames) gaps.add([start, i - 1]);
      start = -1;
    }
  }
  if (start >= 0 && voiced.length - start >= kMinVoicelessGapFrames) {
    gaps.add([start, voiced.length - 1]);
  }
  return gaps;
}

/// 録音1回を採点する。
///
/// [f0Hz] はフレームごとのF0。無声・低信頼のフレームは null。
/// [tones] は例文の音節の声調列（`WordBreakdown.syllables` を語順に連結したもの）。
/// [shortSyllables] は声調の形を出しきれない音節（短母音・死音節）。
/// [syllablePoints] は音節ごとの時間の取り分（[syllablePointsFor]）。
/// [profile] は過去の録音から蓄積した声域。初回は null でよい。
/// [recognition] は語ごとの「通じたか」（[matchTranscript]）。総合点に掛ける。
/// 端末が音声認識に対応していない場合は空、または全て
/// [WordRecognition.unavailable] でよい（減点しない）。
PronunciationResult analyzePronunciation({
  required List<double?> f0Hz,
  required List<ThaiTone> tones,
  List<bool>? shortSyllables,
  List<int>? syllablePoints,
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
  final first = filled.indexWhere((v) => v != null);
  final last = filled.lastIndexWhere((v) => v != null);

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
  final path = dtwAlign(
    reference.values,
    queryZ,
    queryVoiced: queryVoiced,
    referenceAtBoundary: atBoundary,
  );
  final scores = scoreSyllables(
    reference: reference,
    queryZ: queryZ,
    queryVoiced: queryVoiced,
    path: path,
    shortSyllables: shortSyllables,
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
