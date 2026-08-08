import 'package:flutter/material.dart';

import '../../core/config/app_config.dart';
import '../../core/constants/generation_labels.dart';
import '../../l10n/app_localizations.dart';
import '../screens/paywall_screen.dart';

const int freeVocabScoreLimit = 100;
const _freeTopics = ['あいさつ', '食べ物', '買い物', 'タイBLドラマ'];

/// 語彙レベルの識別子。prefs に保存され `_thresholdForLevel` の判定にも使うため
/// 日本語のまま変えない。表示には [vocabLevelLabel] を使うこと。
String vocabLevel(int vocab) {
  if (vocab < 100) return '入門';
  if (vocab < 300) return '初級';
  if (vocab < 600) return '初中級';
  if (vocab < 1500) return '中級';
  return '上級';
}

/// 語彙レベル識別子の表示ラベル。
String vocabLevelLabel(L10n l10n, String level) => switch (level) {
      '初級' => l10n.vocabLevelBeginner,
      '初中級' => l10n.vocabLevelUpperBeginner,
      '中級' => l10n.vocabLevelIntermediate,
      '上級' => l10n.vocabLevelAdvanced,
      _ => l10n.vocabLevelIntro,
    };

void showVocabScoreInfo(
  BuildContext context,
  int vocab, {
  required bool isPremium,
}) {
  final displayVocab =
      isPremium ? vocab : vocab.clamp(0, freeVocabScoreLimit).toInt();
  final level = vocabLevel(displayVocab);
  final nextUnlock = isPremium ? _nextUnlock(displayVocab) : null;
  final threshold =
      isPremium ? _nextThreshold(displayVocab) : freeVocabScoreLimit;
  final currentTopics = isPremium ? _topicsForLevel(displayVocab) : _freeTopics;
  final currentTopicCount = currentTopics.length;
  final nextTopicCount = nextUnlock == null ? 0 : nextUnlock.addedTopics.length;
  final progressValue = threshold == null
      ? 0.0
      : (displayVocab / threshold).clamp(0.0, 1.0).toDouble();
  final l10n = lookupL10n(Localizations.localeOf(context));
  final levelLabel = vocabLevelLabel(l10n, level);
  final remainingText = threshold == null
      ? null
      : !isPremium && displayVocab >= threshold
          ? l10n.vocabFreeCap
          : l10n.vocabRemaining(threshold - displayVocab);

  showDialog<void>(
    context: context,
    builder: (dialogContext) {
      final theme = Theme.of(dialogContext);
      void openPaywall() {
        Navigator.pop(dialogContext);
        PaywallBottomSheet.show(
          context,
          source: 'vocab_score_dialog',
        );
      }

      return AlertDialog(
        title: Text(isPremium
            ? l10n.vocabDialogTitle(levelLabel)
            : l10n.vocabDialogTitleFree(levelLabel)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (threshold != null) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(l10n.vocabProgressOf(displayVocab, threshold),
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text(remainingText!,
                        style: TextStyle(
                            color: theme.colorScheme.onSurfaceVariant)),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progressValue,
                    minHeight: 8,
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  ),
                ),
                const SizedBox(height: 20),
              ],
              if (!isPremium) ...[
                _buildFreeVocabLimitCallout(dialogContext),
                const SizedBox(height: 16),
              ],
              if (isPremium) ...[
                _buildTopicUnlockSummary(
                  dialogContext,
                  currentCount: currentTopicCount,
                  nextThreshold: threshold,
                  nextCount: nextTopicCount,
                ),
                const SizedBox(height: 16),
              ],
              _buildCategoryBlock(
                dialogContext,
                title: isPremium
                    ? l10n.vocabCurrentTopics(currentTopicCount)
                    : l10n.vocabFreeTopics(currentTopicCount),
                topics: currentTopics,
              ),
              if (!isPremium) ...[
                const SizedBox(height: 16),
                Divider(
                  height: 1,
                  color: theme.colorScheme.outlineVariant,
                ),
                const SizedBox(height: 16),
                _buildScoreUnlockPreview(dialogContext),
              ],
              if (nextUnlock != null) ...[
                const SizedBox(height: 16),
                Divider(
                  height: 1,
                  color: theme.colorScheme.outlineVariant,
                ),
                const SizedBox(height: 16),
                _buildCategoryBlock(
                  dialogContext,
                  title: threshold == null
                      ? l10n.vocabNextUnlock(nextTopicCount)
                      : l10n.vocabNextUnlockIn(
                          threshold - displayVocab, nextTopicCount),
                  topics: nextUnlock.addedTopics,
                  addition: true,
                ),
              ],
            ],
          ),
        ),
        actions: [
          if (!isPremium)
            FilledButton.icon(
              onPressed: openPaywall,
              icon: const Icon(Icons.auto_awesome, size: 18),
              label: Text(l10n.vocabSeePremium),
            ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(l10n.commonClose),
          ),
        ],
      );
    },
  );
}

int? _nextThreshold(int vocab) {
  if (vocab < 100) return 100;
  if (vocab < 300) return 300;
  if (vocab < 600) return 600;
  return null;
}

const _l1Topics = ['あいさつ', '食べ物', '旅行', '家族', '買い物', '天気'];
const _l2Topics = [..._l1Topics, '仕事', '交通', '健康', '趣味', '恋愛・男女関係'];
const _l3Topics = [..._l2Topics, '学校'];
const _l4Topics = [..._l3Topics, '宗教・信仰', '伝統・祭り', '礼儀作法'];

List<String> _topicsForLevel(int vocab) {
  if (vocab < 100) return _l1Topics;
  if (vocab < 300) return _l2Topics;
  if (vocab < 600) return _l3Topics;
  return _l4Topics;
}

({String level, List<String> addedTopics})? _nextUnlock(int vocab) {
  if (vocab < 100) {
    return (
      level: '初級',
      addedTopics: ['仕事', '交通', '健康', '趣味', '恋愛・男女関係'],
    );
  }
  if (vocab < 300) {
    return (level: '初中級', addedTopics: ['学校']);
  }
  if (vocab < 600) {
    return (
      level: '中級',
      addedTopics: ['宗教・信仰', '伝統・祭り', '礼儀作法'],
    );
  }
  return null;
}

Widget _buildFreeVocabLimitCallout(BuildContext context) {
  final theme = Theme.of(context);
  final colorScheme = theme.colorScheme;

  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: colorScheme.primaryContainer.withValues(alpha: 0.55),
      border: Border.all(
        color: colorScheme.primary.withValues(alpha: 0.35),
      ),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.lock_outline, size: 22, color: colorScheme.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                L10n.of(context).vocabFreeLimitTitle,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                L10n.of(context).vocabFreeLimitBody,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onPrimaryContainer.withValues(alpha: 0.85),
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

Widget _buildTopicUnlockSummary(
  BuildContext context, {
  required int currentCount,
  required int? nextThreshold,
  required int nextCount,
}) {
  final theme = Theme.of(context);
  final l10n = L10n.of(context);
  final message = nextCount > 0 && nextThreshold != null
      ? l10n.vocabUnlockMore
      : l10n.vocabTopicCountNow(currentCount);

  return Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.auto_stories_outlined,
          size: 18,
          color: theme.colorScheme.onSecondaryContainer,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSecondaryContainer,
              height: 1.35,
            ),
          ),
        ),
      ],
    ),
  );
}

Widget _buildScoreUnlockPreview(BuildContext context) {
  final colorScheme = Theme.of(context).colorScheme;
  const addedTopics = [
    '旅行',
    '仕事',
    '恋愛・男女関係',
    '家族',
    '天気',
    '交通',
    '健康',
    '趣味',
    '学校',
    '宗教・信仰',
    '伝統・祭り',
    '礼儀作法',
  ];

  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: colorScheme.primaryContainer.withValues(alpha: 0.28),
      border: Border.all(
        color: colorScheme.primary.withValues(alpha: 0.18),
      ),
      borderRadius: BorderRadius.circular(AppConfig.cardBorderRadius),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          L10n.of(context).vocabPremiumAddsTopics(addedTopics.length),
          style: TextStyle(
            color: colorScheme.primary,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            border: Border.all(color: colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(8),
          ),
          child: _topicListRow(
            context: context,
            topics: addedTopics,
            borderColor: colorScheme.outlineVariant,
          ),
        ),
      ],
    ),
  );
}

Widget _buildCategoryBlock(
  BuildContext context, {
  required String title,
  required List<String> topics,
  bool addition = false,
}) {
  final theme = Theme.of(context);
  final titleColor = addition ? theme.colorScheme.primary : null;
  final rowBorderColor = theme.colorScheme.outlineVariant;
  final block = Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          if (addition) ...[
            Icon(Icons.lock, size: 16, color: titleColor),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              title,
              style: TextStyle(fontWeight: FontWeight.bold, color: titleColor),
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      Container(
        width: double.infinity,
        decoration: BoxDecoration(
          border: Border.all(color: rowBorderColor),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            if (topics.isNotEmpty)
              _topicListRow(
                  context: context,
                  topics: topics,
                  borderColor: rowBorderColor),
          ],
        ),
      ),
    ],
  );

  if (!addition) return block;

  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: theme.colorScheme.primaryContainer.withValues(alpha: 0.28),
      border: Border.all(
        color: theme.colorScheme.primary.withValues(alpha: 0.18),
      ),
      borderRadius: BorderRadius.circular(AppConfig.cardBorderRadius),
    ),
    child: block,
  );
}

Widget _topicListRow({
  required BuildContext context,
  required List<String> topics,
  required Color borderColor,
  bool showBottomBorder = false,
}) {
  final l10n = L10n.of(context);
  final separator = l10n.listSeparator;
  final items = topics.map((t) => topicLabel(l10n, t).name).toList();

  return Container(
    decoration: BoxDecoration(
      border: showBottomBorder
          ? Border(bottom: BorderSide(color: borderColor))
          : null,
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        children: [
          for (var i = 0; i < items.length; i++)
            Text(
              i == items.length - 1 ? items[i] : '${items[i]}$separator',
              maxLines: 1,
              softWrap: false,
            ),
        ],
      ),
    ),
  );
}
