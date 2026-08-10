import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../providers/pronunciation_quota_provider.dart';
import '../screens/paywall_screen.dart';

/// プレミアム体験トライアルの終了を伝え、そのまま登録へ誘導するダイアログ。
///
/// 「使えていたものが使えなくなった」直後が最も伝わるので、体験終了を検知した
/// 最初の起動で一度だけ出す。ペイウォールは原則タップ起点だが、この瞬間だけは
/// 割り込みで知らせる価値がある（黙って機能が減ると不具合に見える）。
class PremiumTrialEndedDialog extends StatelessWidget {
  const PremiumTrialEndedDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);

    return AlertDialog(
      icon: Icon(
        Icons.hourglass_bottom_rounded,
        color: theme.colorScheme.primary,
        size: 32,
      ),
      iconPadding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
      title: Text(l10n.trialEndedTitle),
      titlePadding: const EdgeInsets.symmetric(horizontal: 24),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.trialEndedBody),
          const SizedBox(height: 12),
          // ここは「いま何が変わったか」だけを数字で出す。特典の全一覧は
          // ペイウォールの仕事で、両方に並べるとペイウォールが繰り返しになる。
          // 実数の増減が出ない項目（テーマ選択・例文の質・語彙上限）は載せない。
          _Change(
            icon: Icons.bolt,
            text: l10n.trialEndedChangeQuota(
              premiumDailySentences,
              freeDailySentences,
            ),
          ),
          const SizedBox(height: 6),
          _Change(
            icon: Icons.mic_none,
            text: l10n.trialEndedChangePronunciation(
              freeDailyPronunciationChecks,
            ),
          ),
        ],
      ),
      scrollable: true,
      contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
      actionsPadding: const EdgeInsets.fromLTRB(24, 4, 24, 20),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(l10n.trialEndedLater),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(l10n.trialEndedSeePremium),
        ),
      ],
    );
  }
}

class _Change extends StatelessWidget {
  const _Change({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: cs.primary),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            // 初回ガイドの体験期間と同じ強調に揃える。
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: cs.primary,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ),
      ],
    );
  }
}

/// 体験終了ダイアログを表示する。戻り値はペイウォールを開くかどうか。
Future<bool> showPremiumTrialEndedDialog(BuildContext context) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => const PremiumTrialEndedDialog(),
  );
  return result ?? false;
}
