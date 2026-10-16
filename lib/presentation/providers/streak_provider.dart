import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/datasources/local/database_helper.dart';
import 'sentence_provider.dart';

/// 連続日数。数えるのは「例文を作った（受け取った）日」だけで、クイズは数えない。
///
/// 記録は端末の daily_activity に持つ。学習データのリセットで DB ごと消える。
class StreakSummary {
  const StreakSummary({
    required this.current,
    required this.best,
    required this.doneDates,
    required this.firstDate,
    required this.today,
  });

  static StreakSummary empty(DateTime today) => StreakSummary(
        current: 0,
        best: 0,
        doneDates: const {},
        firstDate: null,
        today: _dateOnly(today),
      );

  /// 今日まで（今日が未達なら昨日まで）続いている日数。昨日も未達なら0。
  final int current;
  final int best;
  final Set<String> doneDates;

  /// 初めて記録した日。これより前の日は「未達」ではなく「記録前」として見せる。
  final DateTime? firstDate;
  final DateTime today;

  bool get hasHistory => firstDate != null;
  bool isDone(DateTime day) => doneDates.contains(streakDateKey(day));

  /// 次の節目（7・14・30日）。30日を超えたら null。
  int? get nextMilestone {
    for (final m in streakMilestones) {
      if (current < m) return m;
    }
    return null;
  }

  /// [dates] は yyyy-MM-dd。並びは問わない。
  static StreakSummary compute(Iterable<String> dates, DateTime now) {
    final today = _dateOnly(now);
    final days = {for (final d in dates) DateTime.tryParse(d)}
        .whereType<DateTime>()
        .map(_dateOnly)
        .toList()
      ..sort();
    if (days.isEmpty) return empty(now);

    var best = 0;
    var run = 0;
    DateTime? prev;
    for (final day in days) {
      run = prev != null && _daysBetween(prev, day) == 1 ? run + 1 : 1;
      if (run > best) best = run;
      prev = day;
    }

    // 最後の記録が今日か昨日なら、その連続がまだ生きている。
    final gap = _daysBetween(days.last, today);
    final current = gap <= 1 ? run : 0;

    return StreakSummary(
      current: current,
      best: best,
      doneDates: {for (final d in days) streakDateKey(d)},
      firstDate: days.first,
      today: today,
    );
  }
}

const streakMilestones = [7, 14, 30];

String streakDateKey(DateTime day) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${day.year}-${two(day.month)}-${two(day.day)}';
}

DateTime _dateOnly(DateTime t) => DateTime(t.year, t.month, t.day);

/// 夏時間で1日が23・25時間になっても日数がずれないよう、UTC の日付で数える。
int _daysBetween(DateTime a, DateTime b) => DateTime.utc(b.year, b.month, b.day)
    .difference(DateTime.utc(a.year, a.month, a.day))
    .inDays;

class StreakController extends StateNotifier<StreakSummary> {
  StreakController(this._db, {DateTime Function()? clock})
      : _clock = clock ?? DateTime.now,
        super(StreakSummary.empty((clock ?? DateTime.now)())) {
    refresh();
  }

  final DatabaseHelper _db;
  final DateTime Function() _clock;

  Future<void> refresh() async {
    try {
      final dates = await _db.getGenerationDates();
      if (!mounted) return;
      state = StreakSummary.compute(dates, _clock());
    } catch (_) {
      // 表示用の数字なので、読めなければ前の値のままにする。
    }
  }

  /// 今日を「例文を作った日」として記録する。
  Future<void> markToday() async {
    try {
      await _db.markGenerationDone(streakDateKey(_clock()));
    } catch (_) {
      return;
    }
    await refresh();
  }
}

final streakProvider =
    StateNotifierProvider<StreakController, StreakSummary>((ref) {
  final controller = StreakController(DatabaseHelper.instance);
  // 生成に成功したら（手動・起動時の自動とも）今日を記録する。
  // 配信の受け取りは home_screen の取り込みで記録する。
  ref.listen<SentenceState>(sentenceControllerProvider, (prev, next) {
    if (next is SentenceStateSuccess &&
        next.generated &&
        !identical(prev, next)) {
      controller.markToday();
    }
  });
  return controller;
});
