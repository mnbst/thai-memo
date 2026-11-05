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
      expect(
          _w('ก', 1, p: 0.15, answered: true).mastery, VocabMastery.learning);
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
      targetWords: const ['ไม่มี', 'น้ำ'],
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
  });

  test('build は端末に例文が無い語を載せない', () {
    final sentence = ThaiSentence(
      thaiText: 'ไปตลาด',
      pronunciation: 'pai ta-làat',
      japaneseTranslation: '市場へ行く',
      wordBreakdowns: [
        WordBreakdown(wordText: 'ไป', pronunciation: 'pai', meaning: '行く'),
      ],
    );
    final entries = VocabEntry.build(
      [_w('ไป', 8), _w('อะไร', 14)],
      [sentence],
    );
    expect(entries.map((e) => e.progress.word), ['ไป']);
  });

  group('quizScoreBand', () {
    test('未受験はスコアの下50と前方の帯', () {
      expect(quizScoreBand(score: 30, tested: 0, premium: true), (0, 44));
      expect(quizScoreBand(score: 300, tested: 0, premium: true), (250, 308));
    });
    test('受験者は測定値より下を出さず、前方は測定値から数える', () {
      expect(quizScoreBand(score: 320, tested: 300, premium: true), (300, 336));
    });
    test('free は100語で頭打ちにする', () {
      expect(quizScoreBand(score: 95, tested: 500, premium: false), (100, 100));
      expect(quizScoreBand(score: 50, tested: 0, premium: false), (0, 60));
    });
    test('測定値の上限に達した人は前方を広げる', () {
      expect(
        quizScoreBand(score: 4000, tested: 3000, premium: true),
        (3950, 4050),
      );
    });
  });

  group('vocabListRows', () {
    List<Object> rows(List<int> ranks, int score, (int, int)? band) {
      final entries =
          ranks.map((r) => VocabEntry(progress: _w('w$r', r))).toList();
      return vocabListRows(entries, score, band)
          .map((e) => e is VocabEntry ? e.progress.rank : e)
          .toList();
    }

    test('範囲の上端・スコア・下端を語の間に挟む', () {
      expect(rows([342, 306, 296, 240], 300, (250, 308)), [
        342,
        VocabListMarker.rangeTop,
        306,
        VocabListMarker.score,
        296,
        VocabListMarker.rangeBottom,
        240,
      ]);
    });
    test('範囲内の語が無ければ区切りを出さない', () {
      expect(rows([400, 100], 300, (250, 308)), [
        400,
        VocabListMarker.score,
        100,
      ]);
    });
    test('下端より下の語が無ければ末尾に下端を置く', () {
      expect(rows([300, 280], 0, (250, 308)), [
        VocabListMarker.rangeTop,
        300,
        280,
        VocabListMarker.rangeBottom,
      ]);
    });
    test('スコアが範囲の下にあれば下端の後に置く', () {
      expect(rows([120, 80], 90, (100, 130)), [
        VocabListMarker.rangeTop,
        120,
        VocabListMarker.rangeBottom,
        VocabListMarker.score,
        80,
      ]);
    });
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
