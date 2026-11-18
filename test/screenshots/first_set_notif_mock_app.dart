// =============================================================================
// first_set_notif_mock_app.dart
// 初回のまとめクイズのあと「次のセットへ」→ ペイウォール → 閉じる →
// 次のセットを読み込みながら通知の案内、の流れを Firebase なしで確かめるモック。
// 本番の順序は learning_screen.dart の summaryQuiz の onNextSentence。
// 読み込みは数秒待つだけの見せかけ。
//
//   flutter run -t test/screenshots/first_set_notif_mock_app.dart
// =============================================================================

import 'dart:async';

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
import 'package:thai_memo/presentation/widgets/notification_coach_dialog.dart';
import 'package:thai_memo/services/analytics_service.dart';

const _lang = String.fromEnvironment('LANG', defaultValue: 'ja');

void main() {
  // テーマ（google_fonts）を作る前に binding を用意する。
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    ProviderScope(
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
        locale: const Locale(_lang),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        theme: buildAppLightTheme(ThaiFont.sarabun),
        home: const _Home(),
      ),
    ),
  );
}

class _Home extends StatefulWidget {
  const _Home();

  @override
  State<_Home> createState() => _HomeState();
}

class _HomeState extends State<_Home> {
  bool _premium = false;
  bool _loading = false;
  bool _done = false;

  Future<void> _nextSet() async {
    if (_loading) return;
    final l10n = L10n.of(context);
    if (!_premium) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) => PaywallScreen(
            source: 'mock',
            lead: l10n.paywallLeadFirstSet,
          ),
        ),
      );
      if (!mounted) return;
    }
    // 本番と同じく、読み込みと案内を同時に走らせる。
    setState(() {
      _loading = true;
      _done = false;
    });
    final loading = Future<void>.delayed(const Duration(seconds: 3)).then((_) {
      if (mounted) setState(() => _loading = false);
    });
    final accepted = await showNotificationCoachDialog(context);
    await loading;
    if (!mounted) return;
    setState(() => _done = true);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(accepted ? '「通知をオンにする」→ ここでOSの許可ダイアログ' : '「今はしない」')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.learnSummaryQuizTitle)),
      body: Center(
        child: _loading
            ? const CircularProgressIndicator()
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_done) const Text('次のセット（見せかけ）'),
                  const SizedBox(height: 24),
                  SwitchListTile(
                    title: const Text('プレミアム（ペイウォールを飛ばす）'),
                    value: _premium,
                    onChanged: (v) => setState(() => _premium = v),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _nextSet,
                    icon: const Icon(Icons.arrow_forward),
                    label: Text(l10n.learnNextSet),
                  ),
                ],
              ),
      ),
    );
  }
}

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
