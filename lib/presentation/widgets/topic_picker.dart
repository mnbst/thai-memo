import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/generation_constants.dart';
import '../../core/constants/generation_labels.dart';
import '../../l10n/app_localizations.dart';
import '../providers/remaining_quota_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/subscription_provider.dart';
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

  const NextSentenceTopicLabel({super.key, this.paywallSource = 'next_topic'});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPremium = ref.watch(isPremiumProvider);
    final trialActive =
        ref.watch(premiumTrialActiveProvider).valueOrNull ?? false;
    final canSelect = isPremium || trialActive;
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
