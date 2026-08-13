import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../providers/pronunciation_quota_provider.dart';
import '../screens/paywall_screen.dart';

/// プレミアム体験の開放を伝えるダイアログ。
///
/// 体験を後から配った既存ユーザー向け。黙って配ると、増えたことにも減ったことにも
/// 気づかないまま期間が終わり、終了ダイアログで初めて「失った」と知らされる。
/// それでは価値を体験したことにならないので、開放の瞬間に何が使えるかを伝える。
///
/// ここでは課金を勧めない。今もらったばかりの人に登録を促すのは筋が悪く、
/// 訴求は体験が終わる [PremiumTrialEndedDialog] の仕事にする。
class PremiumTrialStartedDialog extends StatelessWidget {
  const PremiumTrialStartedDialog({super.key, required this.days});

  /// 体験できる残り日数（期限から算出）。
  final int days;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);

    return AlertDialog(
      icon: Icon(
        Icons.card_giftcard_rounded,
        color: theme.colorScheme.primary,
        size: 32,
      ),
      iconPadding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
      title: Text(l10n.trialStartedTitle(days)),
      titlePadding: const EdgeInsets.symmetric(horizontal: 24),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.trialStartedBody),
          const SizedBox(height: 12),
          // 終了ダイアログと同じ項目・同じ並びにする。開放と終了で見せるものが
          // 違うと、失ったものが何なのか結び付かない。
          _Unlocked(
            icon: Icons.bolt,
            text: l10n.trialStartedChangeQuota(
              premiumDailySentences,
              freeDailySentences,
            ),
          ),
          const SizedBox(height: 6),
          _Unlocked(
            icon: Icons.mic_none,
            text: l10n.trialStartedChangePronunciation(
              freeDailyPronunciationChecks,
            ),
          ),
          const SizedBox(height: 6),
          _Unlocked(
            icon: Icons.category_outlined,
            text: l10n.trialStartedChangeTopic,
          ),
        ],
      ),
      scrollable: true,
      contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
      actionsPadding: const EdgeInsets.fromLTRB(24, 4, 24, 20),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.trialStartedStart),
        ),
      ],
    );
  }
}

class _Unlocked extends StatelessWidget {
  const _Unlocked({required this.icon, required this.text});

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

/// 体験開放ダイアログを表示する。
Future<void> showPremiumTrialStartedDialog(
  BuildContext context, {
  required int days,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => PremiumTrialStartedDialog(days: days),
  );
}
