import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thai_memo/data/models/thai_sentence.dart';
import 'package:thai_memo/presentation/providers/daily_set_provider.dart';
import 'package:thai_memo/presentation/screens/home_screen.dart';
import 'package:thai_memo/services/daily_sentence_service.dart';

ThaiSentence _sentence(String id) => ThaiSentence(
      id: id,
      thaiText: id,
      pronunciation: '',
      japaneseTranslation: '',
      wordBreakdowns: const [],
    );

void main() {
  group('isSameDailySet', () {
    test('同じ並びの通知を再度開いても消化中セットを作り直さない', () {
      final sentences = [_sentence('a'), _sentence('b'), _sentence('c')];
      final active = DailySetState(sentences: sentences, index: 1);
      final delivered = DailySentenceSet(
        setId: 'a',
        sentences: [_sentence('a'), _sentence('b'), _sentence('c')],
      );

      expect(isSameDailySet(active, delivered), isTrue);
    });

    test('本数または順序が違う新着セットは置き換える', () {
      final active = DailySetState(
        sentences: [_sentence('a'), _sentence('b')],
      );

      expect(
        isSameDailySet(
          active,
          DailySentenceSet(
            setId: 'x',
            sentences: [_sentence('b'), _sentence('a')],
          ),
        ),
        isFalse,
      );
    });

    test('通信断で通知対象の1本だけ返っても進行中セットを保つ', () {
      final active = DailySetState(
        sentences: [_sentence('a'), _sentence('b'), _sentence('c')],
        index: 2,
      );

      expect(
        isSameDailySet(
          active,
          DailySentenceSet(setId: 'a', sentences: [_sentence('a')]),
        ),
        isTrue,
      );
    });

    test('関係のない旧形式の1本配信は進行中セットと別物', () {
      final active = DailySetState(
        sentences: [_sentence('a'), _sentence('b')],
        index: 1,
      );

      expect(
        isSameDailySet(
          active,
          DailySentenceSet(setId: 'old', sentences: [_sentence('old')]),
        ),
        isFalse,
      );
    });
  });

  group('shouldAutoLoadAfterSentenceQuotaRefresh', () {
    test('0から正数に戻り、当日未生成なら自動ロードする', () {
      expect(
        shouldAutoLoadAfterSentenceQuotaRefresh(
          previous: const AsyncData(0),
          next: const AsyncData(5),
          dailySentenceGenerated: false,
        ),
        isTrue,
      );
    });

    test('0から正数に戻っても当日生成済みなら自動ロードしない', () {
      expect(
        shouldAutoLoadAfterSentenceQuotaRefresh(
          previous: const AsyncData(0),
          next: const AsyncData(5),
          dailySentenceGenerated: true,
        ),
        isFalse,
      );
    });

    test('残数が正数へ変わっていない場合は自動ロードしない', () {
      expect(
        shouldAutoLoadAfterSentenceQuotaRefresh(
          previous: const AsyncData(2),
          next: const AsyncData(5),
          dailySentenceGenerated: false,
        ),
        isFalse,
      );
    });
  });

  group('shouldOfferSummaryQuiz', () {
    test('配信セットと同じ例文5本ごとに誘導する（初回だけ早く出したりしない）', () {
      // completedCount はいま解いている確認クイズの1本を含まない。
      expect(shouldOfferSummaryQuiz(0), isFalse); // 1本目
      expect(shouldOfferSummaryQuiz(1), isFalse);
      expect(shouldOfferSummaryQuiz(2), isFalse);
      expect(shouldOfferSummaryQuiz(3), isFalse);
      expect(shouldOfferSummaryQuiz(4), isTrue); // 5本目
    });

    test('まとめクイズを飛ばして本数が伸びても誘導し続ける', () {
      expect(shouldOfferSummaryQuiz(summaryQuizThreshold), isTrue);
      expect(shouldOfferSummaryQuiz(summaryQuizThreshold + 3), isTrue);
    });
  });
}
