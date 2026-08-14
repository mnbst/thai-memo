// =============================================================================
// sentence_tone_spans.dart
// 例文の単語分解から、発音判定に渡す音節の声調列と、語↔音節の対応を作る。
//
// 判定は音節ごとに行うが、結果は語ごとにまとめて見せる。文が20〜30音節になると
// 音節をそのまま並べても読めないため。この対応づけをここで持つ。
// =============================================================================

import '../core/pronunciation/segment_coach.dart';
import '../core/pronunciation/tone_contour.dart';
import '../core/thai_tone_analyzer.dart';
import '../data/models/word_breakdown.dart';

/// 1語が占める音節の範囲。
class WordToneSpan {
  final String wordText;

  /// 語の発音表記（音節はハイフン区切り）。
  final String pronunciation;

  /// 音節列における開始位置。
  final int start;

  /// 音節数。
  final int length;

  const WordToneSpan({
    required this.wordText,
    this.pronunciation = '',
    required this.start,
    required this.length,
  });

  /// この語に属する音節の添字（終端は含まない）。
  int get end => start + length;

  bool contains(int syllableIndex) =>
      syllableIndex >= start && syllableIndex < end;
}

/// 例文の声調列と、語ごとの区切り。
class SentenceToneSpans {
  /// 文全体の音節の声調（語順に連結）。
  final List<ThaiTone> tones;

  /// 語ごとの音節範囲。
  final List<WordToneSpan> words;

  /// 音節ごとに、声調の形を出しきれない長さか（[tones] と同じ順）。
  ///
  /// 短母音や死音節（末子音で閉じる音節）は時間が足りず、上昇声・下降声でも
  /// 動きが完了しない。**この音節は形ではなく隣との高低差で判断する。**
  final List<bool> shortSyllables;

  /// 音節ごとの、お手本での時間の取り分（[syllablePointsFor]）。
  ///
  /// [shortSyllables] とは別に持つ。あちらは「動きを出しきれるか」、
  /// こちらは「どれだけの長さか」で、判断の基準が違う。
  final List<int> syllablePoints;

  /// 音節ごとの「表記/長さの分類」（[tones] と同じ順）。
  ///
  /// 時間の取り分（[syllablePoints]）は表記から決めているので、実際の発話の
  /// 長さと食い違ったときに**どの語のどの判定が原因か**を追えなければ直せない。
  /// 判定には使わない、ログのためだけの文字列。
  final List<String> syllableLabels;

  /// 音節ごとに、実際に書かれている声調記号（[tones] と同じ順）。
  ///
  /// 記号を持たない音節は空文字。**声調から引いた対応表ではない**
  /// （同じ記号でも子音クラスで声調が変わるため、逆引きは成立しない）。
  final List<String> toneMarks;

  /// 音節ごとの、子音・母音の助言に要る材料（[tones] と同じ順）。
  ///
  /// 声調の判定には使わない。通じなかった語について「どの音を直すか」を選ぶため
  /// だけに持つ（[segmentPointOfWord]）。
  final List<SegmentSyllable> segmentSyllables;

  /// 新しい節が始まる音節の添字（昇順）。
  ///
  /// `thai_text` の空白＝節の切れ目。話者はそこで息を継いで**声を上げ直す**ので、
  /// 声調のお手本は節ごとに引き直す必要がある（[ReferenceContour.clauseStarts]）。
  final List<int> clauseStarts;

  /// 音節ごとの、声調記号付きローマ字（[tones] と同じ順）。取れなければ空文字。
  ///
  /// 語の発音表記をハイフンで割って音節に対応づける。**ローマ字は TLTK、
  /// 音節分割は PyThaiNLP と出所が違う**ので、数が食い違う語がある。
  /// その語は全て空にする（ずれたまま名指しすると助言が別の音節を指す）。
  final List<String> syllableRomans;

  const SentenceToneSpans({
    required this.tones,
    required this.words,
    required this.shortSyllables,
    required this.syllablePoints,
    this.segmentSyllables = const [],
    this.clauseStarts = const [],
    this.syllableLabels = const [],
    this.toneMarks = const [],
    this.syllableRomans = const [],
  });

  bool get isEmpty => tones.isEmpty;

  /// 語ひとつについて、子音・母音のどこを直すかを1つ選ぶ。
  ///
  /// 範囲外の語・材料が無い場合は null。
  SegmentPoint? segmentPointOfWord(int wordIndex) {
    if (wordIndex < 0 || wordIndex >= words.length) return null;
    if (segmentSyllables.isEmpty) return null;

    final span = words[wordIndex];
    return segmentPointOf(
      segmentSyllables,
      start: span.start,
      end: span.end,
    );
  }
}

/// 単語分解から声調列と語の区切りを組み立てる。
///
/// 音節データを持たない語は飛ばす。サーバーが音節を返さなかった古い例文が
/// 混ざっても、残りの語だけで練習できるようにするため。
/// 語の発音表記を音節へ割る。数が合わなければ全て空文字で返す。
///
/// **数が合わないまま前から詰めてはいけない。** 1つずれるだけで、助言が
/// 別の音節を名指しする。出せないときは出さない方がまだ良い。
List<String> _romansOf(String pronunciation, int syllableCount) {
  final parts = pronunciation
      .split('-')
      .map((p) => p.trim())
      .where((p) => p.isNotEmpty)
      .toList();
  if (parts.length != syllableCount) {
    return List.filled(syllableCount, '');
  }
  return parts;
}

/// 節の切れ目とみなす文字。
///
/// タイ語は語間に空白を置かないので、**空白は節の切れ目**（`thai_text` の空白は
/// 最大1つで、2節あるときの切れ目にだけ置かれる）。句読点も切れ目として扱う。
final RegExp _clauseBreakChars = RegExp(r'[\s​.!?。！？]');

/// 語の直前に節の切れ目がある語の添字を返す。
///
/// 単語分解は空白を語として持たないので、位置は `thai_text` の上で数える。
/// 見つからない語は飛ばす（位置が分からない語で切れ目を作ると、実際とは違う
/// ところで声を上げ直すお手本になる）。
Set<int> _wordsAfterClauseBreak(List<WordBreakdown> words, String thaiText) {
  if (thaiText.isEmpty) return const {};

  final result = <int>{};
  var cursor = 0;
  for (var i = 0; i < words.length; i++) {
    final text = words[i].wordText;
    if (text.isEmpty) continue;
    final at = thaiText.indexOf(text, cursor);
    if (at < 0) continue;
    if (i > 0 &&
        at > cursor &&
        _clauseBreakChars.hasMatch(thaiText.substring(cursor, at))) {
      result.add(i);
    }
    cursor = at + text.length;
  }
  return result;
}

/// [thaiText] を渡すと、節の切れ目（空白）を [SentenceToneSpans.clauseStarts]
/// として拾う。省略すると1節の文として扱う。
SentenceToneSpans buildSentenceToneSpans(
  List<WordBreakdown> words, {
  String thaiText = '',
}) {
  final tones = <ThaiTone>[];
  final spans = <WordToneSpan>[];
  final short = <bool>[];
  final points = <int>[];
  final labels = <String>[];
  final marks = <String>[];
  final romans = <String>[];
  final segments = <SegmentSyllable>[];
  final clauseStarts = <int>[];

  final breakBefore = _wordsAfterClauseBreak(words, thaiText);
  // 音節を持たない語は飛ばすので、切れ目は**次に音節を持つ語**まで持ち越す。
  var pendingBreak = false;

  for (var i = 0; i < words.length; i++) {
    final word = words[i];
    if (breakBefore.contains(i)) pendingBreak = true;

    final syllables = word.syllables;
    if (syllables == null || syllables.isEmpty) continue;

    if (pendingBreak && tones.isNotEmpty) clauseStarts.add(tones.length);
    pendingBreak = false;

    spans.add(WordToneSpan(
      wordText: word.wordText,
      pronunciation: word.pronunciation,
      start: tones.length,
      length: syllables.length,
    ));
    tones.addAll(syllables.map((s) => toneFromName(s.tone)));
    // 死音節は末子音で切られるため、短母音でなくても動きが完了しない。
    short.addAll(syllables.map(
      (s) => s.hasShortVowel == true || s.syllableType == 'dead',
    ));
    // 長さは別基準。長母音に閉鎖音が付いただけの音節は長い。
    //
    // อำ / ไอ / ใอ / เอา は**音としては短母音**だが、声調規則の上では生音節なので
    // `hasShortVowel` は false で来る。長さの判定はこちらで足す。
    points.addAll(syllables.map(
      (s) => syllablePointsFor(
        shortVowel: s.hasShortVowel == true ||
            ThaiToneAnalyzer.hasSpecialShortVowel(s.text),
        dead: s.syllableType == 'dead',
      ),
    ));
    labels.addAll(syllables.map(
      (s) => '${s.text}'
          '[${s.hasShortVowel == true || ThaiToneAnalyzer.hasSpecialShortVowel(s.text) ? "短" : "長"}'
          '/${s.syllableType == "dead" ? "死" : "生"}]',
    ));
    marks.addAll(syllables.map((s) => toneMarkCharOf(s.toneMark)));
    romans.addAll(_romansOf(word.pronunciation, syllables.length));
    // 長さは声調規則の生死ではなく実際の長さで見る（[points] と同じ基準）。
    segments.addAll(syllables.map(
      (s) => SegmentSyllable(
        text: s.text,
        initialConsonant: s.initialConsonant,
        hasShortVowel: s.hasShortVowel == true ||
            ThaiToneAnalyzer.hasSpecialShortVowel(s.text),
      ),
    ));
  }

  return SentenceToneSpans(
    tones: tones,
    words: spans,
    shortSyllables: short,
    syllablePoints: points,
    segmentSyllables: segments,
    clauseStarts: clauseStarts,
    syllableLabels: labels,
    toneMarks: marks,
    syllableRomans: romans,
  );
}
