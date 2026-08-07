import 'package:cloud_firestore/cloud_firestore.dart';
import '../../l10n/app_localizations.dart';
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

/// users/{uid}.premium_trial_remaining — プレミアム体験トライアルの残回数
///
/// 現在のトライアルは期間制で、残回数は旧クライアント互換のために書かれている値。
/// 有効判定には [premiumTrialActiveProvider] を使うこと。
final premiumTrialRemainingProvider = Provider<AsyncValue<int>>((ref) {
  return ref.watch(userDocProvider).whenData(
      (data) => (data?['premium_trial_remaining'] as num?)?.toInt() ?? 0);
});

/// users/{uid}.premium_trial_expires_at — プレミアム体験トライアルの期限
/// 期限を持たない旧ユーザーは null。
final premiumTrialExpiresAtProvider = Provider<AsyncValue<DateTime?>>((ref) {
  return ref.watch(userDocProvider).whenData(
        (data) => (data?['premium_trial_expires_at'] as Timestamp?)?.toDate(),
      );
});

/// プレミアム体験トライアルが有効か。
///
/// 新規ユーザーは登録から一定期間、テーマ選択＋premium生成を体験できる。
/// 期限を持たない旧ユーザーだけ、従来どおり残回数で判定する（サーバー側の
/// _resolve_trial_active と同じ順序）。
final premiumTrialActiveProvider = Provider<AsyncValue<bool>>((ref) {
  final expiresAt = ref.watch(premiumTrialExpiresAtProvider);
  final remaining = ref.watch(premiumTrialRemainingProvider);
  return expiresAt.whenData((value) {
    if (value != null) return DateTime.now().isBefore(value);
    return (remaining.valueOrNull ?? 0) > 0;
  });
});

/// users/{uid}.tier — Firestoreストリームからリアルタイムにプレミアム判定
final isPremiumRealtimeProvider = Provider<AsyncValue<bool>>((ref) {
  return ref
      .watch(userDocProvider)
      .whenData((data) => data?['tier'] == 'premium');
});

/// 次のリセット（JST 0:00）までの残り時間テキストを返す
String nextResetText(L10n l10n) {
  final nowJst = DateTime.now().toUtc().add(const Duration(hours: 9));
  final nextMidnight = DateTime.utc(nowJst.year, nowJst.month, nowJst.day + 1);
  final diff = nextMidnight.difference(nowJst);
  final hours = diff.inHours;
  final minutes = diff.inMinutes % 60;
  if (hours > 0) return l10n.quotaResetInHours(hours, minutes);
  return l10n.quotaResetInMinutes(minutes);
}
