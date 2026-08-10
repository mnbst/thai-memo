// =============================================================================
// sentence_tone_spans.dart
// 例文の単語分解から、発音判定に渡す音節の声調列と、語↔音節の対応を作る。
//
// 判定は音節ごとに行うが、結果は語ごとにまとめて見せる。文が20〜30音節になると
// 音節をそのまま並べても読めないため。この対応づけをここで持つ。
// =============================================================================

import '../core/pronunciation/tone_contour.dart';
import '../core/thai_tone_analyzer.dart';
import '../data/models/word_breakdown.dart';

/// 1語が占める音節の範囲。
class WordToneSpan {
  final String wordText;

  /// 音節列における開始位置。
  final int start;

  /// 音節数。
  final int length;

  const WordToneSpan({
    required this.wordText,
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
    this.syllableLabels = const [],
    this.toneMarks = const [],
    this.syllableRomans = const [],
  });

  bool get isEmpty => tones.isEmpty;
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

SentenceToneSpans buildSentenceToneSpans(List<WordBreakdown> words) {
  final tones = <ThaiTone>[];
  final spans = <WordToneSpan>[];
  final short = <bool>[];
  final points = <int>[];
  final labels = <String>[];
  final marks = <String>[];
  final romans = <String>[];

  for (final word in words) {
    final syllables = word.syllables;
    if (syllables == null || syllables.isEmpty) continue;

    spans.add(WordToneSpan(
      wordText: word.wordText,
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
  }

  return SentenceToneSpans(
    tones: tones,
    words: spans,
    shortSyllables: short,
    syllablePoints: points,
    syllableLabels: labels,
    toneMarks: marks,
    syllableRomans: romans,
  );
}
