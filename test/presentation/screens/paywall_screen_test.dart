/// ペイウォールのプラン選択のテスト
///
/// 検証する仕様:
/// - 月額と買い切りが両方出て、既定は月額が選ばれている
/// - 買い切りを選ぶと、購入は買い切り商品に向く
/// - 買い切りを売っていない環境（商品が引けない）ではプラン選択を出さない
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:thai_memo/l10n/app_localizations.dart';
import 'package:thai_memo/presentation/providers/analytics_provider.dart';
import 'package:thai_memo/presentation/providers/remaining_quota_provider.dart';
import 'package:thai_memo/presentation/providers/subscription_provider.dart';
import 'package:thai_memo/presentation/screens/paywall_screen.dart';
import 'package:thai_memo/services/firebase_auth_service.dart';

import '../../helpers/fake_firebase.dart';

ProductDetails _product(String id, String price, double rawPrice) {
  return ProductDetails(
    id: id,
    title: id,
    description: id,
    price: price,
    rawPrice: rawPrice,
    currencyCode: 'JPY',
  );
}

/// ストアから商品を引き終えた状態の controller。
class _ReadyController extends SubscriptionController {
  _ReadyController({
    required super.analytics,
    required super.l10n,
    required super.purchaseService,
    required bool withLifetime,
  }) : super(firestore: FakeFirestore()) {
    state = SubscriptionState(
      product: _product('premium_monthly', '¥600', 600),
      lifetimeProduct:
          withLifetime ? _product('premium_lifetime', '¥1,800', 1800) : null,
    );
  }

  // ストアには触らせない。商品はコンストラクタで入れ終えている。
  @override
  Future<void> ensureStoreReady() async {}
}

Future<void> _pump(
  WidgetTester tester, {
  required FakePurchaseService purchase,
  bool withLifetime = true,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        analyticsServiceProvider.overrideWithValue(FakeAnalyticsService()),
        userDocProvider.overrideWith((ref) => Stream.value(null)),
        subscriptionControllerProvider.overrideWith(
          (ref) => _ReadyController(
            analytics: FakeAnalyticsService(),
            l10n: () => lookupL10n(const Locale('ja')),
            purchaseService: purchase,
            withLifetime: withLifetime,
          ),
        ),
      ],
      child: MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        locale: const Locale('ja'),
        home: const Scaffold(body: PaywallBottomSheet(source: 'test')),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  late FakeFirebaseAuth auth;
  late FakePurchaseService purchase;

  setUp(() {
    auth = FakeFirebaseAuth();
    auth.user = FakeUser(uid: 'linked-uid', isAnonymous: false);
    FirebaseAuthService.authOverride = auth;
    purchase = FakePurchaseService();
  });

  tearDown(() {
    FirebaseAuthService.authOverride = null;
  });

  testWidgets('月額と買い切りを価格つきで並べる', (tester) async {
    await _pump(tester, purchase: purchase);

    expect(find.text('月額プラン'), findsOneWidget);
    expect(find.text('¥600 / 月'), findsOneWidget);
    expect(find.text('買い切り'), findsOneWidget);
    expect(find.text('¥1,800'), findsOneWidget);
  });

  testWidgets('既定は月額。そのまま押すと月額を買う', (tester) async {
    await _pump(tester, purchase: purchase);

    await tester.tap(find.text('このプランで始める'));
    // 購入中はボタンが進捗表示に変わって回り続けるので settle させない。
    await tester.pump();

    expect(purchase.lastBought?.id, 'premium_monthly');
  });

  testWidgets('買い切りを選んでから押すと買い切りを買う', (tester) async {
    await _pump(tester, purchase: purchase);

    await tester.tap(find.text('買い切り'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('このプランで始める'));
    await tester.pump();

    expect(purchase.lastBought?.id, 'premium_lifetime');
  });

  testWidgets('買い切りを売っていない環境ではプラン選択を出さない', (tester) async {
    await _pump(tester, purchase: purchase, withLifetime: false);

    expect(find.text('買い切り'), findsNothing);
    // 選択肢が1つなら、これまで通りの「プレミアムに登録」のまま。
    expect(find.text('プレミアムに登録'), findsOneWidget);
    expect(find.text('このプランで始める'), findsNothing);
  });
}
