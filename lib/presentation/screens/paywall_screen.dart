/// paywall_screen.dart — プレミアムプラン購入画面（ペイウォール）
///
/// Free ユーザーに対してプレミアムプランの特典を提示し、購入・復元を促す画面。
/// モーダルボトムシートとして表示され、以下の要素で構成される:
///
/// 1. Free / Premium の機能比較テーブル（例文生成回数、クイズ、トピック数など）
/// 2. 月額価格の表示（ストアから動的に取得した実際の価格）
/// 3. 「プレミアムに登録」ボタン → OS ネイティブの決済シートを起動
/// 4. 「購入を復元」ボタン → 機種変更・再インストール時の復元用
/// 5. [DEV] ティア切替ボタン → dev環境でのみ表示、ストア接続なしでテスト可能
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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../providers/subscription_provider.dart';

/// プレミアムプランの説明を表示するモーダルボトムシート
class PaywallBottomSheet extends ConsumerWidget {
  const PaywallBottomSheet({super.key});

  /// ボトムシートを表示する
  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => const PaywallBottomSheet(),
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
                  'より豊かなタイ語学習体験を',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                // 比較テーブル
                _buildComparisonTable(context),
                const SizedBox(height: 32),
                // 購入ボタン
                _buildPurchaseSection(context, ref),
                // dev環境のみ: ティアトグルボタン
                if (AppConfig.isDev) ...[
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () async {
                      await ref
                          .read(subscriptionControllerProvider.notifier)
                          .toggleTier();
                      if (context.mounted) Navigator.pop(context);
                    },
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: const Text(
                      '[DEV] ティアを切り替え',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
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
              '${subState.product!.price} / 月',
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
              : () =>
                  ref.read(subscriptionControllerProvider.notifier).purchase(),
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
      ],
    );
  }

  Widget _buildComparisonTable(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    const features = [
      ('例文', '1日1回', '1日5回'),
      ('クイズ', '1日1回', '1日10回'),
      ('トピック', '4種', '16種'),
      ('文体', '2種', '5種'),
      ('その他の設定', '×', '○'),
      ('広告', 'あり', 'なし'),
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
                  flex: 2,
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
                  flex: 2,
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
            final feature = entry.value;
            final isLast = i == features.length - 1;
            final isPremiumBetter = feature.$3 != feature.$2;

            return Container(
              decoration: BoxDecoration(
                border: isLast
                    ? null
                    : Border(
                        bottom: BorderSide(color: colorScheme.outlineVariant),
                      ),
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Text(
                        feature.$1,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      feature.$2,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      feature.$3,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: isPremiumBetter
                                ? colorScheme.primary
                                : colorScheme.onSurface,
                            fontWeight: isPremiumBetter
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                      textAlign: TextAlign.center,
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
