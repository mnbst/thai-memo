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
          .ensureStoreReady(),
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
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return SingleChildScrollView(
          controller: scrollController,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ドラッグハンドル
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color:
                          colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                // タイトル
                Text(
                  'プレミアムプラン',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colorScheme.primary,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  '仕事も恋愛も、タイ語で話せるように',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                // 比較テーブル
                _buildComparisonTable(context),
                const SizedBox(height: 20),
                // テーマ一覧
                _buildTopicSection(context),
                const SizedBox(height: 32),
                // 購入ボタン
                _buildPurchaseSection(context, ref),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 購入セクション: 価格表示・購入ボタン・復元ボタン・エラー表示
  ///
  /// 既にプレミアムの場合は「加入中」メッセージのみ表示。
  /// product が null（ストアから商品情報を取得できていない）の場合、購入ボタンは無効化される。
  Widget _buildPurchaseSection(BuildContext context, WidgetRef ref) {
    final subState = ref.watch(subscriptionControllerProvider);
    final colorScheme = Theme.of(context).colorScheme;

    if (subState.isPremium) {
      return Container(
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
      );
    }

    return Column(
      children: [
        // 価格表示
        if (subState.product != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              _formatPrice(
                  subState.product!.rawPrice, subState.product!.currencyCode),
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
              textAlign: TextAlign.center,
            ),
          ),
        // エラーメッセージ
        if (subState.errorMessage != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
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
                  ref.read(subscriptionControllerProvider.notifier).purchase();
                },
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            minimumSize: const Size(double.infinity, 0),
          ),
          child: subState.isLoading
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text(
                  'プレミアムに登録',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
        ),
        const SizedBox(height: 8),
        // 復元ボタン
        TextButton(
          onPressed: subState.isLoading
              ? null
              : () =>
                  ref.read(subscriptionControllerProvider.notifier).restore(),
          child: const Text('購入を復元'),
        ),
        // 自動更新サブスクリプション開示文（iOS: Apple ガイドライン 3.1.2 準拠）
        if (defaultTargetPlatform == TargetPlatform.iOS) ...[
          const SizedBox(height: 12),
          Text(
            'サブスクリプションは、現在の期間終了の24時間前までにキャンセルしない限り自動更新されます。'
            '更新料金は期間終了の24時間以内に請求されます。'
            'App Storeのアカウント設定からサブスクリプションの管理・キャンセルができます。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.6),
                ),
            textAlign: TextAlign.left,
          ),
        ],
        // 利用規約・プライバシーポリシーリンク（Apple ガイドライン 3.1.2 準拠）
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextButton(
              onPressed: () =>
                  launchUrl(Uri.parse(AppConfig.termsOfServiceUrl)),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                '利用規約',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      decoration: TextDecoration.underline,
                    ),
              ),
            ),
            Text(
              '|',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.4),
                  ),
            ),
            TextButton(
              onPressed: () => launchUrl(Uri.parse(AppConfig.privacyPolicyUrl)),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                'プライバシーポリシー',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      decoration: TextDecoration.underline,
                    ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  String _formatPrice(double rawPrice, String currencyCode) {
    if (currencyCode == 'JPY') {
      return '¥${rawPrice.toInt()} / 月';
    }
    final formatted = rawPrice.toStringAsFixed(2);
    return '$currencyCode $formatted / 月';
  }

  Widget _buildTopicSection(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    const freeTopics = ['あいさつ', '食べ物', '旅行', '買い物'];
    const premiumTopics = [
      '仕事',
      '恋愛',
      '家族',
      '交通',
      '健康',
      '天気',
      '趣味',
      '学校',
      '宗教・信仰',
      '伝統・祭り',
      '礼儀作法',
    ];

    Widget chipWrap(List<String> labels, Color bg, Color fg) => Wrap(
          spacing: 6,
          runSpacing: 6,
          children: labels
              .map((label) => Chip(
                    label: Text(label,
                        style: Theme.of(context)
                            .textTheme
                            .labelSmall
                            ?.copyWith(color: fg)),
                    backgroundColor: bg,
                    side: BorderSide.none,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ))
              .toList(),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('例文のテーマ',
            style: Theme.of(context)
                .textTheme
                .labelLarge
                ?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        chipWrap(freeTopics, colorScheme.surfaceContainerHighest,
            colorScheme.onSurfaceVariant),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(child: Divider(color: colorScheme.outlineVariant)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text('プレミアムで追加',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      )),
            ),
            Expanded(child: Divider(color: colorScheme.outlineVariant)),
          ],
        ),
        const SizedBox(height: 6),
        chipWrap(premiumTopics, colorScheme.primaryContainer,
            colorScheme.onPrimaryContainer),
      ],
    );
  }

  Widget _buildComparisonTable(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    // (機能名, 無料, プレミアム)
    const features = [
      ('例文生成 / クイズ', '最大2回/日', '最大10回/日'),
      ('学べる単語', '100語まで', '最大1万語'),
    ];

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          // ヘッダー行
          Container(
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                const Expanded(flex: 3, child: SizedBox()),
                Expanded(
                  flex: 3,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      '無料',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'プレミアム',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: colorScheme.primary,
                          ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // 機能行
          ...features.asMap().entries.map((entry) {
            final i = entry.key;
            final f = entry.value;
            final isLast = i == features.length - 1;

            return Container(
              decoration: BoxDecoration(
                border: isLast
                    ? null
                    : Border(
                        bottom: BorderSide(color: colorScheme.outlineVariant),
                      ),
                borderRadius: isLast
                    ? const BorderRadius.vertical(bottom: Radius.circular(12))
                    : null,
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      child: Text(f.$1,
                          style: Theme.of(context).textTheme.bodyMedium),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 12),
                      child: Text(
                        f.$2,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 12),
                      child: Text(
                        f.$3,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: colorScheme.primary,
                              fontWeight: FontWeight.bold,
                            ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
