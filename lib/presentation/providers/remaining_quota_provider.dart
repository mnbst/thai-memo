import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Firebase Auth の uid をリアクティブに提供
final authUidProvider = StreamProvider<String?>((ref) {
  return FirebaseAuth.instance.authStateChanges().map((user) => user?.uid);
});

/// Firestore users/{uid} ドキュメント全体を1つのリスナーで監視
final userDocProvider = StreamProvider<Map<String, dynamic>?>((ref) {
  final uidAsync = ref.watch(authUidProvider);
  final uid = uidAsync.valueOrNull;
  if (uid == null) return Stream.value(null);

  return FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .snapshots()
      .map((doc) => doc.data());
});

/// users/{uid}.remaining_sentences
final remainingSentencesProvider = Provider<AsyncValue<int>>((ref) {
  return ref
      .watch(userDocProvider)
      .whenData((data) => (data?['remaining_sentences'] as num?)?.toInt() ?? 0);
});

/// users/{uid}.daily_sentence_generated
final dailySentenceGeneratedProvider = Provider<AsyncValue<bool>>((ref) {
  return ref.watch(userDocProvider).whenData(
      (data) => (data?['daily_sentence_generated'] as bool?) ?? false);
});

/// users/{uid}.remaining_quizzes
final remainingQuizzesProvider = Provider<AsyncValue<int>>((ref) {
  return ref
      .watch(userDocProvider)
      .whenData((data) => (data?['remaining_quizzes'] as num?)?.toInt() ?? 0);
});

/// users/{uid}.tier — Firestoreストリームからリアルタイムにプレミアム判定
final isPremiumRealtimeProvider = Provider<AsyncValue<bool>>((ref) {
  return ref
      .watch(userDocProvider)
      .whenData((data) => data?['tier'] == 'premium');
});

/// users/{uid} の初回3回Premium体験中かどうか
final isInitialPremiumSentenceTrialProvider = Provider<AsyncValue<bool>>((ref) {
  return ref.watch(userDocProvider).whenData((data) {
    if (data == null || data['tier'] == 'premium') return false;

    final generatedCount = (data['sentence_generated_count'] as num?)?.toInt();
    final isInitialGeneration = data['is_first_generation'] == true;
    return isInitialGeneration ||
        (generatedCount != null && generatedCount <= 3);
  });
});

/// 次のリセット（JST 0:00）までの残り時間テキストを返す
String nextResetText() {
  final nowJst = DateTime.now().toUtc().add(const Duration(hours: 9));
  final nextMidnight =
      DateTime.utc(nowJst.year, nowJst.month, nowJst.day + 1);
  final diff = nextMidnight.difference(nowJst);
  final hours = diff.inHours;
  final minutes = diff.inMinutes % 60;
  if (hours > 0) return '次のリセットまで $hours時間$minutes分';
  return '次のリセットまで $minutes分';
}
