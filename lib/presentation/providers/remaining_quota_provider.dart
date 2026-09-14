import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../l10n/app_localizations.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import 'subscription_provider.dart';

/// 認証ユーザーの識別子とアカウント種別を、同じ Firebase Auth ストリームから提供する。
/// userChanges は匿名アカウントのリンクでも流れるため、uid が変わらない昇格も拾える。
class AuthIdentity {
  const AuthIdentity({required this.uid, required this.isLinked});

  final String uid;
  final bool isLinked;
}

final authIdentityProvider = StreamProvider<AuthIdentity?>((ref) {
  return FirebaseAuth.instance.userChanges().map((user) {
    if (user == null) return null;
    return AuthIdentity(uid: user.uid, isLinked: !user.isAnonymous);
  });
});

final authUidProvider = Provider<AsyncValue<String?>>((ref) {
  return ref.watch(authIdentityProvider).whenData((identity) => identity?.uid);
});

/// users/{uid} の1スナップショット。取得元（サーバー / 端末キャッシュ）も持つ。
class UserDocSnapshot {
  const UserDocSnapshot({required this.data, required this.isFromCache});

  final Map<String, dynamic>? data;
  final bool isFromCache;
}

/// Firestore users/{uid} を監視する唯一のリスナー。
///
/// 語彙・Premium・クォータはすべてこの1本を共有する。用途ごとに listener を
/// 増やすと、同じ doc を何本も常時監視して読み取りが積み上がるため。
final userDocSnapshotProvider = StreamProvider<UserDocSnapshot>((ref) {
  final uid = ref.watch(authUidProvider).valueOrNull;
  if (uid == null) {
    return Stream.value(const UserDocSnapshot(data: null, isFromCache: false));
  }

  return FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .snapshots()
      .map((doc) => UserDocSnapshot(
            data: doc.data(),
            isFromCache: doc.metadata.isFromCache,
          ));
});

/// users/{uid} のフィールドを読む入口。監視は [userDocSnapshotProvider] の共有分。
///
/// 最初の到着を待つときは [userDocSnapshotProvider] の future を読む。
final userDocProvider = Provider<AsyncValue<Map<String, dynamic>?>>((ref) {
  return ref.watch(userDocSnapshotProvider).whenData((doc) => doc.data);
});

/// users/{uid}.remaining_sentences
final remainingSentencesProvider = Provider<AsyncValue<int>>((ref) {
  return ref
      .watch(userDocProvider)
      .whenData((data) => (data?['remaining_sentences'] as num?)?.toInt() ?? 0);
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
        (data) =>
            (data?['premium_trial_backfilled_at'] as Timestamp?)?.toDate(),
      );
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
  final identity = ref.watch(authIdentityProvider);
  if (identity.isLoading) return const AsyncValue<PlanStatus>.loading();
  if (identity.hasError) {
    return AsyncValue.data(
      ref.watch(isPremiumProvider) ? PlanStatus.premium : PlanStatus.free,
    );
  }
  final linked = identity.valueOrNull?.isLinked ?? false;

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

/// 課金と体験を区別する必要がある箇所も、共通のプラン判定から導出する。
final trialActiveProvider = Provider<bool>((ref) {
  return ref.watch(planStatusProvider).valueOrNull == PlanStatus.trial;
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

/// 買い切りへの無償移行を案内してよいユーザーか。
///
/// 条件はサーバー側（migrateToLifetime）と揃える。サーバーの名簿
/// （lifetime_migration_eligible）に載っていて、ストアでの購入記録があり、
/// まだ買い切りの印が付いていない人。status は見ないので、いま課金中の方も
/// 過去に買って切れている方も同じく対象。手動付与や体験トライアルは
/// platform で外れる。
final lifetimeMigrationEligibleProvider = Provider<bool>((ref) {
  final data = ref.watch(userDocProvider).valueOrNull;
  if (data == null) return false;
  if (data['lifetime_migration_eligible'] != true) return false;

  final sub = data['subscription'];
  if (sub is! Map) return false;
  if (sub['lifetime'] == true) return false;
  return sub['platform'] == 'ios' || sub['platform'] == 'android';
});

/// 起動時に無償移行の案内を実際に出した端末か。
///
/// 「移行時点で課金していた人」の目印。案内を押し損ねた・移行に失敗した人へ
/// 設定からのやり直し口を出すために使う。
final lifetimeMigrationOfferedProvider = FutureProvider<bool>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(AppConfig.prefKeyLifetimeMigrationOffered) ?? false;
});

/// 残数が「0以下」から「正数」へ変わったか。日次リセット（dailyBatch）で
/// クォータが戻った瞬間を拾うための判定で、画面とLearningScreenで共有する。
bool changedFromNoRemainingToAvailable(
  AsyncValue<int>? previous,
  AsyncValue<int> next,
) {
  final previousRemaining = previous?.valueOrNull;
  final nextRemaining = next.valueOrNull;
  return previousRemaining != null &&
      nextRemaining != null &&
      previousRemaining <= 0 &&
      nextRemaining > 0;
}
