/// subscription_provider.dart — サブスクリプション状態管理
///
/// 「まいにちタイ語」アプリの課金状態（Free / Premium）を Riverpod で管理する。
/// アプリ全体で参照され、機能制限（例文生成回数、クイズ回数、広告表示等）の判定に使用される。
///
/// 【状態の信頼元（Source of Truth）】
/// - prod/tester環境: Firestore の users/{uid}.tier フィールド
///   - 購入時: verifySubscription Cloud Function がストア API で検証後に 'premium' に更新
///   - 解約/期限切れ時: handleAppStoreNotification / handlePlayNotification が 'free' に更新
///   - クライアントはアプリ起動時・フォアグラウンド復帰時に Firestore から最新 tier を取得
/// - dev環境: Firestore（ストア接続なしでテスト可能）
///
/// 【Free / Premium の機能差分】
/// - 例文生成: Free=5回/日 / Premium=5回/日（0時リセット）
/// - クイズ: Free=1回/日 / Premium=5回/日（0時リセット）
/// - 選べる単語: Free=100語まで / Premium=無制限
/// - テーマ: Free=3種 / Premium=15種
/// - 文体: Free=2種 / Premium=5種
/// - 広告: Free=あり / Premium=なし
///
/// 【関連ファイル】
/// - purchase_service.dart: ストア決済処理（購入・復元・検証依頼）
/// - paywall_screen.dart: プレミアムプラン購入 UI
/// - generation_constants.dart: Free/Premium のパラメータ制限値
library;

import '../../core/l10n/l10n_provider.dart';
import '../../l10n/app_localizations.dart';
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import '../../core/config/firebase_config.dart';
import '../../services/analytics_service.dart';
import '../../services/firebase_auth_service.dart';
import '../../services/purchase_service.dart';
import 'analytics_provider.dart';

// ==================== Subscription State ====================

/// ユーザーの課金ティア（無料 or プレミアム）
enum UserTier { free, premium }

/// サブスクリプション画面の状態
///
/// tier: 現在の課金ティア（アプリ全体の機能制限判定に使用）
/// isLoading: 購入/復元処理中かどうか（ボタンの無効化やローディング表示に使用）
/// product: ストアから取得した商品情報（価格表示に使用、取得前は null）
/// errorMessage: 直近のエラーメッセージ（購入失敗時に UI に表示）
class SubscriptionState {
  final UserTier tier;
  final bool isLoading;
  final ProductDetails? product;
  final String? errorMessage;

  const SubscriptionState({
    this.tier = UserTier.free,
    this.isLoading = false,
    this.product,
    this.errorMessage,
  });

  bool get isPremium => tier == UserTier.premium;

  SubscriptionState copyWith({
    UserTier? tier,
    bool? isLoading,
    ProductDetails? product,
    String? errorMessage,
  }) {
    return SubscriptionState(
      tier: tier ?? this.tier,
      isLoading: isLoading ?? this.isLoading,
      product: product ?? this.product,
      errorMessage: errorMessage,
    );
  }
}

// ==================== Subscription Controller ====================

/// サブスクリプション状態を管理するコントローラ
///
/// PurchaseService（ストア決済）と Firestore（状態保存）を橋渡しする。
/// 購入完了時のコールバックで Firestore から最新 tier を再取得し、UI を更新する。
class SubscriptionController extends StateNotifier<SubscriptionState> {
  /// firestore / purchaseService / restoreDelay はテスト時の差し替え用
  SubscriptionController({
    required AnalyticsService analytics,
    required L10n Function() l10n,
    FirebaseFirestore? firestore,
    PurchaseService? purchaseService,
    this.restoreDelay = const Duration(seconds: 2),
  })  : _analytics = analytics,
        _l10n = l10n,
        _firestore = firestore,
        _purchaseService = purchaseService,
        super(const SubscriptionState(tier: UserTier.free));

  final AnalyticsService _analytics;

  /// 文言は言語設定に追従させたいので、値ではなく都度引く関数を持つ。
  final L10n Function() _l10n;
  final FirebaseFirestore? _firestore;
  PurchaseService? _purchaseService;
  Future<void>? _storeReadyFuture;

  /// 復元リクエスト後、サーバー検証完了を待ってから Firestore を再読するまでの待機時間
  final Duration restoreDelay;

  /// 初期化: Firestore から現在のティアを取得
  ///
  /// アプリ起動時に main.dart から1回呼び出される。
  /// Firestoreにサブスク情報がない場合（新規/再登録ユーザー）は
  /// バックグラウンドでストアからの購入復元を試みる。
  Future<void> initialize() async {
    final needsRestore = await _fetchTierFromFirestore();
    // 匿名ユーザーは自動復元しない（premiumが匿名uidへ移ってしまうため）
    if (needsRestore && FirebaseAuthService.instance.isLinkedAccount) {
      unawaited(_silentRestore());
    }
  }

  /// フォアグラウンド復帰時にティアを再取得
  Future<void> refreshTier() async {
    await _fetchTierFromFirestore();
  }

  /// バックグラウンドでストアから購入を復元（UIブロックしない）
  Future<void> _silentRestore() async {
    try {
      await ensureStoreReady();
      if (_purchaseService == null) return;
      await _purchaseService!.restore();
      await _purchaseService!
          .waitForPendingVerifications(settleDelay: restoreDelay);
      await _fetchTierFromFirestore();
    } catch (e) {
      debugPrint('Silent restore failed: $e');
    }
  }

  /// 購入を開始
  Future<void> purchase() async {
    if (!FirebaseAuthService.instance.isLinkedAccount) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: _l10n().errSignInRequiredForPremium,
      );
      return;
    }
    try {
      await ensureStoreReady();
      if (_purchaseService == null || state.product == null) {
        state = state.copyWith(
          isLoading: false,
          errorMessage: _l10n().errProductLoadFailed,
        );
        return;
      }
      state = state.copyWith(isLoading: true, errorMessage: null);
      await _purchaseService!.buy(state.product!);
    } catch (e) {
      debugPrint('Failed to start purchase: $e');
      state = state.copyWith(
          isLoading: false, errorMessage: _l10n().errPurchaseStartFailed);
    }
  }

  /// 購入を復元（機種変更・再インストール後に過去の有効な購入を復元）
  ///
  /// ストアに復元リクエスト → サーバー検証 → Firestore 更新の一連の流れが完了するまで
  /// 2秒の待機を入れてから Firestore を再読み込みしている。
  /// （復元イベントは purchaseStream 経由で非同期に届くため、即座に Firestore を
  ///   読んでも反映されていない可能性がある）
  Future<void> restore() async {
    if (!FirebaseAuthService.instance.isLinkedAccount) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: _l10n().errSignInRequiredForPremium,
      );
      return;
    }
    try {
      await ensureStoreReady();
      if (_purchaseService == null) {
        state = state.copyWith(
          isLoading: false,
          errorMessage: _l10n().errStoreUnavailable,
        );
        return;
      }
      state = state.copyWith(isLoading: true, errorMessage: null);
      await _purchaseService!.restore();
      // purchaseStream から開始されたサーバー検証が完了してから最新状態を読む。
      await _purchaseService!
          .waitForPendingVerifications(settleDelay: restoreDelay);
      await _fetchTierFromFirestore();
      state = state.copyWith(
        isLoading: false,
        errorMessage: state.isPremium ? null : _l10n().errNothingToRestore,
      );
    } catch (e) {
      debugPrint('Failed to restore purchase: $e');
      state = state.copyWith(
          isLoading: false, errorMessage: _l10n().errRestoreFailed);
    }
  }

  /// Firestore の users/{uid}.tier フィールドからサブスクリプション状態を取得
  ///
  /// サブスク情報がないユーザー（新規/再登録）の場合 true を返す。
  Future<bool> _fetchTierFromFirestore() async {
    final uid = FirebaseAuthService.instance.currentUser?.uid;
    if (uid == null) return false;

    // プレミアムはサインイン（正規アカウント）時のみ有効。
    // 匿名ユーザーはFirestoreの値に関わらずfree扱いとする。
    // 本メソッドはbuild中から呼ばれるため、同期的なstate更新を避ける
    if (!FirebaseAuthService.instance.isLinkedAccount) {
      await Future<void>.delayed(Duration.zero);
      if (!mounted) return false;
      state = state.copyWith(tier: UserTier.free);
      unawaited(_analytics.setUserTier(UserTier.free.name));
      return false;
    }

    try {
      final ref = (_firestore ?? FirebaseFirestore.instance)
          .collection('users')
          .doc(uid);
      final doc = await ref.get();
      if (!mounted) return false;
      final data = doc.data();
      final tier =
          data?['tier'] == 'premium' ? UserTier.premium : UserTier.free;
      state = state.copyWith(tier: tier);
      unawaited(_analytics.setUserTier(tier.name));
      final hasSubscription = data?.containsKey('subscription') ?? false;
      return !hasSubscription && tier != UserTier.premium;
    } catch (_) {
      return false;
    }
  }

  Future<void> ensureStoreReady() {
    final existing = _storeReadyFuture;
    if (existing != null) return existing;

    late final Future<void> future;
    future = _initializeStore().whenComplete(() {
      // isAvailable=false や商品取得失敗は例外にならないため、失敗状態を
      // キャッシュするとアプリ再起動まで購入不能になる。次回表示時に再試行する。
      if (mounted &&
          state.product == null &&
          identical(_storeReadyFuture, future)) {
        _storeReadyFuture = null;
      }
    });
    _storeReadyFuture = future;
    return future;
  }

  Future<void> _loadProduct() async {
    try {
      final product = await _purchaseService?.fetchProduct();
      if (!mounted) return;
      if (product != null) {
        state = state.copyWith(product: product, errorMessage: null);
      } else {
        state = state.copyWith(errorMessage: _l10n().errProductLoadFailed);
      }
    } on PurchaseProductLoadException catch (e) {
      debugPrint('Failed to load product: $e');
      if (!mounted) return;
      state = state.copyWith(errorMessage: e.message);
    } catch (e) {
      debugPrint('Failed to load product: $e');
      if (!mounted) return;
      state = state.copyWith(errorMessage: _l10n().errProductLoadFailed);
    }
  }

  void _onPurchaseCompleted() {
    if (!mounted) return;
    unawaited(refreshTier());
    state = state.copyWith(isLoading: false);
  }

  void _onPurchaseCanceled() {
    if (!mounted) return;
    state = state.copyWith(isLoading: false, errorMessage: null);
  }

  void _onPurchaseError(String message) {
    if (!mounted) return;
    state = state.copyWith(isLoading: false, errorMessage: message);
  }

  void _onPurchasePending(String message) {
    if (!mounted) return;
    state = state.copyWith(isLoading: false, errorMessage: message);
  }

  Future<void> _initializeStore() async {
    try {
      final service = _purchaseService ??= PurchaseService(
        l10n: _l10n,
        functions: FirebaseFunctions.instanceFor(
          region: FirebaseConfig.functionsRegion,
        ),
        analytics: _analytics,
      );

      service.onPurchaseCompleted = _onPurchaseCompleted;
      service.onPurchaseError = _onPurchaseError;
      service.onPurchaseCanceled = _onPurchaseCanceled;
      service.onPurchasePending = _onPurchasePending;

      final available = await service.initialize();
      if (!mounted) return;
      if (!available) {
        state = state.copyWith(
          isLoading: false,
          errorMessage: _l10n().errStoreUnavailable,
        );
        return;
      }
      await _loadProduct();
    } catch (_) {
      _storeReadyFuture = null;
      rethrow;
    }
  }

  @override
  void dispose() {
    _purchaseService?.dispose();
    super.dispose();
  }
}

// ==================== Providers ====================
// Riverpod プロバイダ定義。アプリ内の各画面・プロバイダから参照される。

/// PurchaseService のシングルトンプロバイダ
final purchaseServiceProvider = Provider<PurchaseService>((ref) {
  final service = PurchaseService(
    l10n: () => ref.read(l10nProvider),
    functions:
        FirebaseFunctions.instanceFor(region: FirebaseConfig.functionsRegion),
    analytics: ref.read(analyticsServiceProvider),
  );
  ref.onDispose(() => service.dispose());
  return service;
});

final subscriptionControllerProvider =
    StateNotifierProvider<SubscriptionController, SubscriptionState>((ref) {
  return SubscriptionController(
    analytics: ref.watch(analyticsServiceProvider),
    l10n: () => ref.read(l10nProvider),
  );
});

/// プレミアムかどうかを簡単に参照するプロバイダ
///
/// 使用例: ref.watch(isPremiumProvider) で bool を取得し、
/// 機能制限の分岐や広告表示の制御に使用する。
final isPremiumProvider = Provider<bool>((ref) {
  return ref.watch(subscriptionControllerProvider).isPremium;
});
