import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../data/models/thai_sentence.dart';

/// 例文中の学習単語を金で光らせる。学習タブと例文詳細で同じ見え方にするため、
/// 描画のしかたはここに1つだけ置く。

/// タイ文字の本文。学習単語だけ金の面に載せて太字にする。
TextSpan buildHighlightedThaiText(
  String text,
  List<String> targetWords,
  TextStyle baseStyle,
  Color highlightColor,
) {
  if (targetWords.isEmpty) {
    return TextSpan(text: text, style: baseStyle);
  }
  final sorted = [...targetWords]..sort((a, b) => b.length.compareTo(a.length));
  final regex = RegExp(sorted.map(RegExp.escape).join('|'));
  final spans = <InlineSpan>[];
  var lastEnd = 0;
  final highlightStyle = baseStyle.copyWith(
    color: highlightColor,
    fontWeight: FontWeight.bold,
  );
  for (final match in regex.allMatches(text)) {
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
  Color tint,
) {
  if (targetWords.isEmpty) {
    return TextSpan(text: text, style: baseStyle);
  }
  final sorted = [...targetWords]..sort((a, b) => b.length.compareTo(a.length));
  final regex = RegExp(sorted.map(RegExp.escape).join('|'));
  final spans = <InlineSpan>[];
  var lastEnd = 0;
  for (final match in regex.allMatches(text)) {
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
