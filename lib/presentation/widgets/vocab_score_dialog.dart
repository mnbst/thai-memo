import 'package:flutter/material.dart';

import '../../core/config/app_config.dart';
import '../screens/paywall_screen.dart';

const int freeVocabScoreLimit = 100;
const String _freeTopics = 'あいさつ、食べ物、買い物';

String vocabLevel(int vocab) {
  if (vocab < 100) return '入門';
  if (vocab < 300) return '初級';
  if (vocab < 600) return '初中級';
  if (vocab < 1500) return '中級';
  return '上級';
}

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
  final currentTopicCount = _topicCount(currentTopics);
  final nextTopicCount =
      nextUnlock == null ? 0 : _topicCount(nextUnlock.addedTopics);
  final progressValue = threshold == null
      ? 0.0
      : (displayVocab / threshold).clamp(0.0, 1.0).toDouble();
  final remainingText = threshold == null
      ? null
      : !isPremium && displayVocab >= threshold
          ? 'Free上限'
          : '残り${threshold - displayVocab}語';

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
        title: Text(isPremium ? '語彙スコア（$level）' : '語彙スコア（Free・$level）'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (threshold != null) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('$displayVocab / $threshold 語',
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
                    ? '現在のテーマ数（$currentTopicCount件）'
                    : 'Freeのテーマ数（$currentTopicCount件）',
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
                      ? '次の開放（+$nextTopicCount件）'
                      : 'あと${threshold - displayVocab}語で開放（+$nextTopicCount件）',
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
              label: const Text('Premiumを見る'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('閉じる'),
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

String _topicsForLevel(int vocab) {
  if (vocab < 100) {
    return 'あいさつ、食べ物、旅行、家族、買い物、天気';
  }
  if (vocab < 300) {
    return 'あいさつ、食べ物、旅行、家族、買い物、天気、仕事、交通、健康、趣味、恋愛';
  }
  if (vocab < 600) {
    return 'あいさつ、食べ物、旅行、家族、買い物、天気、仕事、交通、健康、趣味、恋愛、学校';
  }
  return 'あいさつ、食べ物、旅行、家族、買い物、天気、仕事、交通、健康、趣味、恋愛、学校、宗教・信仰、伝統・祭り、礼儀作法';
}

({String label, String addedTopics})? _nextUnlock(int vocab) {
  if (vocab < 100) {
    return (label: '初級', addedTopics: '仕事、交通、健康、趣味、恋愛');
  }
  if (vocab < 300) {
    return (label: '初中級', addedTopics: '学校');
  }
  if (vocab < 600) {
    return (label: '中級', addedTopics: '宗教・信仰、伝統・祭り、礼儀作法');
  }
  return null;
}

int _topicCount(String topics) {
  return topics
      .split('、')
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .length;
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
                'Freeは100語が上限です',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Premiumでは100語以上学べます。また例文のテーマが増え、より多様なタイ語が学べます。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color:
                      colorScheme.onPrimaryContainer.withValues(alpha: 0.85),
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
  final message = nextCount > 0 && nextThreshold != null
      ? '語彙スコアが増えると次の例文テーマが開放されます。'
      : '例文テーマ候補は現在$currentCount件です。';

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
  const addedTopics = '旅行、仕事、恋愛、家族、天気、交通、健康、趣味、学校、宗教・信仰、伝統・祭り、礼儀作法';

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
          'Premiumで追加されるテーマ数（13件）',
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
            value: addedTopics,
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
  required String topics,
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
              _topicListRow(value: topics, borderColor: rowBorderColor),
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
  required String value,
  required Color borderColor,
  bool showBottomBorder = false,
}) {
  final items = value
      .split('、')
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList();

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
              i == items.length - 1 ? items[i] : '${items[i]}、',
              maxLines: 1,
              softWrap: false,
            ),
        ],
      ),
    ),
  );
}
