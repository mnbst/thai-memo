import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thai_memo/presentation/screens/home_screen.dart';

void main() {
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
    test('例文5本ごとに誘導する（初回だけ早く出したりしない）', () {
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
