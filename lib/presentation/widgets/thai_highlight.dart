import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../data/models/thai_sentence.dart';
import '../../data/models/word_breakdown.dart';

/// 例文中の学習単語を金で光らせる。学習タブと例文詳細で同じ見え方にするため、
/// 描画のしかたはここに1つだけ置く。

/// ไม้ยมก（ๆ）。前を空けるか詰めるかは書き手によって割れる。
const _maiYamok = 'ๆ';

/// 語をさがすための正規表現。スペースの有無の違いは無視する。
///
/// 同じ語でも「จริงๆ」と「จริง ๆ」の両方の書き方があり、例文と単語分解で
/// 食い違うことがある。タイ語としては同じ語なので、ここで揺れを吸収する。
/// 語の途中に勝手なスペースは入らないので、緩めるのは語中のスペースと
/// ไม้ยมก の前だけにとどめる。
RegExp _flexibleWord(String word) {
  final buffer = StringBuffer();
  var pendingSpace = false;
  for (final rune in word.runes) {
    final char = String.fromCharCode(rune);
    if (char.trim().isEmpty) {
      pendingSpace = true;
      continue;
    }
    if (buffer.isNotEmpty && (pendingSpace || char == _maiYamok)) {
      buffer.write(r'\s*');
    }
    buffer.write(RegExp.escape(char));
    pendingSpace = false;
  }
  return RegExp(buffer.toString());
}

/// スペースを落とした形。語の同一性を見るときの鍵に使う。
String _spaceless(String value) => value.replaceAll(RegExp(r'\s+'), '');

/// 複数の語をまとめて探す正規表現。長い語から先に当てる。
RegExp _flexibleWords(List<String> words) {
  final sorted = [...words]..sort((a, b) => b.length.compareTo(a.length));
  return RegExp(sorted.map((w) => _flexibleWord(w).pattern).join('|'));
}

/// 単語分解から取った語の切れ目（本文中の位置）。分解が無ければ空。
Set<int> _wordBoundaries(String text, List<WordBreakdown> words) {
  final boundaries = <int>{};
  var cursor = 0;
  for (final word in words) {
    final wordText = word.wordText;
    if (wordText.isEmpty) continue;
    final match = _flexibleWord(wordText).firstMatch(text.substring(cursor));
    if (match == null) continue;
    boundaries
      ..add(cursor + match.start)
      ..add(cursor + match.end);
    cursor += match.end;
  }
  return boundaries;
}

/// 学習単語を光らせる範囲（開始, 終了）を出現順に返す。
///
/// 文字列の部分一致だけで光らせると、長い語の中に短い学習単語が含まれる
/// ときに途中まで光る（แล้ว の中の แล、เวลา の中の ลา など）。単語分解が
/// 分かっていれば、始まりと終わりが語の切れ目に乗った一致だけを採る。
/// 途中で語をまたぐのはよい（ดูเหมือนว่า が ดู / เหมือน / ว่า に分かれていても光る）。
/// 単語分解が語の後ろに ๆ を付けている（อ่อนๆ）ときは ๆ まで含めて光らせる。
///
/// 単語分解が無いときは語の切れ目が分からないので、全ての一致を採る。
List<(int, int)> _targetRanges(
  String text,
  List<String> targetWords,
  List<WordBreakdown> words,
) {
  final targets = targetWords.where((w) => w.trim().isNotEmpty).toList();
  if (targets.isEmpty) return const [];

  final boundaries = _wordBoundaries(text, words);
  if (boundaries.isEmpty) {
    return [
      for (final m in _flexibleWords(targets).allMatches(text))
        (m.start, m.end),
    ];
  }

  final patterns = [
    for (final w in targets) ...[
      _flexibleWord(w),
      if (!w.trim().endsWith(_maiYamok))
        RegExp('${_flexibleWord(w).pattern}\\s*$_maiYamok'),
    ],
  ];
  final ranges = <(int, int)>[];
  var lastEnd = 0;
  for (final start in boundaries.toList()..sort()) {
    if (start < lastEnd) continue;
    // 同じ位置から複数の学習単語が当たるときは、切れ目に乗る中で一番長いものを採る。
    int? end;
    for (final pattern in patterns) {
      final match = pattern.matchAsPrefix(text, start);
      if (match == null || !boundaries.contains(match.end)) continue;
      if (end == null || match.end > end) end = match.end;
    }
    if (end == null) continue;
    ranges.add((start, end));
    lastEnd = end;
  }
  return ranges;
}

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
  final spans = <InlineSpan>[];
  var lastEnd = 0;
  final highlightStyle = baseStyle.copyWith(
    color: highlightColor,
    fontWeight: FontWeight.bold,
  );
  for (final (start, end) in _targetRanges(text, targetWords, words)) {
    if (start > lastEnd) {
      spans.add(TextSpan(text: text.substring(lastEnd, start)));
    }
    // 面も下線も持たせない。金の字と太さだけで示す。深藍の上では
    // それだけで十分に立ち、タイ文字の声調記号も隠れない。
    spans
        .add(TextSpan(text: text.substring(start, end), style: highlightStyle));
    lastEnd = end;
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
  final spans = <InlineSpan>[];
  var lastEnd = 0;
  for (final (start, end) in _targetRanges(text, targetWords, words)) {
    if (start > lastEnd) {
      spans.add(TextSpan(text: text.substring(lastEnd, start)));
    }
    spans.add(
      TextSpan(
        text: text.substring(start, end),
        style: baseStyle.copyWith(color: tint),
      ),
    );
    lastEnd = end;
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

  // 語の引き当てもスペースの揺れを無視する（「จริงๆ」と「จริง ๆ」）。
  final breakdownMap = {
    for (final wb in sentence.wordBreakdowns)
      _spaceless(wb.wordText): wb.pronunciation,
  };
  final readings = targetWords
      .map((w) =>
          breakdownMap[_spaceless(w)] ??
          breakdownMap[_spaceless('$w$_maiYamok')])
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
