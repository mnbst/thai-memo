// =============================================================================
// paywall_mock_app.dart
// ペイウォール（PaywallScreen）を Firebase・ストアなしでシミュレーターに出す。
// 商品は差し込み、購入はしない。見た目の調整中は r（hot reload）で確かめる。
//
//   flutter run -t test/screenshots/paywall_mock_app.dart
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:thai_memo/core/theme/app_theme.dart';
import 'package:thai_memo/l10n/app_localizations.dart';
import 'package:thai_memo/presentation/providers/analytics_provider.dart';
import 'package:thai_memo/presentation/providers/remaining_quota_provider.dart';
import 'package:thai_memo/presentation/providers/settings_provider.dart';
import 'package:thai_memo/presentation/providers/subscription_provider.dart';
import 'package:thai_memo/presentation/screens/paywall_screen.dart';
import 'package:thai_memo/services/analytics_service.dart';

const _lang = String.fromEnvironment('LANG', defaultValue: 'ja');

void main() => runApp(
      ProviderScope(
        overrides: [
          analyticsServiceProvider.overrideWithValue(_NoopAnalytics()),
          userDocSnapshotProvider.overrideWith(
            (ref) => Stream.value(
                const UserDocSnapshot(data: null, isFromCache: false)),
          ),
          subscriptionControllerProvider
              .overrideWith((ref) => _StubController()),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          locale: const Locale(_lang),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          theme: buildAppLightTheme(ThaiFont.sarabun),
          home: const PaywallScreen(source: 'mock'),
        ),
      ),
    );

class _StubController extends SubscriptionController {
  _StubController()
      : super(
          analytics: _NoopAnalytics(),
          l10n: () => lookupL10n(const Locale(_lang)),
        ) {
    state = SubscriptionState(
      product: _product('premium_monthly', 'プレミアム（月額）', '¥600', 600),
      yearlyProduct: _product('premium_annual', 'プレミアム（年額）', '¥4,800', 4800),
      lifetimeProduct:
          _product('premium_lifetime', 'プレミアム 買い切り', '¥5,800', 5800),
    );
  }

  static ProductDetails _product(
          String id, String title, String price, double rawPrice) =>
      ProductDetails(
        id: id,
        title: title,
        description: title,
        price: price,
        rawPrice: rawPrice,
        currencyCode: 'JPY',
      );
}

class _NoopAnalytics extends Fake implements AnalyticsService {
  @override
  Future<void> logPaywallView({
    required String source,
    required bool productLoaded,
  }) async {}

  @override
  Future<void> logTapPaywall({required String source}) async {}
}
