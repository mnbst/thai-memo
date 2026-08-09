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
/// 1音節でも外すと語全体が×になる作りだと、大半が合っている語まで赤くなり、
/// どこを直せばよいのか分からない。8割ほど合っていれば合格として扱う。
const double kWordCorrectRatio = 0.75;

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
/// 逆に認識されなかったときは「通じないレベルで外している」という強い信号なので、
/// 声調が合っていても一段下げる。
///
/// 一段だけに留めるのは、認識が落ちる原因が発音以外（雑音・語彙）にもあるため。
/// 声調も発音も外していれば、どちらの経路からも `wrong` になる。
ToneVerdict combinedWordVerdict(ToneVerdict tone, WordRecognition recognition) {
  switch (recognition) {
    case WordRecognition.recognized:
    case WordRecognition.unavailable:
      return tone;
    case WordRecognition.missing:
      switch (tone) {
        case ToneVerdict.correct:
          return ToneVerdict.close;
        case ToneVerdict.close:
        case ToneVerdict.wrong:
          return ToneVerdict.wrong;
        case ToneVerdict.unscored:
          // 声調は測れていないが、通じなかったことは分かっている。
          return ToneVerdict.wrong;
      }
  }
}
