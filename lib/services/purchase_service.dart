import 'dart:async';
import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../core/config/firebase_config.dart';

/// アプリ内課金の商品ID
const String kProductIdPremiumMonthly = 'premium_monthly';

/// 購入状態の変化を通知するコールバック型
typedef PurchaseCallback = void Function();

/// in_app_purchase のラッパーサービス
///
/// 購入処理・検証・復元を一元管理する。
class PurchaseService {
  PurchaseService({
    FirebaseFunctions? functions,
  }) : _functions = functions ??
            FirebaseFunctions.instanceFor(
                region: FirebaseConfig.functionsRegion);

  final InAppPurchase _iap = InAppPurchase.instance;
  final FirebaseFunctions _functions;
  StreamSubscription<List<PurchaseDetails>>? _subscription;

  /// 購入完了時のコールバック（SubscriptionControllerがセット）
  PurchaseCallback? onPurchaseCompleted;

  /// 購入エラー時のコールバック
  void Function(String message)? onPurchaseError;

  /// サービスを初期化し、購入ストリームの監視を開始
  Future<bool> initialize() async {
    final available = await _iap.isAvailable();
    if (!available) return false;

    _subscription = _iap.purchaseStream.listen(
      _onPurchaseUpdate,
      onDone: () => _subscription?.cancel(),
      onError: (Object error) {
        debugPrint('Purchase stream error: $error');
      },
    );
    return true;
  }

  /// 商品情報を取得
  Future<ProductDetails?> fetchProduct() async {
    final response =
        await _iap.queryProductDetails({kProductIdPremiumMonthly});
    if (response.error != null) {
      debugPrint('Product query error: ${response.error}');
      return null;
    }
    if (response.productDetails.isEmpty) return null;
    return response.productDetails.first;
  }

  /// 購入を開始
  Future<void> buy(ProductDetails product) async {
    final purchaseParam = PurchaseParam(productDetails: product);
    await _iap.buyNonConsumable(purchaseParam: purchaseParam);
  }

  /// 購入を復元
  Future<void> restore() async {
    await _iap.restorePurchases();
  }

  /// 購入ストリームのハンドラ
  void _onPurchaseUpdate(List<PurchaseDetails> purchases) {
    for (final purchase in purchases) {
      switch (purchase.status) {
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          _verifyAndComplete(purchase);
          break;
        case PurchaseStatus.error:
          onPurchaseError?.call(purchase.error?.message ?? '購入エラーが発生しました');
          _completePurchaseIfNeeded(purchase);
          break;
        case PurchaseStatus.canceled:
          _completePurchaseIfNeeded(purchase);
          break;
        case PurchaseStatus.pending:
          // 処理待ち - 何もしない
          break;
      }
    }
  }

  /// サーバー側で検証してから購入を完了
  Future<void> _verifyAndComplete(PurchaseDetails purchase) async {
    try {
      final callable = _functions.httpsCallable(
        FirebaseConfig.verifySubscriptionFunctionName,
        options: HttpsCallableOptions(
          timeout: const Duration(seconds: 30),
        ),
      );

      await callable.call<dynamic>({
        'platform': Platform.isIOS ? 'ios' : 'android',
        'purchase_token': purchase.verificationData.serverVerificationData,
        'product_id': purchase.productID,
      });

      onPurchaseCompleted?.call();
    } catch (e) {
      debugPrint('Verification failed: $e');
      onPurchaseError?.call('購入の検証に失敗しました');
    } finally {
      _completePurchaseIfNeeded(purchase);
    }
  }

  void _completePurchaseIfNeeded(PurchaseDetails purchase) {
    if (purchase.pendingCompletePurchase) {
      _iap.completePurchase(purchase);
    }
  }

  /// リソースの解放
  void dispose() {
    _subscription?.cancel();
  }
}
