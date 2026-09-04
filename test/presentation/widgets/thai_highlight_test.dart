// 学習単語のハイライトは「語まるごと」だけを光らせる。
// 部分一致で光らせると、長い語の途中（แล้ว の中の แล、lɛ́ɛw の中の lɛ́）まで
// 金になり、どれが学習単語か分からなくなる。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thai_memo/data/models/thai_sentence.dart';
import 'package:thai_memo/data/models/word_breakdown.dart';
import 'package:thai_memo/presentation/widgets/thai_highlight.dart';

const _base = TextStyle(fontSize: 14);

WordBreakdown _word(String text, String pronunciation) => WordBreakdown(
      wordText: text,
      pronunciation: pronunciation,
      meaning: '',
    );

/// 光った部分の文字列を出現順に返す（金＋太字の TextSpan）。
List<String> _highlighted(TextSpan span) => span.children!
    .whereType<TextSpan>()
    .where((s) => s.style?.fontWeight == FontWeight.bold)
    .map((s) => s.text!)
    .toList();

/// 色が付いた部分の文字列を出現順に返す（色だけ＝TextSpan）。
List<String> _tinted(TextSpan span, Color color) => span.children!
    .whereType<TextSpan>()
    .where((s) => s.style?.color == color)
    .map((s) => s.text!)
    .toList();

void main() {
  const gold = Color(0xFFC39A4E);

  group('buildHighlightedThaiText', () {
    test('単語分解があれば、語の切れ目に乗った一致だけ光る', () {
      final span = buildHighlightedThaiText(
        'ดึกแล้วและนอนนะ',
        const ['และ'],
        _base,
        gold,
        words: [
          _word('ดึก', 'dùk'),
          _word('แล้ว', 'lɛ́ɛw'),
          _word('และ', 'lɛ́'),
          _word('นอน', 'nɔɔn'),
          _word('นะ', 'ná'),
        ],
      );

      expect(_highlighted(span), ['และ']);
    });

    test('単語分解が無ければ従来どおり全ての一致を光らせる', () {
      final span = buildHighlightedThaiText(
        'และและ',
        const ['และ'],
        _base,
        gold,
      );

      expect(_highlighted(span), ['และ', 'และ']);
    });
  });

  group('buildTintedThaiText', () {
    test('語の途中に含まれる一致は色を変えない', () {
      final span = buildTintedThaiText(
        'ดึกแล้วและนอน',
        const ['แล'],
        _base,
        gold,
        words: [
          _word('ดึก', 'dùk'),
          _word('แล้ว', 'lɛ́ɛw'),
          _word('และ', 'lɛ́'),
          _word('นอน', 'nɔɔn'),
        ],
      );

      expect(_tinted(span, gold), isEmpty);
    });
  });

  group('buildHighlightedPronunciation', () {
    ThaiSentence sentence(List<String> targets) => ThaiSentence(
          thaiText: 'ดึกแล้วและนอนนะ',
          pronunciation: 'dùk lɛ́ɛw lɛ́ nɔɔn ná',
          japaneseTranslation: 'もう遅いから寝よう',
          targetWords: targets,
          wordBreakdowns: [
            _word('ดึก', 'dùk'),
            _word('แล้ว', 'lɛ́ɛw'),
            _word('และ', 'lɛ́'),
            _word('นอน', 'nɔɔn'),
            _word('นะ', 'ná'),
          ],
        );

    test('長い語の頭に含まれる読みは光らせない', () {
      final span = buildHighlightedPronunciation(sentence(['และ']), _base);
      final lit = span.children!
          .whereType<TextSpan>()
          .where((s) => s.style?.color != null)
          .map((s) => s.text)
          .toList();

      // lɛ́ɛw の頭ではなく、単語として現れる lɛ́ だけ。
      expect(lit, ['lɛ́']);
    });

    test('多音節語は語まるごとで光る', () {
      final span = buildHighlightedPronunciation(sentence(['แล้ว']), _base);
      final lit = span.children!
          .whereType<TextSpan>()
          .where((s) => s.style?.color != null)
          .map((s) => s.text)
          .toList();

      expect(lit, ['lɛ́ɛw']);
    });
  });
}
