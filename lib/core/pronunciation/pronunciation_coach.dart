// =============================================================================
// pronunciation_coach.dart
// 採点結果から「次の1回で何を直すか」を1つだけ選ぶ。
//
// 外した音節を全部並べても直せない。人が1回の言い直しで意識できるのは1点なので、
// **最も多く外している (声調 × 外し方) を1つだけ返す**。
//
// 外し方の軸は採点が使っている2つ（形・入り方）をそのまま使う。ここで新しい
// 基準を作ると、帯の色と助言が食い違う。
// =============================================================================

import '../thai_tone_analyzer.dart';
import 'pronunciation_scorer.dart';
import 'transcript_match.dart';

/// 何を外しているか。
enum CoachIssue {
  /// 声調の形（上がる／下がる）が出ていない。
  shape,

  /// 直前の音節からの入り方（高く入るか低く入るか）が逆。
  step,

  /// 声調は外していないが、その語が聞き取られなかった。
  notRecognized,
}

/// 次の1回で直す点。
class CoachingTip {
  const CoachingTip({
    required this.issue,
    this.tone,
    this.syllableIndex,
    this.stepUp = false,
    this.wordText,
    this.toneMark = '',
    this.roman = '',
  });

  final CoachIssue issue;

  /// 直す対象の声調。[CoachIssue.notRecognized] では null。
  final ThaiTone? tone;

  /// 代表として選んだ音節（同点なら文の先頭に近いもの）。
  /// [CoachIssue.notRecognized] では null。
  final int? syllableIndex;

  /// [CoachIssue.step] のとき、お手本が直前より高く入るなら true。
  /// 他の [issue] では意味を持たない。
  final bool stepUp;

  /// [CoachIssue.notRecognized] で名指しする語。他では null。
  final String? wordText;

  /// [syllableIndex] の音節に実際に書かれている声調記号。無ければ空文字。
  ///
  /// **声調から引いた記号ではない。** 無記号でも声調は決まるので、
  /// 空文字は正常な状態であって、欠損ではない。
  final String toneMark;

  /// [syllableIndex] の音節の、声調記号付きローマ字。取れなければ空文字。
  final String roman;
}

/// 採点結果から助言を1つ選ぶ。直すところが無ければ null。
///
/// 声調を先に見る。声調は音節ごとに形と入り方まで分かるので**どう直すか**を
/// 言えるが、音声認識は「通じなかった」しか返さず、原因を特定できない。
/// 具体的に直せる方を優先する。
///
/// `wrong` を優先し、無ければ `close` を見る。全部合っている回に「ここを直せ」
/// と出すと、判定そのものを信用されなくなる。
///
/// [recognition] と [wordTexts] は語順で対応する同じ長さの列。省略すると
/// 声調だけを見る。
///
/// [toneMarks] と [romans] は音節順（[SyllableScore.syllableIndex] で引く）。
CoachingTip? coachingTipOf(
  Iterable<SyllableScore> scores, {
  List<WordRecognition> recognition = const [],
  List<String> wordTexts = const [],
  List<String> toneMarks = const [],
  List<String> romans = const [],
}) {
  final list = scores.toList();

  final tip = _tipAmong(list, ToneVerdict.wrong) ??
      _tipAmong(list, ToneVerdict.close);
  if (tip != null) return _withSyllableLabels(tip, toneMarks, romans);

  // 声調は通っているのに帯が赤い場合がここ。**帯が赤いのに助言が空**という
  // 状態を作らないために、言えることだけ言う（語を名指しして言い直しを促す）。
  return _notRecognizedTip(recognition, wordTexts);
}

/// 代表音節の表記（声調記号・ローマ字）を載せる。取れないものは空のまま。
CoachingTip _withSyllableLabels(
  CoachingTip tip,
  List<String> toneMarks,
  List<String> romans,
) {
  final index = tip.syllableIndex;
  if (index == null || index < 0) return tip;

  String at(List<String> source) =>
      index < source.length ? source[index] : '';

  return CoachingTip(
    issue: tip.issue,
    tone: tip.tone,
    syllableIndex: index,
    stepUp: tip.stepUp,
    wordText: tip.wordText,
    toneMark: at(toneMarks),
    roman: at(romans),
  );
}

/// 聞き取られなかった最初の語を指す。原因は特定しない。
CoachingTip? _notRecognizedTip(
  List<WordRecognition> recognition,
  List<String> wordTexts,
) {
  final count =
      recognition.length < wordTexts.length ? recognition.length : wordTexts.length;
  for (var i = 0; i < count; i++) {
    if (recognition[i] != WordRecognition.missing) continue;
    final text = wordTexts[i].trim();
    if (text.isEmpty) continue;
    return CoachingTip(issue: CoachIssue.notRecognized, wordText: text);
  }
  return null;
}

CoachingTip? _tipAmong(List<SyllableScore> scores, ToneVerdict verdict) {
  // (声調, 外し方) ごとに、件数と代表の音節を集める。
  final counts = <String, int>{};
  final firstOf = <String, SyllableScore>{};
  final issueOf = <String, CoachIssue>{};

  for (final s in scores) {
    if (s.verdict != verdict) continue;
    // 声調が決まらない音節に助言はできない。
    if (s.tone == ThaiTone.unknown) continue;

    final issue = _issueOf(s);
    if (issue == null) continue;

    final key = '${s.tone.name}:${issue.name}';
    counts[key] = (counts[key] ?? 0) + 1;
    if (!firstOf.containsKey(key)) {
      firstOf[key] = s;
      issueOf[key] = issue;
    }
  }

  if (counts.isEmpty) return null;

  // 最多。同数なら文の先頭に近い方を採る（言い直すとき最初に来る）。
  var bestKey = counts.keys.first;
  for (final key in counts.keys) {
    final better = counts[key]! > counts[bestKey]! ||
        (counts[key] == counts[bestKey] &&
            firstOf[key]!.syllableIndex < firstOf[bestKey]!.syllableIndex);
    if (better) bestKey = key;
  }

  final representative = firstOf[bestKey]!;
  return CoachingTip(
    tone: representative.tone,
    issue: issueOf[bestKey]!,
    syllableIndex: representative.syllableIndex,
    stepUp: representative.referenceStep > 0,
  );
}

/// この音節が外しているのはどちらの軸か。
///
/// 形を先に見る。形は声調そのものの動きで、入り方は前の音節との関係なので、
/// **形が出ていないなら、まずそこ**。両方 null（測れていない）なら助言しない。
CoachIssue? _issueOf(SyllableScore score) {
  if (score.shapeAgrees == false) return CoachIssue.shape;
  if (score.stepAgrees == false) return CoachIssue.step;
  return null;
}
