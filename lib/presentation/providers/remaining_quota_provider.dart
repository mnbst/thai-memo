import 'package:cloud_firestore/cloud_firestore.dart';
import '../../l10n/app_localizations.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/firebase_auth_service.dart';
import 'subscription_provider.dart';

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

/// users/{uid}.premium_trial_expires_at — プレミアム体験トライアルの期限
/// 期限を持たない旧ユーザーは null。
final premiumTrialExpiresAtProvider = Provider<AsyncValue<DateTime?>>((ref) {
  return ref.watch(userDocProvider).whenData(
        (data) => (data?['premium_trial_expires_at'] as Timestamp?)?.toDate(),
      );
});

/// users/{uid}.premium_trial_ended_at — 体験終了が確定した時刻
///
/// 期限切れ後、最初の日次リセット（dailyBatch）で刻まれる。期限そのものではなく
/// これを見ることで、「回数が free に戻った後」に体験終了を伝えられる。
final premiumTrialEndedAtProvider = Provider<AsyncValue<DateTime?>>((ref) {
  return ref.watch(userDocProvider).whenData(
        (data) => (data?['premium_trial_ended_at'] as Timestamp?)?.toDate(),
      );
});

/// users/{uid}.premium_trial_backfilled_at — 体験を後から配られた時刻
///
/// 新規登録時（onUserCreate）の付与では刻まれない。既存ユーザーへの一括配布で
/// だけ立つので、クライアントはこれを見て「開放しました」の案内を出す。
/// 新規ユーザーには初回ガイドで体験を伝えており、二重に案内しない。
final premiumTrialBackfilledAtProvider = Provider<AsyncValue<DateTime?>>((ref) {
  return ref.watch(userDocProvider).whenData(
        (data) => (data?['premium_trial_backfilled_at'] as Timestamp?)?.toDate(),
      );
});

/// プレミアム体験トライアルが有効か。
///
/// 新規ユーザーは登録から一定期間、課金プレミアムと完全に同じ機能・回数を使える。
/// サーバー側の判定（utils/premium.ts, sentence_handlers._resolve_trial_active）と
/// 同じく期限だけで決める。
final premiumTrialActiveProvider = Provider<AsyncValue<bool>>((ref) {
  return ref.watch(premiumTrialExpiresAtProvider).whenData(
        (value) => value != null && DateTime.now().isBefore(value),
      );
});

/// users/{uid}.tier — Firestoreストリームからリアルタイムにプレミアム判定
final isPremiumRealtimeProvider = Provider<AsyncValue<bool>>((ref) {
  return ref
      .watch(userDocProvider)
      .whenData((data) => data?['tier'] == 'premium');
});

/// 表示・判定用のプラン状態。
enum PlanStatus { free, trial, premium }

/// ユーザーのプラン状態を users/{uid} の1スナップショットだけから決める。
///
/// tier と体験期限を別々のソース（Firestore の1回読み／ストリーム）から取ると、
/// 起動直後に free → 体験中 → Premium と数段階ぶれて見えるため、判定は
/// このプロバイダに集約する。未確定（読み込み中）は AsyncLoading のまま返し、
/// 呼び出し側で「まだ出さない」を選べるようにする。
final planStatusProvider = Provider<AsyncValue<PlanStatus>>((ref) {
  final doc = ref.watch(userDocProvider);
  final linked = FirebaseAuthService.instance.isLinkedAccount;

  // サインイン済みなのに doc が無いのは onUserCreate が書く前の一瞬。ここで free と
  // 決めると直後の体験付与で Free → 体験中 とぶれるので、未確定のままにする。
  if (linked && doc.hasValue && doc.value == null) {
    return const AsyncValue<PlanStatus>.loading();
  }
  // 読めないまま未確定を返すと Chip が出ないまま固まるので、課金状態だけでも出す。
  if (doc.hasError) {
    return AsyncValue.data(
      ref.watch(isPremiumProvider) ? PlanStatus.premium : PlanStatus.free,
    );
  }

  return doc.whenData((data) {
    // プレミアムはサインイン（正規アカウント）時のみ有効。
    if (linked && data?['tier'] == 'premium') return PlanStatus.premium;
    final expiresAt =
        (data?['premium_trial_expires_at'] as Timestamp?)?.toDate();
    if (expiresAt != null && DateTime.now().isBefore(expiresAt)) {
      return PlanStatus.trial;
    }
    return PlanStatus.free;
  });
});

/// 課金プレミアム、またはプレミアム体験トライアル中か。
///
/// 体験中は課金と完全に同じ扱いにするので、機能の出し分けは原則これで判定する。
/// 「課金しているか」そのものを問う場面（プラン表示・購入導線）だけ
/// [isPremiumProvider] を使うこと。
final effectivePremiumProvider = Provider<bool>((ref) {
  final plan = ref.watch(planStatusProvider).valueOrNull;
  if (plan != null) return plan != PlanStatus.free;
  // ストリーム未確定の間だけ、コントローラが持つ値で代用する。
  return ref.watch(isPremiumProvider);
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
