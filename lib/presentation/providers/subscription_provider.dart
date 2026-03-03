import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/config/app_config.dart';
import '../../core/config/firebase_config.dart';
import '../../services/firebase_auth_service.dart';
import '../../services/purchase_service.dart';

// ==================== Subscription State ====================

/// dev環境でのデフォルトティア
const _devDefaultTier = UserTier.free;

enum UserTier { free, premium }

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

class SubscriptionController extends StateNotifier<SubscriptionState> {
  SubscriptionController({PurchaseService? purchaseService})
      : _purchaseService = purchaseService,
        super(SubscriptionState(
          tier: AppConfig.isDev ? _devDefaultTier : UserTier.free,
        ));

  PurchaseService? _purchaseService;

  /// PurchaseServiceを設定（main.dartから呼び出し）
  void setPurchaseService(PurchaseService service) {
    _purchaseService = service;
    _purchaseService!.onPurchaseCompleted = _onPurchaseCompleted;
    _purchaseService!.onPurchaseError = _onPurchaseError;
  }

  /// Firestoreからティアを取得（dev時はSharedPreferencesから復元）
  Future<void> initialize() async {
    if (AppConfig.isDev) {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(AppConfig.prefKeyDevTier);
      state = state.copyWith(
        tier: saved == 'premium' ? UserTier.premium : UserTier.free,
      );
      return;
    }

    await _fetchTierFromFirestore();
    // 商品情報を取得
    _loadProduct();
  }

  /// フォアグラウンド復帰時にティアを再取得
  Future<void> refreshTier() async {
    if (AppConfig.isDev) return;
    await _fetchTierFromFirestore();
  }

  /// 購入を開始
  Future<void> purchase() async {
    if (_purchaseService == null || state.product == null) return;
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      await _purchaseService!.buy(state.product!);
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: '購入を開始できませんでした');
    }
  }

  /// 購入を復元
  Future<void> restore() async {
    if (_purchaseService == null) return;
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      await _purchaseService!.restore();
      // 復元後にFirestoreから最新状態を取得
      await Future.delayed(const Duration(seconds: 2));
      await _fetchTierFromFirestore();
      state = state.copyWith(isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: '復元に失敗しました');
    }
  }

  /// [dev] Free ↔ Premium をトグルしSharedPreferencesに永続化
  Future<void> toggleTier() async {
    if (!AppConfig.isDev) return;
    final newTier = state.isPremium ? UserTier.free : UserTier.premium;
    state = state.copyWith(tier: newTier);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      AppConfig.prefKeyDevTier,
      newTier == UserTier.premium ? 'premium' : 'free',
    );
  }

  Future<void> _fetchTierFromFirestore() async {
    final uid = FirebaseAuthService.instance.currentUser?.uid;
    if (uid == null) return;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      final tier =
          doc.data()?['tier'] == 'premium' ? UserTier.premium : UserTier.free;
      state = state.copyWith(tier: tier);
    } catch (_) {
      // Firestore通信エラー時はデフォルト状態を維持
    }
  }

  Future<void> _loadProduct() async {
    try {
      final product = await _purchaseService?.fetchProduct();
      if (product != null) {
        state = state.copyWith(product: product);
      }
    } catch (e) {
      debugPrint('Failed to load product: $e');
    }
  }

  void _onPurchaseCompleted() {
    refreshTier();
    state = state.copyWith(isLoading: false);
  }

  void _onPurchaseError(String message) {
    state = state.copyWith(isLoading: false, errorMessage: message);
  }
}

// ==================== Providers ====================

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
  return SubscriptionController();
});

/// プレミアムかどうかを簡単に参照するプロバイダ
final isPremiumProvider = Provider<bool>((ref) {
  return ref.watch(subscriptionControllerProvider).isPremium;
});
