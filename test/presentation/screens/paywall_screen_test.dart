/// ペイウォールのプラン選択のテスト
///
/// 検証する仕様:
/// - 月額と買い切りが両方出て、既定は月額が選ばれている
/// - 買い切りを選ぶと、購入は買い切り商品に向く
/// - 年額を選ぶと、購入は年額商品に向く
/// - 月額しか引けない環境ではプラン選択を出さない
/// - 小さい iPhone（SE）でもはみ出さず、購入ボタンが画面内に残る
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
    required bool withYearly,
    required bool withLifetime,
    bool isPremium = false,
  }) : super(firestore: FakeFirestore()) {
    state = SubscriptionState(
      tier: isPremium ? UserTier.premium : UserTier.free,
      product: _product('premium_monthly', '¥600', 600),
      yearlyProduct:
          withYearly ? _product('premium_annual', '¥4,800', 4800) : null,
      lifetimeProduct:
          withLifetime ? _product('premium_lifetime', '¥5,800', 5800) : null,
    );
  }

  // ストアには触らせない。商品はコンストラクタで入れ終えている。
  @override
  Future<void> ensureStoreReady() async {}
}

Future<void> _pump(
  WidgetTester tester, {
  required FakePurchaseService purchase,
  bool withYearly = true,
  bool withLifetime = true,
  bool isPremium = false,
  Map<String, dynamic>? userData,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        analyticsServiceProvider.overrideWithValue(FakeAnalyticsService()),
        userDocSnapshotProvider.overrideWith(
          (ref) => Stream.value(
            UserDocSnapshot(data: userData, isFromCache: false),
          ),
        ),
        subscriptionControllerProvider.overrideWith(
          (ref) => _ReadyController(
            analytics: FakeAnalyticsService(),
            l10n: () => lookupL10n(const Locale('ja')),
            purchaseService: purchase,
            withYearly: withYearly,
            withLifetime: withLifetime,
            isPremium: isPremium,
          ),
        ),
      ],
      child: MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        locale: const Locale('ja'),
        home: const PaywallScreen(source: 'test'),
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

  testWidgets('月額・年額・買い切りを価格つきで並べる', (tester) async {
    await _pump(tester, purchase: purchase);

    expect(find.text('月額プラン'), findsOneWidget);
    expect(find.text('¥600 / 月'), findsOneWidget);
    expect(find.text('年額プラン'), findsOneWidget);
    expect(find.text('¥4,800 / 年'), findsOneWidget);
    expect(find.text('買い切り'), findsOneWidget);
    expect(find.text('¥5,800'), findsOneWidget);
  });

  testWidgets('小さい iPhone（SE）でもはみ出さず、購入ボタンが画面内に残る', (tester) async {
    tester.view.physicalSize = const Size(750, 1334);
    tester.view.devicePixelRatio = 2;
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await _pump(tester, purchase: purchase);

    expect(tester.takeException(), isNull);
    expect(find.text('このプランで始める').hitTestable(), findsOneWidget);
    // 特典の下にあるプラン欄も、スクロールすれば届く。
    await tester.scrollUntilVisible(find.text('買い切り'), 200);
    expect(find.text('買い切り').hitTestable(), findsOneWidget);
  });

  testWidgets('既定は月額。そのまま押すと月額を買う', (tester) async {
    await _pump(tester, purchase: purchase);

    await tester.tap(find.text('このプランで始める'));
    // 購入中はボタンが進捗表示に変わって回り続けるので settle させない。
    await tester.pump();

    expect(purchase.lastBought?.id, 'premium_monthly');
  });

  testWidgets('年額を選んでから押すと年額を買う', (tester) async {
    await _pump(tester, purchase: purchase);

    await tester.ensureVisible(find.text('年額プラン'));
    await tester.tap(find.text('年額プラン'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('このプランで始める'));
    await tester.pump();

    expect(purchase.lastBought?.id, 'premium_annual');
  });

  testWidgets('買い切りを選んでから押すと買い切りを買う', (tester) async {
    await _pump(tester, purchase: purchase);

    await tester.ensureVisible(find.text('買い切り'));
    await tester.tap(find.text('買い切り'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('このプランで始める'));
    await tester.pump();

    expect(purchase.lastBought?.id, 'premium_lifetime');
  });

  testWidgets('買い切りを売っていない環境（Android）でも月額と年額は選べる', (tester) async {
    await _pump(tester, purchase: purchase, withLifetime: false);

    expect(find.text('買い切り'), findsNothing);
    expect(find.text('月額プラン'), findsOneWidget);
    expect(find.text('年額プラン'), findsOneWidget);
    expect(find.text('このプランで始める'), findsOneWidget);
  });

  testWidgets('月額しか引けない環境ではプラン選択を出さない', (tester) async {
    await _pump(
      tester,
      purchase: purchase,
      withYearly: false,
      withLifetime: false,
    );

    expect(find.text('年額プラン'), findsNothing);
    expect(find.text('買い切り'), findsNothing);
    // 選択肢が1つなら、これまで通りの「プレミアムに登録」のまま。
    expect(find.text('プレミアムに登録'), findsOneWidget);
    expect(find.text('このプランで始める'), findsNothing);
  });

  testWidgets('名簿外の月額加入者は期限切れを待たず買い切りへ変更できる', (tester) async {
    await _pump(
      tester,
      purchase: purchase,
      isPremium: true,
      userData: {
        'tier': 'premium',
        'subscription': {
          'platform': 'ios',
          'product_id': 'premium_monthly',
          'status': 'active',
          'lifetime': false,
        },
      },
    );

    expect(find.text('プレミアムプランに加入中です'), findsNothing);
    expect(find.text('月額プラン'), findsNothing);
    expect(find.text('年額プラン'), findsNothing);
    expect(find.text('買い切り'), findsOneWidget);
    expect(find.text('買い切りへ変更する'), findsOneWidget);
    expect(find.textContaining('現在のサブスクリプションは自動では解約されません'), findsOneWidget);

    await tester.tap(find.text('買い切りへ変更する'));
    await tester.pump();

    expect(purchase.lastBought?.id, 'premium_lifetime');
  });

  testWidgets('無償移行の名簿内ユーザーには買い切りを販売しない', (tester) async {
    await _pump(
      tester,
      purchase: purchase,
      isPremium: true,
      userData: {
        'tier': 'premium',
        'lifetime_migration_eligible': true,
        'subscription': {
          'platform': 'ios',
          'product_id': 'premium_monthly',
          'status': 'active',
          'lifetime': false,
        },
      },
    );

    expect(find.text('プレミアムプランに加入中です'), findsOneWidget);
    expect(find.text('買い切りへ変更する'), findsNothing);
    expect(purchase.lastBought, isNull);
  });

  testWidgets('買い切り所有者には再購入を出さない', (tester) async {
    await _pump(
      tester,
      purchase: purchase,
      isPremium: true,
      userData: {
        'tier': 'premium',
        'subscription': {
          'platform': 'ios',
          'product_id': 'premium_lifetime',
          'status': 'active',
          'lifetime': true,
        },
      },
    );

    expect(find.text('プレミアムプランに加入中です'), findsOneWidget);
    expect(find.text('買い切りへ変更する'), findsNothing);
  });
}
