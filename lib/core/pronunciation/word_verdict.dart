// =============================================================================
// word_verdict.dart
// 語ごとの判定を1つにまとめる。
//
// 声調（ピッチ）と発音（通じたか）は別軸の検査だが、帯を2本並べると
// 実機では単に鬱陶しく、どちらを見ればよいのか分からない。帯は1本にして
// 「言い直す必要があるか」だけを伝え、内訳は語をタップしたときに出す。
// =============================================================================

import 'pronunciation_scorer.dart';
import 'transcript_match.dart';

/// 語に含まれる音節のうち、どれだけ合っていれば語として合格とみなすか。
///
/// 実機で確かめたところ 0.75 では緩く、2音節の語は片方を落としても○のままで
/// （(1+0.5)/2 = 0.75）、直すべき語が緑に見えていた。**ほぼ全部合っている**
/// ことを求める。
///
/// 1にはしない。1音節でも外すと語全体が×になる作りだと、大半が合っている語まで
/// 赤くなり、どこを直せばよいのか分からない。
const double kWordCorrectRatio = 0.9;

/// これを下回ると語として「違う」。
const double kWordCloseRatio = 0.4;

/// 語の声調判定を、含まれる音節の合い具合の割合から決める。
///
/// 「惜しい」は半分として数える。音節ごとの内訳は語をタップすれば見られるので、
/// 帯は語として言い直す必要があるかどうかだけを伝える。
ToneVerdict toneVerdictOfWord(Iterable<SyllableScore> scores) {
  final scored =
      scores.where((s) => s.verdict != ToneVerdict.unscored).toList();
  if (scored.isEmpty) return ToneVerdict.unscored;

  var total = 0.0;
  for (final score in scored) {
    switch (score.verdict) {
      case ToneVerdict.correct:
        total += 1;
      case ToneVerdict.close:
        total += 0.5;
      case ToneVerdict.wrong:
      case ToneVerdict.unscored:
        break;
    }
  }

  final ratio = total / scored.length;
  if (ratio >= kWordCorrectRatio) return ToneVerdict.correct;
  if (ratio >= kWordCloseRatio) return ToneVerdict.close;
  return ToneVerdict.wrong;
}

/// 声調と発音を合わせた、語ひとつの総合判定。
///
/// 音声認識は**見逃す方向に甘い**（言語モデルが期待される語へ補正する）ので、
/// 通じたことは加点にしない。声調の判定をそのまま通す。
///
/// 逆に**認識されなかった語は、声調が合っていても `wrong`** にする。
/// 帯が伝えるのは「この語を言い直す必要があるか」であり、通じていない語は
/// 声調が合っていても言い直す必要がある。声調が正しいことは慰めにならない。
///
/// 当初は一段だけ下げていたが（○→惜しい）、それでは発音の軸が単独では
/// 何も落とせず、判定にほとんど効かなかった。認識が落ちる原因は発音以外
/// （雑音・語彙）にもあるが、認識器はそもそも期待される語へ補正して返すので、
/// それでも通らなかったことのほうが強い信号。
ToneVerdict combinedWordVerdict(ToneVerdict tone, WordRecognition recognition) {
  switch (recognition) {
    case WordRecognition.recognized:
    case WordRecognition.unavailable:
      return tone;
    case WordRecognition.missing:
      return ToneVerdict.wrong;
  }
}

/// 総合点に占める声調の重み。残りが発音（通じたか）。
///
/// 半々。どちらかを外していれば語として通じないので、優劣を付ける理由がない。
const double kToneScoreWeight = 0.5;

/// 声調の点数と発音（通じたか）を合わせた総合点（0〜100）。
///
/// 発音の側は、判定できた語のうち通じた語の割合をそのまま点にする。
///
/// **判定していない端末では声調の点をそのまま返す。** 判定できないことと、
/// 判定して駄目だったことを混同させない。ここで発音側を満点として足すと、
/// 対応していない端末のほうが点が出やすくなる。
double combinedScore(double toneScore, List<WordRecognition> recognition) {
  final judged =
      recognition.where((r) => r != WordRecognition.unavailable).toList();
  if (judged.isEmpty) return toneScore;

  final recognized =
      judged.where((r) => r == WordRecognition.recognized).length;
  final speechScore = 100 * recognized / judged.length;

  return toneScore * kToneScoreWeight + speechScore * (1 - kToneScoreWeight);
}
