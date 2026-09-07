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
    test('free は例文3本ごとに誘導する（初回だけ早く出したりしない）', () {
      // completedCount はいま解いている確認クイズの1本を含まない。
      expect(shouldOfferSummaryQuiz(0, isPaidPremium: false), isFalse); // 1本目
      expect(shouldOfferSummaryQuiz(1, isPaidPremium: false), isFalse);
      expect(shouldOfferSummaryQuiz(2, isPaidPremium: false), isTrue); // 3本目
    });

    test('課金プレミアムは従来どおり例文5本ごと', () {
      expect(shouldOfferSummaryQuiz(2, isPaidPremium: true), isFalse); // 3本目
      expect(shouldOfferSummaryQuiz(3, isPaidPremium: true), isFalse);
      expect(shouldOfferSummaryQuiz(4, isPaidPremium: true), isTrue); // 5本目
    });

    test('まとめクイズを飛ばして本数が伸びても誘導し続ける', () {
      expect(
        shouldOfferSummaryQuiz(summaryQuizThresholdFree, isPaidPremium: false),
        isTrue,
      );
      expect(
        shouldOfferSummaryQuiz(
          summaryQuizThresholdPremium + 3,
          isPaidPremium: true,
        ),
        isTrue,
      );
    });
  });
}
