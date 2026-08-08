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

  /// 0〜100。[failure] が [PronunciationFailure.none] のときだけ意味を持つ。
  final double overallScore;

  final PronunciationFailure failure;

  /// 採点に使った声域。
  final SpeakerRange? speakerRange;

  /// この録音だけから推定できた声域。
  ///
  /// 取れた場合のみ非 null。呼び出し側はこれを [SpeakerPitchProfile] に
  /// 取り込んで永続化する。蓄積プロファイルで代用した回は反映しない
  /// （推定値を推定値で上書きして誤差が積み上がるのを避けるため）。
  final SpeakerRange? freshRange;

  const PronunciationResult({
    required this.syllables,
    required this.overallScore,
    required this.failure,
    this.speakerRange,
    this.freshRange,
  });

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

/// 録音1回を採点する。
///
/// [f0Hz] はフレームごとのF0。無声・低信頼のフレームは null。
/// [tones] は例文の音節の声調列（`WordBreakdown.syllables` を語順に連結したもの）。
/// [profile] は過去の録音から蓄積した声域。初回は null でよい。
PronunciationResult analyzePronunciation({
  required List<double?> f0Hz,
  required List<ThaiTone> tones,
  SpeakerPitchProfile? profile,
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

  final semitones = preparePitchTrack(f0Hz);
  if (voicedRatio(semitones) < minVoicedRatio) {
    return PronunciationResult.failed(PronunciationFailure.tooQuiet);
  }

  final freshRange = estimateSpeakerRange(semitones);
  final range = freshRange ?? profile?.range;
  if (range == null) {
    return PronunciationResult.failed(PronunciationFailure.noSpeakerRange);
  }

  // 無声フレームは落とす。ピッチを持たず比較できないため。
  // 前後関係は DTW が単調に保つので、時間軸の情報が失われても対応づけは崩れない。
  final queryZ = normalizeToSpeakerRange(semitones, range)
      .whereType<double>()
      .toList();
  if (queryZ.isEmpty) {
    return PronunciationResult.failed(PronunciationFailure.tooQuiet);
  }

  final reference = ReferenceContour.fromTones(tones);
  final path = dtwAlign(reference.values, queryZ);
  final scores = scoreSyllables(
    reference: reference,
    queryZ: queryZ,
    path: path,
  );

  return PronunciationResult(
    syllables: scores,
    overallScore: overallScoreOf(scores),
    failure: PronunciationFailure.none,
    speakerRange: range,
    freshRange: freshRange,
  );
}
