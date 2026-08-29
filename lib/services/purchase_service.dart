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

import '../l10n/app_localizations.dart';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../core/config/firebase_config.dart';
import 'analytics_service.dart';
import 'firebase_auth_service.dart';

/// アプリ内課金の商品ID（App Store Connect / Google Play Console で登録した ID と一致させる）
/// tester環境では premium_monthly_test、それ以外は premium_monthly を使用
const String kProductIdPremiumMonthly =
    String.fromEnvironment('ENV') == 'tester'
        ? 'premium_monthly_test'
        : 'premium_monthly';

/// 購入状態の変化を通知するコールバック型
typedef PurchaseCallback = void Function();
typedef PurchaseVerifier = Future<void> Function(PurchaseDetails purchase);

/// 課金商品の取得失敗時に、UIへ表示するための説明付き例外
class PurchaseProductLoadException implements Exception {
  PurchaseProductLoadException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// in_app_purchase パッケージのラッパーサービス
///
/// 購入フロー（開始→ストリーム監視→サーバー検証→完了）を一元管理する。
/// SubscriptionController から呼び出され、購入結果をコールバックで返す。
class PurchaseService {
  PurchaseService({
    required this.l10n,
    FirebaseFunctions? functions,
    AnalyticsService? analytics,
    InAppPurchase? iap,
    PurchaseVerifier? verifier,
  })  : _functions = functions,
        _analytics = analytics,
        _iap = iap ?? InAppPurchase.instance,
        _verifier = verifier;

  final InAppPurchase _iap;
  final FirebaseFunctions? _functions;
  final PurchaseVerifier? _verifier;

  /// 購入結果の計測先。未指定なら計測しない（テスト用）。
  final AnalyticsService? _analytics;
  StreamSubscription<List<PurchaseDetails>>? _subscription;
  final Set<Future<void>> _pendingVerifications = {};

  /// 購入完了時のコールバック（SubscriptionControllerがセット）
  PurchaseCallback? onPurchaseCompleted;

  /// 購入エラー時のコールバック
  /// 文言は言語設定に追従させたいので、値ではなく都度引く関数を持つ。
  final L10n Function() l10n;

  void Function(String message)? onPurchaseError;

  /// 購入キャンセル時のコールバック
  PurchaseCallback? onPurchaseCanceled;

  /// 購入が承認待ちになった時のコールバック
  void Function(String message)? onPurchasePending;

  /// サービスを初期化し、購入ストリームの監視を開始
  ///
  /// purchaseStream はアプリ起動中の全購入イベント（新規購入・復元・エラー・キャンセル）を
  /// リアルタイムで配信するストリーム。OS 側の決済処理完了後に自動的にイベントが届く。
  /// アプリ起動時に1回だけ呼び出す（main.dart で実行）。
  Future<bool> initialize() async {
    if (_subscription != null) return true;

    final available = await _iap.isAvailable();
    if (!available) return false;

    _subscription = _iap.purchaseStream.listen(
      _onPurchaseUpdate,
      onDone: () {
        _subscription?.cancel();
        _subscription = null;
      },
      onError: (Object error) {
        debugPrint('Purchase stream error: $error');
        final failedSubscription = _subscription;
        _subscription = null;
        unawaited(failedSubscription?.cancel() ?? Future<void>.value());
        onPurchaseError?.call(l10n().errPurchaseStatusFailed);
      },
    );
    return true;
  }

  /// 商品情報を取得
  Future<ProductDetails?> fetchProduct() async {
    final response = await _iap.queryProductDetails({kProductIdPremiumMonthly});
    if (response.error != null) {
      debugPrint('Product query error: ${response.error}');
      throw PurchaseProductLoadException(
        response.error!.message,
      );
    }

    if (response.notFoundIDs.contains(kProductIdPremiumMonthly)) {
      throw PurchaseProductLoadException(
        'App Storeで課金商品 $kProductIdPremiumMonthly が見つかりませんでした',
      );
    }

    if (response.productDetails.isEmpty) {
      throw PurchaseProductLoadException(l10n().errProductLoadFailed);
    }

    return response.productDetails.first;
  }

  /// 購入を開始（OS ネイティブの決済シートを表示）
  ///
  /// 呼び出し後、OS の決済 UI が表示される。結果は purchaseStream 経由で非同期に届く。
  /// buyNonConsumable を使用するが、サブスクリプションも in_app_purchase では
  /// この API で処理する（consumable は消費型アイテム用）。
  Future<void> buy(ProductDetails product) async {
    final purchaseParam = PurchaseParam(productDetails: product);
    final started = await _iap.buyNonConsumable(purchaseParam: purchaseParam);
    if (!started) {
      throw StateError('Store did not accept the purchase request');
    }
  }

  /// 購入を復元（機種変更・再インストール時に過去の購入を復元）
  ///
  /// App Store / Google Play に問い合わせ、有効なサブスクリプションがあれば
  /// purchaseStream に PurchaseStatus.restored イベントが届く。
  Future<void> restore() async {
    await _iap.restorePurchases();
  }

  /// restorePurchases が purchaseStream へ流した購入のサーバー検証完了を待つ。
  ///
  /// ストアAPIの Future 完了と purchaseStream の配送には僅かなずれがあるため、
  /// [settleDelay] だけ配送を待ってから、その時点の検証をすべて待機する。
  Future<void> waitForPendingVerifications({
    Duration settleDelay = const Duration(milliseconds: 500),
    Duration timeout = const Duration(seconds: 35),
  }) async {
    await Future<void>.delayed(settleDelay);
    final deadline = DateTime.now().add(timeout);

    while (_pendingVerifications.isNotEmpty) {
      final remaining = deadline.difference(DateTime.now());
      if (remaining <= Duration.zero) {
        throw TimeoutException('Purchase verification did not finish', timeout);
      }
      await Future.wait<void>(_pendingVerifications.toList())
          .timeout(remaining);
      // 完了直後に同じ restore バッチの次イベントが追加される場合に備える。
      await Future<void>.delayed(Duration.zero);
    }
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
          _logResult('purchased');
          _startVerification(purchase);
          break;
        case PurchaseStatus.restored:
          _logResult('restored');
          _startVerification(purchase);
          break;
        case PurchaseStatus.error:
          _logResult('error', code: purchase.error?.code);
          onPurchaseError
              ?.call(purchase.error?.message ?? l10n().errPurchaseGeneric);
          unawaited(_completePurchaseIfNeeded(purchase));
          break;
        case PurchaseStatus.canceled:
          _logResult('canceled');
          onPurchaseCanceled?.call();
          unawaited(_completePurchaseIfNeeded(purchase));
          break;
        case PurchaseStatus.pending:
          _logResult('pending');
          onPurchasePending?.call(l10n().purchasePending);
          break;
      }
    }
  }

  void _logResult(String status, {String? code}) {
    unawaited(_analytics?.logPurchaseResult(status: status, code: code) ??
        Future<void>.value());
  }

  void _startVerification(PurchaseDetails purchase) {
    late final Future<void> task;
    task = _verifyAndComplete(purchase).whenComplete(() {
      _pendingVerifications.remove(task);
    });
    _pendingVerifications.add(task);
    unawaited(task);
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
    // 未ログイン時はCloud Functionを呼べない
    if (!FirebaseAuthService.instance.isAuthenticated) {
      debugPrint('Verification skipped: user not authenticated');
      unawaited(
          _analytics?.logPurchaseVerify(ok: false, code: 'unauthenticated') ??
              Future<void>.value());
      onPurchaseError?.call(l10n().errSignInBeforePurchase);
      // entitlement を付与できていないので取引を完了しない。サインイン後または
      // 次回起動時にストアから再配信・復元できる状態を保つ。
      return;
    }

    try {
      final verifier = _verifier;
      if (verifier != null) {
        await verifier(purchase);
      } else {
        final functions = _functions ??
            FirebaseFunctions.instanceFor(
              region: FirebaseConfig.functionsRegion,
            );
        final callable = functions.httpsCallable(
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
      }

      unawaited(
          _analytics?.logPurchaseVerify(ok: true) ?? Future<void>.value());
      onPurchaseCompleted?.call();
      await _completePurchaseIfNeeded(purchase);
    } catch (e) {
      debugPrint('Verification failed: $e');
      unawaited(_analytics?.logPurchaseVerify(
            ok: false,
            code: e is FirebaseFunctionsException ? e.code : 'unknown',
          ) ??
          Future<void>.value());
      onPurchaseError?.call(l10n().errPurchaseVerificationFailed);
      // サーバー検証に失敗した購入は完了扱いにしない。ストアの再配信または
      // 「購入を復元」から安全に再検証できるようにする。
    }
  }

  /// 購入トランザクションを完了としてマークする
  ///
  /// completePurchase を呼ばないと、ストア側でトランザクションが未完了のまま残り、
  /// 次回アプリ起動時に再度 purchaseStream にイベントが届いてしまう。
  /// entitlement の付与後だけ呼ぶ。検証前に完了すると、一時障害時に
  /// 「課金済みだがプレミアム未付与」の取引を再取得できなくなる。
  Future<void> _completePurchaseIfNeeded(PurchaseDetails purchase) async {
    if (purchase.pendingCompletePurchase) {
      try {
        await _iap.completePurchase(purchase);
      } catch (e) {
        debugPrint('completePurchase error: $e');
      }
    }
  }

  /// リソースの解放
  void dispose() {
    _subscription?.cancel();
  }
}
