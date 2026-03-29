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
/// - 例文生成: Free=1日1回 / Premium=1日10回
/// - クイズ: Free=1日2回 / Premium=1日10回
/// - 選べる単語: Free=300語まで / Premium=無制限
/// - トピック: Free=4種 / Premium=16種
/// - 文体: Free=2種 / Premium=5種
/// - 広告: Free=あり / Premium=なし
///
/// 【関連ファイル】
/// - purchase_service.dart: ストア決済処理（購入・復元・検証依頼）
/// - paywall_screen.dart: プレミアムプラン購入 UI
/// - generation_constants.dart: Free/Premium のパラメータ制限値
/// - ad_provider.dart: Premium 時の広告非表示制御
library;

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
  SubscriptionController({
    required AnalyticsService analytics,
  })  : _analytics = analytics,
        super(const SubscriptionState(tier: UserTier.free));

  final AnalyticsService _analytics;
  PurchaseService? _purchaseService;
  Future<void>? _storeReadyFuture;

  /// 初期化: Firestore から現在のティアを取得し、商品情報をロード
  ///
  /// アプリ起動時に main.dart から1回呼び出される。
  Future<void> initialize() async {
    await _fetchTierFromFirestore();
  }

  /// フォアグラウンド復帰時にティアを再取得
  Future<void> refreshTier() async {
    await _fetchTierFromFirestore();
  }

  /// 購入を開始
  Future<void> purchase() async {
    await ensureStoreReady();
    if (_purchaseService == null || state.product == null) {
      state = state.copyWith(errorMessage: '課金商品を取得できませんでした');
      return;
    }
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      await _purchaseService!.buy(state.product!);
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: '購入を開始できませんでした');
    }
  }

  /// 購入を復元（機種変更・再インストール後に過去の有効な購入を復元）
  ///
  /// ストアに復元リクエスト → サーバー検証 → Firestore 更新の一連の流れが完了するまで
  /// 2秒の待機を入れてから Firestore を再読み込みしている。
  /// （復元イベントは purchaseStream 経由で非同期に届くため、即座に Firestore を
  ///   読んでも反映されていない可能性がある）
  Future<void> restore() async {
    await ensureStoreReady();
    if (_purchaseService == null) return;
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      await _purchaseService!.restore();
      // 復元後にFirestoreから最新状態を取得（サーバー検証完了を待つため遅延）
      await Future.delayed(const Duration(seconds: 2));
      await _fetchTierFromFirestore();
      state = state.copyWith(isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: '復元に失敗しました');
    }
  }

  /// Firestore の users/{uid}.tier フィールドからサブスクリプション状態を取得
  ///
  /// tier フィールドは以下のタイミングでサーバー側が更新する:
  /// - 購入検証時（verifySubscription）: 'premium' に設定
  /// - ストア通知受信時（handleAppStoreNotification / handlePlayNotification）:
  ///   更新・解約・期限切れに応じて 'premium' or 'free' に設定
  /// - 有効期限超過時（subscriptionStatus）: 'free' にフォールバック
  Future<void> _fetchTierFromFirestore() async {
    final uid = FirebaseAuthService.instance.currentUser?.uid;
    if (uid == null) return;

    try {
      final doc =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final tier =
          doc.data()?['tier'] == 'premium' ? UserTier.premium : UserTier.free;
      state = state.copyWith(tier: tier);
      unawaited(_analytics.setUserTier(tier.name));
    } catch (_) {
      // Firestore通信エラー時はデフォルト状態を維持
    }
  }

  Future<void> ensureStoreReady() {
    final existing = _storeReadyFuture;
    if (existing != null) return existing;

    final future = _initializeStore();
    _storeReadyFuture = future;
    return future;
  }

  Future<void> _loadProduct() async {
    try {
      final product = await _purchaseService?.fetchProduct();
      if (product != null) {
        state = state.copyWith(product: product, errorMessage: null);
      } else {
        state = state.copyWith(errorMessage: '課金商品を取得できませんでした');
      }
    } on PurchaseProductLoadException catch (e) {
      debugPrint('Failed to load product: $e');
      state = state.copyWith(errorMessage: e.message);
    } catch (e) {
      debugPrint('Failed to load product: $e');
      state = state.copyWith(errorMessage: '課金商品を取得できませんでした');
    }
  }

  void _onPurchaseCompleted() {
    refreshTier();
    state = state.copyWith(isLoading: false);
  }

  void _onPurchaseError(String message) {
    state = state.copyWith(isLoading: false, errorMessage: message);
  }

  Future<void> _initializeStore() async {
    try {
      final service = _purchaseService ??= PurchaseService(
        functions: FirebaseFunctions.instanceFor(
          region: FirebaseConfig.functionsRegion,
        ),
      );

      service.onPurchaseCompleted = _onPurchaseCompleted;
      service.onPurchaseError = _onPurchaseError;

      final available = await service.initialize();
      if (!available) {
        state = state.copyWith(errorMessage: 'App Storeに接続できませんでした');
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
    functions:
        FirebaseFunctions.instanceFor(region: FirebaseConfig.functionsRegion),
  );
  ref.onDispose(() => service.dispose());
  return service;
});

final subscriptionControllerProvider =
    StateNotifierProvider<SubscriptionController, SubscriptionState>((ref) {
  return SubscriptionController(
    analytics: ref.watch(analyticsServiceProvider),
  );
});

/// プレミアムかどうかを簡単に参照するプロバイダ
///
/// 使用例: ref.watch(isPremiumProvider) で bool を取得し、
/// 機能制限の分岐や広告表示の制御に使用する。
final isPremiumProvider = Provider<bool>((ref) {
  return ref.watch(subscriptionControllerProvider).isPremium;
});
