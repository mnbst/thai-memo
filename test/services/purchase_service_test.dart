import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:thai_memo/l10n/app_localizations.dart';
import 'package:thai_memo/services/firebase_auth_service.dart';
import 'package:thai_memo/services/purchase_service.dart';

import '../helpers/fake_firebase.dart';

class _FakeInAppPurchase extends Fake implements InAppPurchase {
  final StreamController<List<PurchaseDetails>> updates =
      StreamController<List<PurchaseDetails>>.broadcast();
  final List<PurchaseDetails> completed = [];
  bool buyAccepted = true;

  @override
  Stream<List<PurchaseDetails>> get purchaseStream => updates.stream;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<bool> buyNonConsumable({required PurchaseParam purchaseParam}) async {
    return buyAccepted;
  }

  @override
  Future<void> completePurchase(PurchaseDetails purchase) async {
    completed.add(purchase);
  }

  @override
  Future<void> restorePurchases({String? applicationUserName}) async {}
}

PurchaseDetails _purchase() {
  final purchase = PurchaseDetails(
    purchaseID: 'tx-1',
    productID: kProductIdPremiumMonthly,
    verificationData: PurchaseVerificationData(
      localVerificationData: 'local',
      serverVerificationData: 'server',
      source: 'test',
    ),
    transactionDate: '1',
    status: PurchaseStatus.purchased,
  );
  purchase.pendingCompletePurchase = true;
  return purchase;
}

ProductDetails _product() => ProductDetails(
      id: kProductIdPremiumMonthly,
      title: 'Premium',
      description: 'Premium',
      price: '¥800',
      rawPrice: 800,
      currencyCode: 'JPY',
    );

void main() {
  late FakeFirebaseAuth auth;
  late _FakeInAppPurchase iap;

  setUp(() {
    auth = FakeFirebaseAuth()
      ..user = FakeUser(uid: 'linked-user', isAnonymous: false);
    FirebaseAuthService.authOverride = auth;
    iap = _FakeInAppPurchase();
  });

  tearDown(() async {
    FirebaseAuthService.authOverride = null;
    await iap.updates.close();
  });

  test('サーバー検証成功後だけ購入を完了する', () async {
    var completedCallback = false;
    final service = PurchaseService(
      l10n: () => lookupL10n(const Locale('ja')),
      iap: iap,
      verifier: (_) async {},
    );
    service.onPurchaseCompleted = () => completedCallback = true;
    addTearDown(service.dispose);
    await service.initialize();

    iap.updates.add([_purchase()]);
    await Future<void>.delayed(Duration.zero);
    await service.waitForPendingVerifications(settleDelay: Duration.zero);

    expect(completedCallback, isTrue);
    expect(iap.completed, hasLength(1));
  });

  test('サーバー検証失敗時は購入を完了せず再取得可能にする', () async {
    String? errorMessage;
    final service = PurchaseService(
      l10n: () => lookupL10n(const Locale('ja')),
      iap: iap,
      verifier: (_) async => throw StateError('temporary'),
    );
    service.onPurchaseError = (message) => errorMessage = message;
    addTearDown(service.dispose);
    await service.initialize();

    iap.updates.add([_purchase()]);
    await Future<void>.delayed(Duration.zero);
    await service.waitForPendingVerifications(settleDelay: Duration.zero);

    expect(errorMessage, isNotNull);
    expect(iap.completed, isEmpty);
  });

  test('ストアが購入要求を受理しなければ失敗にする', () async {
    iap.buyAccepted = false;
    final service = PurchaseService(
      l10n: () => lookupL10n(const Locale('ja')),
      iap: iap,
    );
    addTearDown(service.dispose);

    await expectLater(service.buy(_product()), throwsStateError);
  });
}
