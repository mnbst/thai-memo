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

    test('間の1日が後から届いたら、連続としてつなげる', () {
      // 端末Aで 9/1・9/3、端末Bの 9/2 は圏外で溜まっていて後から届く。
      var s =
          applyQuizSession(const QuizStatsSnapshot(), session('2026-09-01'));
      s = applyQuizSession(s, session('2026-09-03'));
      expect(s.currentStreak, 1);
      s = applyQuizSession(s, session('2026-09-02'));
      expect(s.currentStreak, 3);
      expect(s.bestStreak, 3);
      expect(s.lastQuizDate, '2026-09-03');
      expect(s.recentDates, ['2026-09-01', '2026-09-02', '2026-09-03']);
    });

    test('日付の記録が無い旧データは、最後の日と連続日数から組み直す', () {
      const prev = QuizStatsSnapshot(
        totalAnswered: 20,
        currentStreak: 3,
        bestStreak: 4,
        lastQuizDate: '2026-09-10',
      );
      final s = applyQuizSession(prev, session('2026-09-11'));
      expect(s.currentStreak, 4);
      expect(s.recentDates.first, '2026-09-08');
    });

    test('日付の記録は直近の上限件数だけ持つ', () {
      var s = const QuizStatsSnapshot();
      for (var i = 0; i < recentDatesLimit + 5; i++) {
        final d = DateTime(2026, 1, 1).add(Duration(days: i));
        s = applyQuizSession(
          s,
          session('${d.year}-${d.month.toString().padLeft(2, '0')}-'
              '${d.day.toString().padLeft(2, '0')}'),
        );
      }
      expect(s.recentDates, hasLength(recentDatesLimit));
      expect(s.currentStreak, recentDatesLimit);
    });
  });

  group('mergeQuizStats', () {
    test('回数は足し、両端末の日付がつながれば連続もつなげる', () {
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
      // 8/28〜9/1（5日）と 9/2〜9/3（2日）はつながって7日。
      expect(m.currentStreak, 7);
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
