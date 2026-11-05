import 'package:flutter_test/flutter_test.dart';
import 'package:thai_memo/data/models/thai_sentence.dart';
import 'package:thai_memo/data/models/vocab_word.dart';
import 'package:thai_memo/data/models/word_breakdown.dart';
import 'package:thai_memo/presentation/screens/vocab_history_screen.dart';

VocabWord _w(String word, int rank, {double p = 0.4, bool answered = false}) =>
    VocabWord(word: word, rank: rank, p: p, answered: answered);

void main() {
  group('mastery', () {
    test('未回答は P に関わらず見ただけ', () {
      expect(_w('ก', 1).mastery, VocabMastery.seen);
    });
    test('回答済みは 0.5 を超えると覚えた', () {
      expect(_w('ก', 1, p: 0.5, answered: true).mastery, VocabMastery.learning);
      expect(_w('ก', 1, p: 0.51, answered: true).mastery, VocabMastery.learned);
    });
    test('不正解で下がった語は覚えかけ', () {
      expect(_w('ก', 1, p: 0.15, answered: true).mastery, VocabMastery.learning);
    });
  });

  group('gauge', () {
    test('未回答は空', () => expect(_w('ก', 1).gauge, 0));
    test('P の範囲を 0〜1 に換算する', () {
      expect(_w('ก', 1, p: 0.15, answered: true).gauge, 0);
      expect(_w('ก', 1, p: 0.99, answered: true).gauge, 1);
      expect(_w('ก', 1, p: 0.8, answered: true).gauge, closeTo(0.774, 0.001));
    });
  });

  test('build はランクの大きい順で、ランク無しを最後にし、例文の情報を引く', () {
    final sentence = ThaiSentence(
      thaiText: 'ไปตลาด',
      pronunciation: 'pai ta-làat',
      japaneseTranslation: '市場へ行く',
      wordBreakdowns: [
        WordBreakdown(wordText: 'ไป', pronunciation: 'pai', meaning: '行く'),
      ],
    );
    final entries = VocabEntry.build(
      [_w('ไม่มี', 0), _w('ไป', 8), _w('น้ำ', 23)],
      [sentence],
    );
    expect(entries.map((e) => e.progress.word), ['น้ำ', 'ไป', 'ไม่มี']);
    final pai = entries[1];
    expect(pai.pronunciation, 'pai');
    expect(pai.meaning, '行く');
    expect(pai.sentences, [sentence]);
    expect(entries[0].sentences, isEmpty);
  });

  group('scoreMarkerIndex', () {
    List<VocabEntry> list(List<int> ranks) => [
          for (final r in ranks) VocabEntry(progress: _w('w$r', r)),
        ];
    test('スコア以下の語の手前に入れる', () {
      expect(scoreMarkerIndex(list([61, 34, 27, 3]), 30), 2);
    });
    test('全語がスコアより上なら最後', () {
      expect(scoreMarkerIndex(list([61, 34]), 30), 2);
    });
    test('ランク無しの語より手前', () {
      expect(scoreMarkerIndex(list([61, 0]), 30), 1);
    });
    test('スコア0は線を引かない', () {
      expect(scoreMarkerIndex(list([61]), 0), isNull);
    });
  });
}
