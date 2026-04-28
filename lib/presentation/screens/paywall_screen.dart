/// paywall_screen.dart — プレミアムプラン購入画面（ペイウォール）
///
/// Free ユーザーに対してプレミアムプランの特典を提示し、購入・復元を促す画面。
/// モーダルボトムシートとして表示され、以下の要素で構成される:
///
/// 1. Free / Premium の機能比較テーブル（例文生成回数、クイズ、テーマ数など）
/// 2. 月額価格の表示（ストアから動的に取得した実際の価格）
/// 3. 「プレミアムに登録」ボタン → OS ネイティブの決済シートを起動
/// 4. 「購入を復元」ボタン → 機種変更・再インストール時の復元用
///
/// 【表示トリガー】
/// - 設定画面のアップグレードバナータップ
/// - ホーム画面で例文生成のクォータ超過時
/// - クイズ画面でクイズ生成のレート制限時
///
/// 【関連ファイル】
/// - subscription_provider.dart: 購入状態管理（SubscriptionController）
/// - purchase_service.dart: ストア決済処理
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config/app_config.dart';
import '../providers/analytics_provider.dart';
import '../providers/subscription_provider.dart';

/// プレミアムプランの説明を表示するモーダルボトムシート
class PaywallBottomSheet extends ConsumerWidget {
  static const routeName = 'paywall';

  const PaywallBottomSheet({
    super.key,
    required this.source,
  });

  final String source;

  /// ボトムシートを表示する
  static Future<void> show(
    BuildContext context, {
    String source = 'unknown',
  }) async {
    final container = ProviderScope.containerOf(context, listen: false);
    final analytics = container.read(analyticsServiceProvider);
    unawaited(
      container
          .read(subscriptionControllerProvider.notifier)
          .ensureStoreReady()
          .catchError((Object error, StackTrace stackTrace) {
        debugPrint('Failed to warm up store: $error');
      }),
    );
    // 呼び出し元の source を失わないよう、表示前にイベントを確定させる。
    unawaited(analytics.logTapPaywall(source: source));
    unawaited(
      analytics.logScreenView(
        screenName: routeName,
        screenClass: 'PaywallBottomSheet',
      ),
    );

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => PaywallBottomSheet(source: source),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.72,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                controller: scrollController,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // ドラッグハンドル
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: colorScheme.onSurfaceVariant
                                .withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      // タイトル
                      Text(
                        'プレミアムプラン',
                        style:
                            Theme.of(context).textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: colorScheme.primary,
                                ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '100語の先へ。多様なタイ語例文を',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      _buildMainBenefits(context),
                    ],
                  ),
                ),
              ),
            ),
            _buildPurchaseBar(context, ref),
          ],
        );
      },
    );
  }

  /// 固定購入バー: 価格表示・購入ボタン・復元ボタン・エラー表示
  ///
  /// 既にプレミアムの場合は「加入中」メッセージのみ表示。
  /// product が null（ストアから商品情報を取得できていない）の場合、購入ボタンは無効化される。
  Widget _buildPurchaseBar(BuildContext context, WidgetRef ref) {
    final subState = ref.watch(subscriptionControllerProvider);
    final colorScheme = Theme.of(context).colorScheme;
    final bottomSafeArea = MediaQuery.paddingOf(context).bottom;

    if (subState.isPremium) {
      return Container(
        width: double.infinity,
        padding: EdgeInsets.fromLTRB(24, 14, 24, 14 + bottomSafeArea),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          border: Border(
            top: BorderSide(color: colorScheme.outlineVariant),
          ),
        ),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            'プレミアムプランに加入中です',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.bold,
                ),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    Widget legalLink({
      required String label,
      required VoidCallback? onPressed,
    }) {
      return TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          minimumSize: Size.zero,
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                decoration: TextDecoration.underline,
              ),
        ),
      );
    }

    Widget separator() {
      return Text(
        '|',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurface.withValues(alpha: 0.4),
            ),
      );
    }

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(24, 10, 24, 10 + bottomSafeArea),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          top: BorderSide(color: colorScheme.outlineVariant),
        ),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 価格表示
          if (subState.product != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                _formatPrice(
                    subState.product!.rawPrice, subState.product!.currencyCode),
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                textAlign: TextAlign.center,
              ),
            ),
          // エラーメッセージ
          if (subState.errorMessage != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                subState.errorMessage!,
                style: TextStyle(color: colorScheme.error),
                textAlign: TextAlign.center,
              ),
            ),
          // 購入ボタン
          FilledButton(
            onPressed: subState.isLoading || subState.product == null
                ? null
                : () {
                    unawaited(
                      ref.read(analyticsServiceProvider).logSubscribe(
                            source: source,
                          ),
                    );
                    ref
                        .read(subscriptionControllerProvider.notifier)
                        .purchase();
                  },
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              minimumSize: const Size(double.infinity, 0),
            ),
            child: subState.isLoading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text(
                    'プレミアムに加入',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
          ),
          // 自動更新サブスクリプション開示文（iOS: Apple ガイドライン 3.1.2 準拠）
          if (defaultTargetPlatform == TargetPlatform.iOS) ...[
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              child: Text(
                'サブスクリプションは自動更新です。期間終了24時間前までにキャンセルできます。'
                '更新料金は終了24時間以内に請求され、管理・キャンセルはApp Storeのアカウント設定から行えます。',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurface.withValues(alpha: 0.6),
                      height: 1.25,
                    ),
                textAlign: TextAlign.left,
              ),
            ),
          ],
          const SizedBox(height: 2),
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 2,
            children: [
              legalLink(
                label: '購入を復元',
                onPressed: subState.isLoading
                    ? null
                    : () => ref
                        .read(subscriptionControllerProvider.notifier)
                        .restore(),
              ),
              separator(),
              legalLink(
                label: '利用規約',
                onPressed: () =>
                    launchUrl(Uri.parse(AppConfig.termsOfServiceUrl)),
              ),
              separator(),
              legalLink(
                label: 'プライバシーポリシー',
                onPressed: () =>
                    launchUrl(Uri.parse(AppConfig.privacyPolicyUrl)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatPrice(double rawPrice, String currencyCode) {
    if (currencyCode == 'JPY') {
      return '¥${rawPrice.toInt()} / 月';
    }
    final formatted = rawPrice.toStringAsFixed(2);
    return '$currencyCode $formatted / 月';
  }

  Widget _buildMainBenefits(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    Widget benefitRow({
      required IconData icon,
      required String title,
      required String freeText,
      required String premiumText,
    }) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: colorScheme.primary, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 4),
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: freeText),
                      const TextSpan(text: ' → '),
                      TextSpan(
                        text: premiumText,
                        style: TextStyle(
                          color: colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          benefitRow(
            icon: Icons.school,
            title: '学べる単語',
            freeText: '無料は100語まで',
            premiumText: '100語の先まで',
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Divider(height: 1, color: colorScheme.outlineVariant),
          ),
          benefitRow(
            icon: Icons.bolt,
            title: '1日の利用回数',
            freeText: '例文2回/日',
            premiumText: '各5回/日',
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Divider(height: 1, color: colorScheme.outlineVariant),
          ),
          benefitRow(
            icon: Icons.auto_awesome,
            title: 'より多様な例文',
            freeText: '基本テーマ中心',
            premiumText: '仕事・恋愛...etc',
          ),
        ],
      ),
    );
  }
}
