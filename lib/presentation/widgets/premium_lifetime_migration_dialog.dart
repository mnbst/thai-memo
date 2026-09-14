/// premium_lifetime_migration_dialog.dart
///
/// 月額プランの既存プレミアムユーザーに、買い切りプランの新設と無料移行を知らせる。
///
/// 伝える順は「継続のお礼 → 新設 → いまなら無料 → 追加料金なし → 解約は本人」。
/// 追加の支払いは発生しない（いま払っている人をそのまま買い切りへ移す）。
/// ただし App Store の自動更新はこちらから止められないので、移行しても
/// 解約しなければ請求は続く。「追加のお支払いはありません」を成り立たせる
/// ために、自動更新の停止が要ることを必ず同じ画面で伝える。
library;

import 'package:flutter/material.dart';

import '../../core/config/app_config.dart';
import '../../l10n/app_localizations.dart';
import '../../core/theme/app_colors.dart';

class PremiumLifetimeMigrationDialog extends StatelessWidget {
  const PremiumLifetimeMigrationDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return AlertDialog(
      icon: Icon(
        Icons.workspace_premium_outlined,
        color: theme.colorScheme.primary,
        size: 32,
      ),
      iconPadding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
      title: Text(l10n.lifetimeMigrationTitle),
      titlePadding: const EdgeInsets.symmetric(horizontal: 24),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.lifetimeMigrationBody),
          const SizedBox(height: 12),
          // 追加料金が無いことは一番の要点なので、本文から切り出して置く。
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.gold.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(AppConfig.buttonBorderRadius),
              border: Border.all(color: AppColors.gold.withValues(alpha: 0.42)),
            ),
            child: Text(
              l10n.lifetimeMigrationNoCharge,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF7A5E22),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 12),
          // ここを落とすと「追加のお支払いはありません」が嘘になる。
          Text(
            l10n.lifetimeMigrationCancelNote,
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurface.withValues(alpha: 0.7),
              height: 1.3,
            ),
          ),
        ],
      ),
      scrollable: true,
      contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
      actionsPadding: const EdgeInsets.fromLTRB(24, 4, 24, 20),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(l10n.lifetimeMigrationConfirm),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(l10n.lifetimeMigrationLater),
        ),
      ],
    );
  }
}

/// 移行の案内を出す。戻り値は「移行する」を押したかどうか。
Future<bool> showPremiumLifetimeMigrationDialog(BuildContext context) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => const PremiumLifetimeMigrationDialog(),
  );
  return result ?? false;
}

/// 案内 → 実行 → 完了（または失敗）まで通す。
///
/// [migrate] は実際の移行処理。dev のプレビューでは待つだけの偽物を渡す。
/// 実行中は閉じられないローディングを出す。途中で閉じられると、移行できた
/// のか分からないまま案内だけ消える。
Future<void> showLifetimeMigrationFlow(
  BuildContext context, {
  required Future<void> Function() migrate,
}) async {
  final moved = await showPremiumLifetimeMigrationDialog(context);
  if (!moved || !context.mounted) return;

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => const _MigrationProgressDialog(),
  );

  Object? error;
  try {
    await migrate();
  } catch (e) {
    error = e;
  }
  if (!context.mounted) return;
  Navigator.of(context, rootNavigator: true).pop(); // ローディングを閉じる

  final l10n = L10n.of(context);
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      icon: Icon(
        error == null ? Icons.check_circle_outline : Icons.error_outline,
        size: 32,
        color: error == null
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.error,
      ),
      title: Text(
        error == null
            ? l10n.lifetimeMigrationDoneTitle
            : l10n.lifetimeMigrationFailedTitle,
      ),
      content: Text(
        error == null
            ? l10n.lifetimeMigrationDoneBody
            : l10n.lifetimeMigrationFailedBody,
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.commonClose),
        ),
      ],
    ),
  );
}

/// 移行中のローディング。閉じる手段は出さない。
class _MigrationProgressDialog extends StatelessWidget {
  const _MigrationProgressDialog();

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(
          children: [
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 16),
            Flexible(child: Text(L10n.of(context).lifetimeMigrationProgress)),
          ],
        ),
      ),
    );
  }
}
