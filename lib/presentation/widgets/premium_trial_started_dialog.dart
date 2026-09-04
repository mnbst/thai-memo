import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../screens/paywall_screen.dart';

/// プレミアム体験の開放を伝えるダイアログ。
///
/// 体験を後から配った既存ユーザー向け。黙って配ると、増えたことにも減ったことにも
/// 気づかないまま期間が終わり、終了ダイアログで初めて「失った」と知らされる。
/// それでは価値を体験したことにならないので、開放の瞬間に何が使えるかを伝える。
///
/// 語彙測定を終えたオンボーディング末尾でも出す（[offerPaywall] = true）。
/// 一括配布のときは課金を勧めないが、こちらは「これから何が使えるのか」を
/// 知った直後なので、プランへ進める導線を1本だけ足す。訴求の本体は
/// 体験が終わる [PremiumTrialEndedDialog] の仕事のままにする。
class PremiumTrialStartedDialog extends StatelessWidget {
  const PremiumTrialStartedDialog({
    super.key,
    required this.days,
    this.offerPaywall = false,
  });

  /// 体験できる残り日数（期限から算出）。
  final int days;

  /// ペイウォールへの導線を出すか。出したときは true を返して閉じる。
  final bool offerPaywall;

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
          _Unlocked(
            icon: Icons.bolt,
            label: l10n.trialStartedChangeQuotaLabel,
            text: l10n.trialStartedChangeQuota(premiumDailySentences),
          ),
          const SizedBox(height: 6),
          _Unlocked(
            icon: Icons.category_outlined,
            label: l10n.trialStartedChangeTopicLabel,
            text: l10n.trialStartedChangeTopic,
          ),
        ],
      ),
      scrollable: true,
      contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
      actionsPadding: const EdgeInsets.fromLTRB(24, 4, 24, 20),
      actions: [
        if (offerPaywall)
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.trialStartedSeePlans),
          ),
        FilledButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(l10n.trialStartedStart),
        ),
      ],
    );
  }
}

class _Unlocked extends StatelessWidget {
  const _Unlocked({required this.icon, required this.label, required this.text});

  final IconData icon;

  /// 機能名。行をまたいで左端を揃えたいので、説明とは別のカラムに置く。
  final String label;
  final String text;

  /// 機能名カラムの幅。行ごとに幅が変わると説明の頭が揃わない。
  static const double _labelWidth = 92;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final style = Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: cs.primary,
          fontWeight: FontWeight.w600,
        );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: cs.primary),
        const SizedBox(width: 6),
        SizedBox(
          width: _labelWidth,
          child: Text(label, style: style),
        ),
        Expanded(child: Text(text, style: style)),
      ],
    );
  }
}

/// 体験開放ダイアログを表示する。戻り値はペイウォールを開くかどうか
/// （[offerPaywall] が false のときは常に false）。
Future<bool> showPremiumTrialStartedDialog(
  BuildContext context, {
  required int days,
  bool offerPaywall = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => PremiumTrialStartedDialog(
      days: days,
      offerPaywall: offerPaywall,
    ),
  );
  return result ?? false;
}
