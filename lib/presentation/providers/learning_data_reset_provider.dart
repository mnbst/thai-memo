import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/datasources/backend_api_service.dart';
import '../../data/datasources/local/database_helper.dart';
import '../../services/firebase_auth_service.dart';
import '../../services/sentence_view_marker.dart';
import 'daily_set_provider.dart';
import 'leaderboard_provider.dart';
import 'quiz_provider.dart';
import 'sentence_provider.dart';
import 'vocab_stats_provider.dart';

/// 学習リセットとアカウント削除で、端末の保存・表示を同じ順序で掃除する。
class LearningDataReset {
  LearningDataReset(
    this._ref, {
    Future<void> Function()? resetRemote,
    Future<void> Function()? deleteDatabase,
    String? Function()? currentUid,
  })  : _resetRemote = resetRemote ?? BackendApiService().resetLearningData,
        _deleteDatabase =
            deleteDatabase ?? DatabaseHelper.instance.deleteDatabase,
        _currentUid =
            currentUid ?? (() => FirebaseAuthService.instance.currentUser?.uid);

  final Ref _ref;
  final Future<void> Function() _resetRemote;
  final Future<void> Function() _deleteDatabase;
  final String? Function() _currentUid;
  Future<void>? _inFlight;

  Future<void> reset() => _runOnce(resetRemote: true, clearPreferences: false);
  Future<void> clearLocal() =>
      _runOnce(resetRemote: false, clearPreferences: true);
  Future<void> clearUserLocal(String? uid) =>
      _runOnce(resetRemote: false, clearPreferences: false, uid: uid);

  Future<void> _runOnce({
    required bool resetRemote,
    required bool clearPreferences,
    String? uid,
  }) {
    return _inFlight ??= _run(
      resetRemote: resetRemote,
      clearPreferences: clearPreferences,
      uid: uid,
    ).whenComplete(() {
      _inFlight = null;
    });
  }

  Future<void> _run({
    required bool resetRemote,
    required bool clearPreferences,
    String? uid,
  }) async {
    uid ??= _currentUid();
    final sets = _ref.read(dailySetProvider.notifier);
    final quiz = _ref.read(quizControllerProvider.notifier);
    final sentences = _ref.read(sentenceControllerProvider.notifier);
    await sets.pauseSync();
    try {
      await sentences.settleForLearningReset();
      await quiz.settleForLearningReset();
      await sets.settled;
      if (resetRemote) await _resetRemote();
      // サーバー処理の失敗時は、端末の学習状態を消さない。
      quiz.reset();
      await quiz.waitForSavedQuizWrites();
      await sets.clear();
      // 例文ごと消えるので、既読の送信記録も持っていても使えない。
      await SentenceViewMarker.instance.clear();
      await _deleteDatabase();
      final prefs = await SharedPreferences.getInstance();
      if (clearPreferences) {
        await prefs.clear();
      } else {
        await _clearUserCaches(prefs, uid);
      }
      sentences.reset();
      _ref.invalidate(allSentencesProvider);
      _ref.invalidate(sentenceCountProvider);
      _ref.invalidate(quizStatsProvider);
      _ref.invalidate(vocabStatsProvider);
      _ref.read(leaderboardRefreshEpochProvider.notifier).state++;
    } finally {
      sets.resumeSync();
    }
  }

  Future<void> _clearUserCaches(SharedPreferences prefs, String? uid) async {
    // LearningProgressStore.clear() が進捗・クイズを消す。ここではUID別の
    // Firestore表示キャッシュだけを消し、テーマ・言語・通知・案内済み等の
    // アプリ設定は維持する。
    if (uid == null) return;
    for (final key in prefs.getKeys()) {
      if (key.startsWith('vocab_stats_${uid}_')) await prefs.remove(key);
    }
  }
}

final learningDataResetProvider = Provider<LearningDataReset>((ref) {
  return LearningDataReset(ref);
});
