import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/generation_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/constants/generation_labels.dart';
import '../../l10n/app_localizations.dart';
import '../providers/remaining_quota_provider.dart';
import '../providers/settings_provider.dart';
import '../screens/paywall_screen.dart';
import 'coach_mark_overlay.dart';

/// テーマ文字列から表示用の短いラベル（括弧前の名称）を返す。null は「おまかせ」。
String topicShortLabel(L10n l10n, String? topic) {
  if (topic == null) return l10n.settingsTopicRandom;
  return topicLabel(l10n, topic).name;
}

/// 次の例文のテーマを文脈付きで表示し、変更導線を提供する。課金導線として全ユーザーに表示。
/// Free: 「おまかせ」表示＋「テーマを選ぶ」でペイウォール / Premium・トライアル中: 「変更」で選択。
class NextSentenceTopicLabel extends ConsumerWidget {
  /// ペイウォール計測用のソース名。
  final String paywallSource;

  /// 学習タブの帯として出すか。false ならチップ（クイズ結果画面での従来表示）。
  ///
  /// 帯は例文カードのすぐ上に置き、「次はどのテーマが届くか」を
  /// 例文を読む前に見せる。中身の出し分け（Free はおまかせ＋ペイウォール）は
  /// チップと同じで、器だけが違う。
  final bool banner;

  const NextSentenceTopicLabel({
    super.key,
    this.paywallSource = 'next_topic',
    this.banner = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canSelect = ref.watch(effectivePremiumProvider);
    final currentTopic = ref.watch(generationParamsProvider)['topic'];
    final l10n = L10n.of(context);
    final label = canSelect
        ? topicShortLabel(l10n, currentTopic)
        : l10n.settingsTopicRandom;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final onTap = canSelect
        ? () {
            // ツアー中にスポットしたチップをタップしたらマークを閉じる。
            CoachMarkOverlay.dismiss();
            showTopicPicker(context, ref);
          }
        : () {
            CoachMarkOverlay.dismiss();
            PaywallBottomSheet.show(context, source: paywallSource);
          };

    if (banner) {
      return _buildBanner(context, l10n, label, canSelect, onTap);
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: ActionChip(
        onPressed: onTap,
        avatar: Icon(
          canSelect ? Icons.palette_outlined : Icons.lock,
          size: 18,
          color: cs.primary,
        ),
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.nextTopicPrefix,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
            Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (canSelect) ...[
              const SizedBox(width: 4),
              Icon(Icons.edit_outlined, size: 14, color: cs.onSurfaceVariant),
            ],
          ],
        ),
        shape: StadiumBorder(side: BorderSide(color: cs.outlineVariant)),
        backgroundColor: Colors.transparent,
      ),
    );
  }

  Widget _buildBanner(
    BuildContext context,
    L10n l10n,
    String label,
    bool canSelect,
    VoidCallback onTap,
  ) {
    final theme = Theme.of(context);
    return Material(
      color: AppColors.gold.withValues(alpha: 0.13),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          // 帯は「毎回押す場所」ではないので、例文より先に大きな面積を取らない
          // 高さに抑える。
          height: 36,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.gold.withValues(alpha: 0.32)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              if (!canSelect) ...[
                const Icon(Icons.lock, size: 15, color: Color(0xFF8A6C2E)),
                const SizedBox(width: 8),
              ],
              Text(
                l10n.nextTopicPrefix,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: const Color(0xFF8A6C2E),
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.06 * 12,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF6B5220),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Icon(
                Icons.chevron_right,
                size: 20,
                color: Color(0xFFA8823C),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// テーマ選択ダイアログを表示し、選択結果を設定に保存する。
/// Premium / トライアル中のユーザー向け。
Future<void> showTopicPicker(BuildContext context, WidgetRef ref) async {
  final currentTopic = ref.read(generationParamsProvider)['topic'];

  final selected = await showDialog<String?>(
    context: context,
    builder: (context) {
      final cs = Theme.of(context).colorScheme;
      return SimpleDialog(
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(L10n.of(context).topicPickerTitle),
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.pop(context),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, ''),
            child: ListTile(
              leading: Icon(
                Icons.shuffle,
                color: currentTopic == null ? cs.primary : null,
              ),
              title: Text(
                L10n.of(context).settingsTopicRandom,
                style: currentTopic == null
                    ? TextStyle(color: cs.primary, fontWeight: FontWeight.bold)
                    : null,
              ),
            ),
          ),
          ...GenerationConstants.topics.map((topic) {
            final isSelected = topic == currentTopic;
            final label = topicLabel(L10n.of(context), topic);
            final name = label.name;
            final sub = label.sub;

            return SimpleDialogOption(
              onPressed: () => Navigator.pop(context, topic),
              child: ListTile(
                leading: Icon(
                  Icons.circle,
                  size: 12,
                  color: isSelected ? cs.primary : Colors.transparent,
                ),
                title: Text(
                  name,
                  style: isSelected
                      ? TextStyle(
                          color: cs.primary, fontWeight: FontWeight.bold)
                      : null,
                ),
                subtitle: sub.isNotEmpty ? Text(sub) : null,
              ),
            );
          }),
        ],
      );
    },
  );

  if (selected != null) {
    await ref.read(settingsControllerProvider.notifier).setGenerationParam(
          'topic',
          selected.isEmpty ? null : selected,
        );
  }
}
