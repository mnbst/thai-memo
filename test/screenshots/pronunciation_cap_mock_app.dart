// =============================================================================
// pronunciation_cap_mock_app.dart
// free が発音採点を1日10回使い切ったときの、発音練習シートの見た目の案。
// 本番コードには触れず、シートの外形だけを真似て Firebase なしで出す。
//
//   flutter run -t test/screenshots/pronunciation_cap_mock_app.dart
//
// 上の切替で「残り3回」「上限到達」を見比べる。ボタンでペイウォールへ進む。
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:thai_memo/core/theme/app_colors.dart';
import 'package:thai_memo/core/theme/app_theme.dart';
import 'package:thai_memo/l10n/app_localizations.dart';
import 'package:thai_memo/presentation/providers/analytics_provider.dart';
import 'package:thai_memo/presentation/providers/remaining_quota_provider.dart';
import 'package:thai_memo/presentation/providers/settings_provider.dart';
import 'package:thai_memo/presentation/providers/subscription_provider.dart';
import 'package:thai_memo/presentation/screens/paywall_screen.dart';
import 'package:thai_memo/services/analytics_service.dart';

const _cap = 10;

void main() => runApp(const _MockApp());

class _MockApp extends StatelessWidget {
  const _MockApp();

  @override
  Widget build(BuildContext context) {
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
  int _used = _cap;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _show());
  }

  void _show() {
    Navigator.of(context).popUntil((r) => r.isFirst);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      enableDrag: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _SheetMock(used: _used, onUpgrade: _openPaywall),
    );
  }

  void _openPaywall() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const PaywallScreen(source: 'pronunciation_cap'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('発音練習 上限モック')),
      body: Padding(
        padding: const EdgeInsets.only(top: 24),
        child: Align(
          alignment: Alignment.topCenter,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 7, label: Text('残り3回')),
                  ButtonSegment(value: _cap, label: Text('上限到達')),
                ],
                selected: {_used},
                onSelectionChanged: (v) {
                  setState(() => _used = v.first);
                  _show();
                },
              ),
              const SizedBox(height: 12),
              FilledButton(onPressed: _show, child: const Text('シートを出す')),
            ],
          ),
        ),
      ),
    );
  }
}

/// pronunciation_sheet.dart の _PronunciationSheet の外形を真似たもの。
class _SheetMock extends StatelessWidget {
  const _SheetMock({required this.used, required this.onUpgrade});

  final int used;
  final VoidCallback onUpgrade;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final reached = used >= _cap;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('วันนี้อากาศดีมาก', style: textTheme.titleMedium),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            Text(
              'wan-níi aa-kàat dii mâak',
              style: textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(height: 12),
            // お手本の再生（SentenceAudioPlayer）の代わり。上限後も聞ける。
            OutlinedButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.volume_up),
              label: const Text('お手本を聞く'),
            ),
            const SizedBox(height: 12),
            if (reached)
              _CapCard(onUpgrade: onUpgrade)
            else ...[
              _RecordButtonMock(),
              const SizedBox(height: 6),
              Center(
                child: Text(
                  '今日の採点 あと${_cap - used}回',
                  style: textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RecordButtonMock extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: scheme.primary,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.mic, size: 18, color: scheme.onPrimary),
          const SizedBox(width: 8),
          Text(
            '押しながら話す',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onPrimary,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }
}

/// 録音ボタンの位置に差し替える上限カード。
class _CapCard extends StatelessWidget {
  const _CapCard({required this.onUpgrade});

  final VoidCallback onUpgrade;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      decoration: BoxDecoration(
        color: AppColors.gold.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.45)),
      ),
      child: Column(
        children: [
          const Icon(Icons.mic_off_outlined, color: AppColors.gold, size: 28),
          const SizedBox(height: 6),
          Text(
            '今日の発音採点は$_cap回まで',
            textAlign: TextAlign.center,
            style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            '明日また$_cap回できます。\nプレミアムなら回数は無制限です。',
            textAlign: TextAlign.center,
            style:
                textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.gold,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: onUpgrade,
              child: const Text(
                'プレミアムで続ける',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('閉じる'),
          ),
        ],
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
