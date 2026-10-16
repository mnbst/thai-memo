import 'package:flutter_test/flutter_test.dart';
import 'package:thai_memo/presentation/providers/streak_provider.dart';

void main() {
  final today = DateTime(2026, 10, 16, 21, 30);

  group('StreakSummary.compute', () {
    test('記録がなければ0日・最長0・記録前', () {
      final s = StreakSummary.compute(const [], today);
      expect(s.current, 0);
      expect(s.best, 0);
      expect(s.hasHistory, isFalse);
      expect(s.nextMilestone, 7);
    });

    test('今日まで続いていれば今日を含めて数える', () {
      final s = StreakSummary.compute(
          const ['2026-10-14', '2026-10-15', '2026-10-16'], today);
      expect(s.current, 3);
      expect(s.best, 3);
    });

    test('今日がまだでも昨日まで続いていれば途切れていない', () {
      final s =
          StreakSummary.compute(const ['2026-10-14', '2026-10-15'], today);
      expect(s.current, 2);
    });

    test('昨日も未達なら0日、最長は残る', () {
      final s = StreakSummary.compute(
          const ['2026-10-10', '2026-10-11', '2026-10-12', '2026-10-14'],
          today);
      expect(s.current, 0);
      expect(s.best, 3);
      expect(s.hasHistory, isTrue);
    });

    test('重複・順不同でも正しく数える', () {
      final s = StreakSummary.compute(
          const ['2026-10-16', '2026-10-15', '2026-10-16'], today);
      expect(s.current, 2);
      expect(s.doneDates, {'2026-10-15', '2026-10-16'});
    });

    test('月またぎ・年またぎも連続として数える', () {
      final s = StreakSummary.compute(
          const ['2025-12-31', '2026-01-01'], DateTime(2026, 1, 1));
      expect(s.current, 2);
    });

    test('次の節目は 7・14・30、30日以上は null', () {
      List<String> run(int n) => [
            for (var i = n - 1; i >= 0; i--)
              streakDateKey(DateTime(2026, 10, 16).subtract(Duration(days: i))),
          ];
      expect(StreakSummary.compute(run(7), today).nextMilestone, 14);
      expect(StreakSummary.compute(run(29), today).nextMilestone, 30);
      expect(StreakSummary.compute(run(30), today).nextMilestone, isNull);
    });

    test('isDone は日付キーで判定する', () {
      final s = StreakSummary.compute(const ['2026-10-16'], today);
      expect(s.isDone(DateTime(2026, 10, 16)), isTrue);
      expect(s.isDone(DateTime(2026, 10, 15)), isFalse);
      expect(streakDateKey(DateTime(2026, 1, 5)), '2026-01-05');
    });
  });
}
