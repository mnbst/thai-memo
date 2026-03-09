import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/datasources/local/database_helper.dart';

// ==================== Models ====================

class StreakData {
  final int currentStreak;
  final int bestStreak;

  const StreakData({this.currentStreak = 0, this.bestStreak = 0});

  factory StreakData.fromDatabase(Map<String, dynamic>? row) {
    if (row == null) return const StreakData();
    return StreakData(
      currentStreak: row['current_streak'] as int? ?? 0,
      bestStreak: row['best_streak'] as int? ?? 0,
    );
  }
}

class DailyActivity {
  final bool generationDone;
  final bool quizDone;

  const DailyActivity({this.generationDone = false, this.quizDone = false});

  bool get allDone => generationDone && quizDone;
}

// ==================== Providers ====================

final streakStatsProvider = FutureProvider<StreakData>((ref) async {
  final row = await DatabaseHelper.instance.getStreakStats();
  return StreakData.fromDatabase(row);
});

final todayActivityProvider = FutureProvider<DailyActivity>((ref) async {
  final today = _todayString();
  final row = await DatabaseHelper.instance.getDailyActivity(today);
  if (row == null) return const DailyActivity();
  return DailyActivity(
    generationDone: (row['generation_done'] as int?) == 1,
    quizDone: (row['quiz_done'] as int?) == 1,
  );
});

// ==================== Helper ====================

String _todayString() {
  final now = DateTime.now();
  return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
}

/// 例文生成完了時に呼ぶ
Future<void> markGenerationDone() async {
  final today = _todayString();
  await DatabaseHelper.instance.markActivity(date: today, generationDone: true);
  await DatabaseHelper.instance.updateStreakIfCompleted(today);
}

/// クイズ完了時に呼ぶ
Future<void> markQuizDone() async {
  final today = _todayString();
  await DatabaseHelper.instance.markActivity(date: today, quizDone: true);
  await DatabaseHelper.instance.updateStreakIfCompleted(today);
}

/// アプリ起動時にstreak切れチェック
Future<void> checkStreakOnLaunch() async {
  final today = _todayString();
  await DatabaseHelper.instance.checkStreakExpiry(today);
}
