import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../providers/vocab_stats_provider.dart';
import '../screens/paywall_screen.dart';
import 'vocab_level.dart';

/// プレミアム体験トライアルの終了を伝え、そのまま登録へ誘導するダイアログ。
///
/// 「使えていたものが使えなくなった」直後が最も伝わるので、体験終了を検知した
/// 最初の起動で一度だけ出す。ペイウォールは原則タップ起点だが、この瞬間だけは
/// 割り込みで知らせる価値がある（黙って機能が減ると不具合に見える）。
class PremiumTrialEndedDialog extends ConsumerWidget {
  const PremiumTrialEndedDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);

    // 語彙スコアの行は、実際に切り下がる人にだけ出す。上限に届いていない
    // 人には落差が無く、行だけ増えても意味が読めない。判定には free 上限で
    // 潰れない測定値（vocab_test_vocab）を使う。
    final stats = ref.watch(vocabStatsProvider).valueOrNull;
    final measured = stats == null
        ? 0
        : (stats.testedVocab > 0 ? stats.testedVocab : stats.estimatedVocab);

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
          // 実数の増減が出ない項目（テーマ選択・例文の質）は載せない。
          _ChangeTable(
            changes: [
              _Change(
                icon: Icons.bolt,
                label: l10n.trialEndedChangeQuotaLabel,
                premium:
                    l10n.trialEndedChangeQuotaPremium(premiumDailySentences),
                free: l10n.trialEndedChangeQuotaFree(freeDailySentences),
              ),
              if (measured > freeVocabScoreLimit)
                _Change(
                  icon: Icons.straighten,
                  label: l10n.trialEndedChangeVocabLabel,
                  premium: l10n.trialEndedChangeVocabPremium,
                  free: l10n.trialEndedChangeVocabFree(freeVocabScoreLimit),
                ),
            ],
          ),
        ],
      ),
      scrollable: true,
      contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
      actionsPadding: const EdgeInsets.fromLTRB(24, 4, 24, 20),
      // 縦積みになるので、勧めたい方（プレミアム）を上に置く。
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(l10n.trialEndedKeepPremium),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(l10n.trialEndedKeepFree),
        ),
      ],
    );
  }
}

/// 変化する1項目。
class _Change {
  const _Change({
    required this.icon,
    required this.label,
    required this.premium,
    required this.free,
  });

  final IconData icon;
  final String label;

  /// 体験中に使えていた値。
  final String premium;

  /// 今日から戻る値。
  final String free;
}

/// 変化を表で並べる。
///
/// 行ごとに Row で組むと、項目名の長さの違い（例文／発音チェック）がそのまま
/// ずれになって、矢印も値も揃わない。列幅を共有する表にして縦を通す。
class _ChangeTable extends StatelessWidget {
  const _ChangeTable({required this.changes});

  final List<_Change> changes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final base = theme.textTheme.bodyMedium?.copyWith(
      color: cs.onSurfaceVariant,
    );

    return Table(
      // 値の3列は数字なので縮めない。余りを吸うのはラベル列だけにする
      // （全列 Intrinsic にすると、幅が足りないときにラベルが押し出される）。
      columnWidths: const {
        0: FlexColumnWidth(),
        1: IntrinsicColumnWidth(),
        2: IntrinsicColumnWidth(),
        3: IntrinsicColumnWidth(),
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        for (final change in changes)
          TableRow(
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 12, top: 3, bottom: 3),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(change.icon, size: 16, color: cs.primary),
                    const SizedBox(width: 6),
                    // 長いラベル（他言語・大きい文字サイズ）は折り返させる。
                    Flexible(child: Text(change.label, style: base)),
                  ],
                ),
              ),
              // 色を付けるのは失う側（体験中の値）だけ。無料の値まで同じ強調に
              // すると、どちらがどちらか読み分けられない。
              Text(
                change.premium,
                textAlign: TextAlign.right,
                style: base?.copyWith(
                  color: cs.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text('→', style: base),
              ),
              Text(change.free, style: base),
            ],
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
