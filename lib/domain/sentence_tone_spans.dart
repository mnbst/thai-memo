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

  const SentenceToneSpans({required this.tones, required this.words});

  bool get isEmpty => tones.isEmpty;
}

/// 単語分解から声調列と語の区切りを組み立てる。
///
/// 音節データを持たない語は飛ばす。サーバーが音節を返さなかった古い例文が
/// 混ざっても、残りの語だけで練習できるようにするため。
SentenceToneSpans buildSentenceToneSpans(List<WordBreakdown> words) {
  final tones = <ThaiTone>[];
  final spans = <WordToneSpan>[];

  for (final word in words) {
    final syllables = word.syllables;
    if (syllables == null || syllables.isEmpty) continue;

    spans.add(WordToneSpan(
      wordText: word.wordText,
      start: tones.length,
      length: syllables.length,
    ));
    tones.addAll(syllables.map((s) => toneFromName(s.tone)));
  }

  return SentenceToneSpans(tones: tones, words: spans);
}
