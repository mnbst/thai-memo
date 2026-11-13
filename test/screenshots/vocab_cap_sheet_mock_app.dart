// =============================================================================
// vocab_cap_sheet_mock_app.dart
// free が語彙スコア100に届いたとき、まとめクイズの結果の上に出す課金シート
// （lib/presentation/widgets/vocab_cap_sheet.dart）を Firebase なしで出す。
//
//   flutter run -t test/screenshots/vocab_cap_sheet_mock_app.dart
//
// 上の切替で ja / en / ko を選び、「シートを出す」で何度でも出し直せる。
// 「プレミアムで続ける」でペイウォール（商品は差し込み、購入はしない）へ進む。
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
import 'package:thai_memo/presentation/widgets/vocab_cap_sheet.dart';
import 'package:thai_memo/services/analytics_service.dart';

void main() => runApp(const _MockApp());

class _MockApp extends StatelessWidget {
  const _MockApp();

  @override
  Widget build(BuildContext context) {
    // ペイウォールが Firestore・ストアに触らないよう差し替える
    // （test/screenshots/paywall_review_screenshot.dart と同じ）。
    return ProviderScope(
      overrides: [
        analyticsServiceProvider.overrideWithValue(_NoopAnalytics()),
        userDocSnapshotProvider.overrideWith(
          (ref) => Stream.value(
              const UserDocSnapshot(data: null, isFromCache: false)),
        ),
        subscriptionControllerProvider.overrideWith((ref) => _StubController()),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: const Locale('ja'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        theme: buildAppLightTheme(ThaiFont.sarabun),
        home: const _MockHome(),
      ),
    );
  }
}

class _MockHome extends StatefulWidget {
  const _MockHome();

  @override
  State<_MockHome> createState() => _MockHomeState();
}

class _MockHomeState extends State<_MockHome> {
  String _lang = 'ja';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _show());
  }

  // 本番の VocabCapSheet.show と同じ出し方。言語だけ切り替えられるようにする。
  void _show() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => Localizations.override(
        context: context,
        locale: Locale(_lang),
        child: FractionallySizedBox(
          heightFactor: 0.94,
          child: VocabCapSheet(onContinue: _openPaywall),
        ),
      ),
    );
  }

  void _openPaywall() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Localizations.override(
          context: context,
          locale: Locale(_lang),
          child: const PaywallScreen(source: 'vocab_cap_sheet'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('まとめクイズ 結果')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'ja', label: Text('ja')),
                ButtonSegment(value: 'en', label: Text('en')),
                ButtonSegment(value: 'ko', label: Text('ko')),
              ],
              selected: {_lang},
              onSelectionChanged: (value) {
                setState(() => _lang = value.first);
                _show();
              },
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _show,
              child: const Text('シートを出す'),
            ),
          ],
        ),
      ),
    );
  }
}

/// ストアから商品を引けた状態の SubscriptionController（購入はしない）。
class _StubController extends SubscriptionController {
  _StubController()
      : super(
          analytics: _NoopAnalytics(),
          l10n: () => lookupL10n(const Locale('ja')),
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
