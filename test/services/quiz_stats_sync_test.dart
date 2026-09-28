import 'package:flutter_test/flutter_test.dart';
import 'package:thai_memo/services/quiz_stats_sync.dart';

QuizSessionDelta session(String date, {int correct = 3, int total = 5}) =>
    QuizSessionDelta(correct: correct, total: total, date: date);

void main() {
  group('applyQuizSession', () {
    test('初回は連続1日', () {
      final s =
          applyQuizSession(const QuizStatsSnapshot(), session('2026-09-01'));
      expect(s.totalAnswered, 5);
      expect(s.totalCorrect, 3);
      expect(s.currentStreak, 1);
      expect(s.bestStreak, 1);
      expect(s.lastQuizDate, '2026-09-01');
    });

    test('翌日は伸び、同じ日は据え置き、間が空くと1に戻る', () {
      var s =
          applyQuizSession(const QuizStatsSnapshot(), session('2026-09-01'));
      s = applyQuizSession(s, session('2026-09-02'));
      expect(s.currentStreak, 2);
      s = applyQuizSession(s, session('2026-09-02'));
      expect(s.currentStreak, 2);
      expect(s.totalAnswered, 15);
      s = applyQuizSession(s, session('2026-09-05'));
      expect(s.currentStreak, 1);
      expect(s.bestStreak, 2);
    });

    test('古い日付のセッションが後から届いても連続は切らない', () {
      var s =
          applyQuizSession(const QuizStatsSnapshot(), session('2026-09-01'));
      s = applyQuizSession(s, session('2026-09-02'));
      s = applyQuizSession(s, session('2026-08-20'));
      expect(s.currentStreak, 2);
      expect(s.lastQuizDate, '2026-09-02');
      expect(s.totalAnswered, 15);
    });
  });

  group('mergeQuizStats', () {
    test('回数は足し、連続は最後に解いた日が新しい方を採る', () {
      const a = QuizStatsSnapshot(
        totalAnswered: 10,
        totalCorrect: 7,
        currentStreak: 5,
        bestStreak: 8,
        lastQuizDate: '2026-09-01',
      );
      const b = QuizStatsSnapshot(
        totalAnswered: 4,
        totalCorrect: 2,
        currentStreak: 2,
        bestStreak: 3,
        lastQuizDate: '2026-09-03',
      );
      final m = mergeQuizStats(a, b);
      expect(m.totalAnswered, 14);
      expect(m.totalCorrect, 9);
      expect(m.currentStreak, 2);
      expect(m.bestStreak, 8);
      expect(m.lastQuizDate, '2026-09-03');
    });

    test('同じ日なら長い連続を採る', () {
      const a = QuizStatsSnapshot(currentStreak: 3, lastQuizDate: '2026-09-03');
      const b = QuizStatsSnapshot(currentStreak: 6, lastQuizDate: '2026-09-03');
      expect(mergeQuizStats(a, b).currentStreak, 6);
      expect(mergeQuizStats(b, a).currentStreak, 6);
    });

    test('空と合わせても変わらない', () {
      const a = QuizStatsSnapshot(
        totalAnswered: 10,
        totalCorrect: 7,
        currentStreak: 5,
        bestStreak: 8,
        lastQuizDate: '2026-09-01',
      );
      final m = mergeQuizStats(const QuizStatsSnapshot(), a);
      expect(m.totalAnswered, 10);
      expect(m.currentStreak, 5);
      expect(m.bestStreak, 8);
      expect(m.lastQuizDate, '2026-09-01');
    });
  });
}
