// =============================================================================
// quiz_stats_sync.dart
// クイズの累積統計（総回答数・正解数・連続日数）を端末間で共有する。
//
// 正本は users/{uid}/learning_state/quiz_stats。端末の quiz_stats テーブルは
// 表示用の写しで、セッションを終えたらまず端末側を更新し（すぐ表示するため）、
// 同じセッションを Firestore にもトランザクションで足す。通信できないときは
// セッションを端末に溜め、次に送れたときにまとめて足す。
//
// この機能より前に端末だけで貯めた統計は、端末ごとに1回だけサーバーへ合算する。
// =============================================================================

import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/config/app_config.dart';
import '../core/database_constants.dart';
import '../data/datasources/local/database_helper.dart';

/// 累積統計の値。日付は端末の暦日（yyyy-MM-dd）。
@immutable
class QuizStatsSnapshot {
  const QuizStatsSnapshot({
    this.totalAnswered = 0,
    this.totalCorrect = 0,
    this.currentStreak = 0,
    this.bestStreak = 0,
    this.lastQuizDate,
    this.recentDates = const [],
  });

  final int totalAnswered;
  final int totalCorrect;
  final int currentStreak;
  final int bestStreak;
  final String? lastQuizDate;

  /// 解いた日（昇順、直近 [recentDatesLimit] 日ぶん）。連続日数はここから数える。
  ///
  /// 端末ごとに溜めたセッションは日付順に届くとは限らない。最後の日付と連続日数
  /// だけだと、あとから届いた間の1日を連続に数え直せない。
  final List<String> recentDates;

  bool get isEmpty => totalAnswered == 0 && lastQuizDate == null;

  factory QuizStatsSnapshot.fromFirestore(Map<String, dynamic> data) {
    int read(String key) => (data[key] as num?)?.toInt() ?? 0;
    final date = data['last_quiz_date'];
    return QuizStatsSnapshot(
      totalAnswered: read('total_answered'),
      totalCorrect: read('total_correct'),
      currentStreak: read('current_streak'),
      bestStreak: read('best_streak'),
      lastQuizDate: date is String ? date : null,
      recentDates: ((data['recent_dates'] as List?) ?? const [])
          .whereType<String>()
          .toList(),
    );
  }

  factory QuizStatsSnapshot.fromDatabase(Map<String, dynamic>? row) {
    if (row == null) return const QuizStatsSnapshot();
    int read(String key) => row[key] as int? ?? 0;
    return QuizStatsSnapshot(
      totalAnswered: read(DatabaseConstants.columnStatsTotalAnswered),
      totalCorrect: read(DatabaseConstants.columnStatsTotalCorrect),
      currentStreak: read(DatabaseConstants.columnStatsCurrentStreak),
      bestStreak: read(DatabaseConstants.columnStatsBestStreak),
      lastQuizDate: row[DatabaseConstants.columnStatsLastQuizDate] as String?,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'total_answered': totalAnswered,
        'total_correct': totalCorrect,
        'current_streak': currentStreak,
        'best_streak': bestStreak,
        'last_quiz_date': lastQuizDate,
        'recent_dates': recentDates,
        'updated_at': FieldValue.serverTimestamp(),
      };
}

/// 1セッション分。通信できないあいだ端末に溜める。
@immutable
class QuizSessionDelta {
  const QuizSessionDelta({
    required this.correct,
    required this.total,
    required this.date,
  });

  final int correct;
  final int total;
  final String date;

  String encode() => jsonEncode({'c': correct, 't': total, 'd': date});

  static QuizSessionDelta? decode(String raw) {
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return QuizSessionDelta(
        correct: (map['c'] as num).toInt(),
        total: (map['t'] as num).toInt(),
        date: map['d'] as String,
      );
    } catch (_) {
      return null;
    }
  }
}

bool _isNextDay(String prev, String current) {
  try {
    return DateTime.parse(current).difference(DateTime.parse(prev)).inDays == 1;
  } catch (_) {
    return false;
  }
}

/// 連続日数を数えるために持つ日付の数。
const int recentDatesLimit = 60;

/// 解いた日の記録。[recent_dates] を持たない旧データは、最後の日付と
/// 連続日数から組み直す（連続していた日は分かっている）。
List<String> _knownDates(QuizStatsSnapshot stats) {
  if (stats.recentDates.isNotEmpty) return stats.recentDates;
  final last = DateTime.tryParse(stats.lastQuizDate ?? '');
  if (last == null) return const [];
  final days = stats.currentStreak.clamp(1, recentDatesLimit);
  return [
    for (var i = days - 1; i >= 0; i--)
      _formatDate(last.subtract(Duration(days: i))),
  ];
}

String _formatDate(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// 日付の集合を昇順・重複なし・直近 [recentDatesLimit] 件にそろえる。
List<String> _normalizeDates(Iterable<String> dates) {
  final sorted = dates.toSet().toList()..sort();
  return sorted.length <= recentDatesLimit
      ? sorted
      : sorted.sublist(sorted.length - recentDatesLimit);
}

/// いちばん新しい日から遡って、途切れずに続いた日数。
int _streakOf(List<String> sortedDates) {
  if (sortedDates.isEmpty) return 0;
  var streak = 1;
  for (var i = sortedDates.length - 1; i > 0; i--) {
    if (!_isNextDay(sortedDates[i - 1], sortedDates[i])) break;
    streak++;
  }
  return streak;
}

/// セッションを1つ足す。
///
/// 連続日数は解いた日の記録から数え直す。溜めていたセッションが後から届いて
/// 日付が前後しても、間を埋めた1日を連続として数える。
QuizStatsSnapshot applyQuizSession(
  QuizStatsSnapshot prev,
  QuizSessionDelta session,
) {
  final dates = _normalizeDates([..._knownDates(prev), session.date]);
  final streak = _streakOf(dates);
  return QuizStatsSnapshot(
    totalAnswered: prev.totalAnswered + session.total,
    totalCorrect: prev.totalCorrect + session.correct,
    currentStreak: streak,
    bestStreak: streak > prev.bestStreak ? streak : prev.bestStreak,
    lastQuizDate: dates.last,
    recentDates: dates,
  );
}

/// 別々の端末で貯めた統計を合わせる（移行時の1回だけ）。
///
/// 回数は足す。連続日数は最後に解いた日が新しい方を採り、同じ日なら長い方。
QuizStatsSnapshot mergeQuizStats(QuizStatsSnapshot a, QuizStatsSnapshot b) {
  final aDate = a.lastQuizDate ?? '';
  final bDate = b.lastQuizDate ?? '';
  final QuizStatsSnapshot latest;
  if (aDate == bDate) {
    latest = a.currentStreak >= b.currentStreak ? a : b;
  } else {
    latest = aDate.compareTo(bDate) > 0 ? a : b;
  }
  final best = a.bestStreak > b.bestStreak ? a.bestStreak : b.bestStreak;
  final dates = _normalizeDates([..._knownDates(a), ..._knownDates(b)]);
  // 両端末の日付を合わせると、別々に数えていた連続がつながることがある。
  final streak = dates.isEmpty
      ? latest.currentStreak
      : _streakOf(dates) > latest.currentStreak
          ? _streakOf(dates)
          : latest.currentStreak;
  return QuizStatsSnapshot(
    totalAnswered: a.totalAnswered + b.totalAnswered,
    totalCorrect: a.totalCorrect + b.totalCorrect,
    currentStreak: streak,
    bestStreak: streak > best ? streak : best,
    lastQuizDate: latest.lastQuizDate,
    recentDates: dates,
  );
}

class QuizStatsSync {
  QuizStatsSync({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    DatabaseHelper? database,
  })  : _firestoreOverride = firestore,
        _authOverride = auth,
        _database = database ?? DatabaseHelper.instance;

  /// 既定の共有インスタンス。どの画面から使っても同じ待ち行列を通す。
  static final QuizStatsSync instance = QuizStatsSync();

  static String pendingKey(String uid) => 'quiz_stats_pending_$uid';

  /// この端末の統計をサーバーへ合算済みか。
  static String mergedKey(String uid) => 'quiz_stats_merged_$uid';

  final FirebaseFirestore? _firestoreOverride;
  final FirebaseAuth? _authOverride;
  final DatabaseHelper _database;

  Future<void> _tail = Future.value();

  Future<T> _serialized<T>(Future<T> Function() operation) async {
    final previous = _tail;
    final done = Completer<void>();
    _tail = done.future;
    await previous;
    try {
      return await operation();
    } finally {
      done.complete();
    }
  }

  String? get _uid {
    try {
      return (_authOverride ?? FirebaseAuth.instance).currentUser?.uid;
    } catch (_) {
      return null;
    }
  }

  /// 終えたセッションをサーバーへ足す。端末の quiz_stats は呼び出し側で更新済み。
  Future<void> recordSession(QuizSessionDelta session) => _serialized(() async {
        final uid = _uid;
        if (uid == null) return;
        try {
          final prefs = await SharedPreferences.getInstance();
          final pending = prefs.getStringList(pendingKey(uid)) ?? [];
          pending.add(session.encode());
          await prefs.setStringList(pendingKey(uid), pending);
          await _flush(prefs, uid);
        } catch (e) {
          debugPrint('QuizStatsSync: record failed: $e');
        }
      });

  /// サーバーの統計を端末の quiz_stats へ写す。溜めたセッションを先に送る。
  Future<void> pull() => _serialized(() async {
        final uid = _uid;
        if (uid == null) return;
        try {
          final prefs = await SharedPreferences.getInstance();
          if (!await _flush(prefs, uid)) return;
          final doc = await _ref(uid).get();
          final data = doc.data();
          if (data == null) return;
          await _writeLocal(QuizStatsSnapshot.fromFirestore(data));
        } catch (e) {
          debugPrint('QuizStatsSync: pull failed: $e');
        }
      });

  /// 学習データの初期化・アカウント切替で呼ぶ。送っていないセッションを捨てる。
  Future<void> clear(String uid) => _serialized(() async {
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.remove(pendingKey(uid));
        } catch (_) {}
      });

  DocumentReference<Map<String, dynamic>> _ref(String uid) =>
      (_firestoreOverride ?? FirebaseFirestore.instance)
          .collection('users')
          .doc(uid)
          .collection('learning_state')
          .doc('quiz_stats');

  /// 溜めたセッション（と初回の合算）をサーバーへ送る。すべて送れたら true。
  Future<bool> _flush(SharedPreferences prefs, String uid) async {
    final pending = prefs.getStringList(pendingKey(uid)) ?? const <String>[];
    final needsMerge = prefs.getBool(mergedKey(uid)) != true;
    if (pending.isEmpty && !needsMerge) return true;
    // アカウントを切り替えた直後で、端末に前のアカウントの統計が残っている
    // あいだは合算しない（端末データを消し終えると持ち主が書き換わる）。
    final owner = prefs.getString(AppConfig.prefKeyLocalDataOwnerUid);
    if (needsMerge && owner != null && owner != uid) return false;

    // 合算するときは端末の統計が溜めたセッションも含んでいるので、
    // セッションは足さずに端末の統計をまるごと合わせる。
    final local = needsMerge
        ? QuizStatsSnapshot.fromDatabase(await _database.getCachedQuizStats())
        : null;
    final sessions =
        pending.map(QuizSessionDelta.decode).whereType<QuizSessionDelta>();

    final ref = _ref(uid);
    final firestore = _firestoreOverride ?? FirebaseFirestore.instance;
    final QuizStatsSnapshot? result;
    try {
      result = await firestore.runTransaction((transaction) async {
        final data = (await transaction.get(ref)).data();
        final server = data == null
            ? const QuizStatsSnapshot()
            : QuizStatsSnapshot.fromFirestore(data);
        final next = local != null
            ? mergeQuizStats(server, local)
            : sessions.fold(server, applyQuizSession);
        if (next.isEmpty) return null;
        transaction.set(ref, next.toFirestore());
        return next;
      });
    } catch (e) {
      debugPrint('QuizStatsSync: flush failed: $e');
      return false;
    }

    await prefs.remove(pendingKey(uid));
    await prefs.setBool(mergedKey(uid), true);
    if (result != null) await _writeLocal(result);
    return true;
  }

  Future<void> _writeLocal(QuizStatsSnapshot stats) =>
      _database.replaceQuizStats(
        totalAnswered: stats.totalAnswered,
        totalCorrect: stats.totalCorrect,
        currentStreak: stats.currentStreak,
        bestStreak: stats.bestStreak,
        lastQuizDate: stats.lastQuizDate,
      );
}
