import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../data/models/thai_sentence.dart';
import '../../data/models/word_breakdown.dart';

/// 例文中の学習単語を金で光らせる。学習タブと例文詳細で同じ見え方にするため、
/// 描画のしかたはここに1つだけ置く。

/// 学習単語が「語として」出てくる位置だけを返す。
///
/// 文字列の部分一致だけで光らせると、長い語の中に短い学習単語が含まれる
/// ときに途中まで光る（แล้ว の中の แล、lɛ́ɛw の中の lɛ́ など）。単語分解が
/// 分かっていれば語の切れ目が取れるので、そこに乗った一致だけを採る。
///
/// 単語分解が無いときは空を返す。呼び出し側は従来どおり全ての一致を採る。
Map<int, int> _wordRanges(String text, List<WordBreakdown> words) {
  final ranges = <int, int>{};
  var cursor = 0;
  for (final word in words) {
    final wordText = word.wordText;
    if (wordText.isEmpty) continue;
    final at = text.indexOf(wordText, cursor);
    if (at < 0) continue;
    ranges[at] = at + wordText.length;
    cursor = at + wordText.length;
  }
  return ranges;
}

/// 一致が語1つ分に収まっているか。[ranges] が空なら判定せず全て通す。
bool _isWholeWord(Map<int, int> ranges, int start, int end) =>
    ranges.isEmpty || ranges[start] == end;

/// 発音行で語の切れ目になる文字。
///
/// ハイフンは入れない。多音節語の中の区切り（aa-kàat）なので、これを切れ目に
/// すると1音節だけの学習単語が長い語の途中で光る。
const _pronunciationBreaks = ' \t\n,.!?;:()「」""\'’“”…';

/// 発音行の一致が語まるごとか。前後が行の端か区切り文字であること。
bool _isWholeReading(String text, int start, int end) {
  final before = start == 0 ? ' ' : text[start - 1];
  final after = end >= text.length ? ' ' : text[end];
  return _pronunciationBreaks.contains(before) &&
      _pronunciationBreaks.contains(after);
}

/// タイ文字の本文。学習単語だけ金の面に載せて太字にする。
TextSpan buildHighlightedThaiText(
  String text,
  List<String> targetWords,
  TextStyle baseStyle,
  Color highlightColor, {
  List<WordBreakdown> words = const [],
}) {
  if (targetWords.isEmpty) {
    return TextSpan(text: text, style: baseStyle);
  }
  final sorted = [...targetWords]..sort((a, b) => b.length.compareTo(a.length));
  final regex = RegExp(sorted.map(RegExp.escape).join('|'));
  final ranges = _wordRanges(text, words);
  final spans = <InlineSpan>[];
  var lastEnd = 0;
  final highlightStyle = baseStyle.copyWith(
    color: highlightColor,
    fontWeight: FontWeight.bold,
  );
  for (final match in regex.allMatches(text)) {
    if (!_isWholeWord(ranges, match.start, match.end)) continue;
    if (match.start > lastEnd) {
      spans.add(TextSpan(text: text.substring(lastEnd, match.start)));
    }
    spans.add(
      WidgetSpan(
        alignment: PlaceholderAlignment.baseline,
        baseline: TextBaseline.alphabetic,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: highlightColor.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(match.group(0)!, style: highlightStyle),
        ),
      ),
    );
    lastEnd = match.end;
  }
  if (lastEnd < text.length) {
    spans.add(TextSpan(text: text.substring(lastEnd)));
  }
  return TextSpan(style: baseStyle, children: spans);
}

/// タイ文字の本文のうち、学習単語だけ色を変える。面も太字も持たせない。
///
/// 一覧のように行が並ぶ場所では、金の面が行ごとに散らばって読みにくい。
/// 「どれが学習単語か」だけ分かればよいので、色だけで示す。
TextSpan buildTintedThaiText(
  String text,
  List<String> targetWords,
  TextStyle baseStyle,
  Color tint, {
  List<WordBreakdown> words = const [],
}) {
  if (targetWords.isEmpty) {
    return TextSpan(text: text, style: baseStyle);
  }
  final sorted = [...targetWords]..sort((a, b) => b.length.compareTo(a.length));
  final regex = RegExp(sorted.map(RegExp.escape).join('|'));
  final ranges = _wordRanges(text, words);
  final spans = <InlineSpan>[];
  var lastEnd = 0;
  for (final match in regex.allMatches(text)) {
    if (!_isWholeWord(ranges, match.start, match.end)) continue;
    if (match.start > lastEnd) {
      spans.add(TextSpan(text: text.substring(lastEnd, match.start)));
    }
    spans.add(
      TextSpan(text: match.group(0), style: baseStyle.copyWith(color: tint)),
    );
    lastEnd = match.end;
  }
  if (lastEnd < text.length) {
    spans.add(TextSpan(text: text.substring(lastEnd)));
  }
  return TextSpan(style: baseStyle, children: spans);
}

/// 発音行のうち、学習単語にあたる部分を金にする。
///
/// タイ文字側と同じ語が光ることで、「どの音がその単語か」が結びつく。
/// 単語の発音が文全体の発音にそのまま現れない場合（連音・表記ゆれ）は
/// 光らせずに素のまま出す。無理に部分一致させると別の語を光らせてしまう。
TextSpan buildHighlightedPronunciation(
  ThaiSentence sentence,
  TextStyle baseStyle,
) {
  final text = sentence.pronunciation;
  final targetWords = sentence.targetWords ?? const [];
  if (targetWords.isEmpty || text.isEmpty) {
    return TextSpan(text: text, style: baseStyle);
  }

  final breakdownMap = {
    for (final wb in sentence.wordBreakdowns) wb.wordText: wb.pronunciation,
  };
  final readings = targetWords
      .map((w) => breakdownMap[w] ?? breakdownMap['$wๆ'])
      .whereType<String>()
      .where((r) => r.isNotEmpty && text.contains(r))
      .toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  if (readings.isEmpty) {
    return TextSpan(text: text, style: baseStyle);
  }

  final regex = RegExp(readings.map(RegExp.escape).join('|'));
  final spans = <InlineSpan>[];
  var lastEnd = 0;
  for (final match in regex.allMatches(text)) {
    // 長い語の途中で切り取らない。lɛ́ɛw の頭を lɛ́ として光らせない。
    if (!_isWholeReading(text, match.start, match.end)) continue;
    if (match.start > lastEnd) {
      spans.add(TextSpan(text: text.substring(lastEnd, match.start)));
    }
    spans.add(
      TextSpan(
        text: match.group(0),
        style: baseStyle.copyWith(color: AppColors.gold),
      ),
    );
    lastEnd = match.end;
  }
  if (lastEnd < text.length) {
    spans.add(TextSpan(text: text.substring(lastEnd)));
  }
  return TextSpan(style: baseStyle, children: spans);
}
