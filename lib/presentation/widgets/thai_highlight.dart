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
    final match = _flexibleWord(wordText).firstMatch(text.substring(cursor));
    if (match == null) continue;
    ranges[cursor + match.start] = cursor + match.end;
    cursor += match.end;
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
  final regex = _flexibleWords(targetWords);
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
    // 面も下線も持たせない。金の字と太さだけで示す。深藍の上では
    // それだけで十分に立ち、タイ文字の声調記号も隠れない。
    spans.add(TextSpan(text: match.group(0)!, style: highlightStyle));
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
  final regex = _flexibleWords(targetWords);
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

  // 語の引き当てもスペースの揺れを無視する（「จริงๆ」と「จริง ๆ」）。
  final breakdownMap = {
    for (final wb in sentence.wordBreakdowns)
      _spaceless(wb.wordText): wb.pronunciation,
  };
  final readings = targetWords
      .map((w) =>
          breakdownMap[_spaceless(w)] ?? breakdownMap[_spaceless('$w$_maiYamok')])
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
