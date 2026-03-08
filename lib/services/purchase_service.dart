/// purchase_service.dart — アプリ内課金（In-App Purchase）サービス
///
/// 「まいにちタイ語」アプリのサブスクリプション購入を管理するクライアント側サービス。
/// Flutter の in_app_purchase パッケージを使用し、iOS（StoreKit）/ Android（Google Play Billing）
/// 両プラットフォームのアプリ内課金を統一的に扱う。
///
/// 【決済フロー全体像】
/// 1. ユーザーがペイウォール画面で「プレミアムに登録」をタップ
/// 2. 本サービスの buy() で OS ネイティブの決済シートを表示
/// 3. 決済完了後、purchaseStream 経由で購入結果を受信
/// 4. _verifyAndComplete() でサーバー側 Cloud Function（verifySubscription）に
///    購入トークンを送信し、ストア API で正当性を検証
/// 5. 検証成功後、サーバーが Firestore の users/{uid}.tier を 'premium' に更新
/// 6. コールバック経由で SubscriptionController に通知 → UI が更新される
///
/// 【商品構成】
/// - premium_monthly: 月額サブスクリプション（自動更新型）
///   ※ buyNonConsumable() を使用しているが、サブスクリプションは
///     in_app_purchase パッケージでは nonConsumable として扱う仕様
///
/// 【関連ファイル】
/// - subscription_provider.dart: 購入状態の Riverpod 状態管理
/// - paywall_screen.dart: 購入 UI（ペイウォール）
/// - verifySubscription.ts: サーバー側の購入検証 Cloud Function
/// - handleAppStoreNotification.ts: App Store からの更新/解約通知ハンドラ
/// - handlePlayNotification.ts: Google Play からの更新/解約通知ハンドラ
library;

import 'dart:async';
import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../core/config/firebase_config.dart';

/// アプリ内課金の商品ID（App Store Connect / Google Play Console で登録した ID と一致させる）
const String kProductIdPremiumMonthly = 'premium_monthly';

/// 購入状態の変化を通知するコールバック型
typedef PurchaseCallback = void Function();

/// in_app_purchase パッケージのラッパーサービス
///
/// 購入フロー（開始→ストリーム監視→サーバー検証→完了）を一元管理する。
/// SubscriptionController から呼び出され、購入結果をコールバックで返す。
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
  ///
  /// purchaseStream はアプリ起動中の全購入イベント（新規購入・復元・エラー・キャンセル）を
  /// リアルタイムで配信するストリーム。OS 側の決済処理完了後に自動的にイベントが届く。
  /// アプリ起動時に1回だけ呼び出す（main.dart で実行）。
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
    final response = await _iap.queryProductDetails({kProductIdPremiumMonthly});
    if (response.error != null) {
      debugPrint('Product query error: ${response.error}');
      return null;
    }
    if (response.productDetails.isEmpty) return null;
    return response.productDetails.first;
  }

  /// 購入を開始（OS ネイティブの決済シートを表示）
  ///
  /// 呼び出し後、OS の決済 UI が表示される。結果は purchaseStream 経由で非同期に届く。
  /// buyNonConsumable を使用するが、サブスクリプションも in_app_purchase では
  /// この API で処理する（consumable は消費型アイテム用）。
  Future<void> buy(ProductDetails product) async {
    final purchaseParam = PurchaseParam(productDetails: product);
    await _iap.buyNonConsumable(purchaseParam: purchaseParam);
  }

  /// 購入を復元（機種変更・再インストール時に過去の購入を復元）
  ///
  /// App Store / Google Play に問い合わせ、有効なサブスクリプションがあれば
  /// purchaseStream に PurchaseStatus.restored イベントが届く。
  Future<void> restore() async {
    await _iap.restorePurchases();
  }

  /// 購入ストリームのハンドラ（全購入イベントがここに届く）
  ///
  /// purchased/restored → サーバー検証へ進む
  /// error/canceled → エラー通知して購入トランザクションを完了
  /// pending → 決済処理中（親の承認待ちなど）のため何もしない
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

  /// サーバー側 Cloud Function（verifySubscription）で購入の正当性を検証
  ///
  /// クライアント側だけで購入を承認すると不正購入のリスクがあるため、
  /// 必ずサーバー側でストア API（App Store Server API / Google Play Developer API）に
  /// 問い合わせて検証する。検証成功時にサーバーが Firestore の tier を更新する。
  ///
  /// purchase_token の内容はプラットフォームにより異なる:
  /// - iOS: transactionId（App Store Server API で検証に使用）
  /// - Android: purchaseToken（Google Play Developer API で検証に使用）
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

  /// 購入トランザクションを完了としてマークする
  ///
  /// completePurchase を呼ばないと、ストア側でトランザクションが未完了のまま残り、
  /// 次回アプリ起動時に再度 purchaseStream にイベントが届いてしまう。
  /// 検証の成否に関わらず、必ず呼び出す必要がある。
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
