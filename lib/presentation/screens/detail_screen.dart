import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../data/models/thai_sentence.dart';
import '../providers/sentence_provider.dart';

/// Detail screen for displaying full sentence information
class DetailScreen extends ConsumerStatefulWidget {
  final ThaiSentence sentence;

  const DetailScreen({super.key, required this.sentence});

  @override
  ConsumerState<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends ConsumerState<DetailScreen> {
  bool _isWordBreakdownExpanded = true;
  bool _isContextExpanded = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('例文の詳細'),
        actions: [
          IconButton(
            icon: Icon(
              widget.sentence.isFavorite
                  ? Icons.favorite
                  : Icons.favorite_border,
            ),
            onPressed: _toggleFavorite,
            tooltip: 'お気に入り',
          ),
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: _shareSentence,
            tooltip: '共有',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppConfig.defaultPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildMainSentenceCard(),
            const SizedBox(height: 16),
            _buildWordBreakdownCard(),
            const SizedBox(height: 16),
            _buildContextCard(),
            const SizedBox(height: 16),
            _buildMetadataCard(),
          ],
        ),
      ),
    );
  }

  /// Build main sentence card
  Widget _buildMainSentenceCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppConfig.defaultPadding * 1.5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Thai text
            SelectableText(
              widget.sentence.thaiText,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w500,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 12),
            // Pronunciation
            Row(
              children: [
                Icon(
                  Icons.record_voice_over,
                  size: 16,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SelectableText(
                    widget.sentence.pronunciation,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Theme.of(
                        context,
                      ).colorScheme.primary.withValues(alpha: 0.8),
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 16),
            // Japanese translation
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.translate,
                  size: 16,
                  color: Theme.of(context).colorScheme.secondary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SelectableText(
                    widget.sentence.japaneseTranslation,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Build word breakdown card
  Widget _buildWordBreakdownCard() {
    return Card(
      child: Column(
        children: [
          InkWell(
            onTap: () {
              setState(() {
                _isWordBreakdownExpanded = !_isWordBreakdownExpanded;
              });
            },
            child: Padding(
              padding: const EdgeInsets.all(AppConfig.defaultPadding),
              child: Row(
                children: [
                  Icon(
                    Icons.list_alt,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '単語の分解 (${widget.sentence.wordBreakdowns.length})',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Icon(
                    _isWordBreakdownExpanded
                        ? Icons.expand_less
                        : Icons.expand_more,
                  ),
                ],
              ),
            ),
          ),
          if (_isWordBreakdownExpanded) ...[
            const Divider(height: 1),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: widget.sentence.wordBreakdowns.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final word = widget.sentence.wordBreakdowns[index];
                return _buildWordBreakdownItem(word, index);
              },
            ),
          ],
        ],
      ),
    );
  }

  /// Build individual word breakdown item
  Widget _buildWordBreakdownItem(word, int index) {
    return Padding(
      padding: const EdgeInsets.all(AppConfig.defaultPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    '${index + 1}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      word.wordText,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      word.pronunciation,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(
                          context,
                        ).colorScheme.primary.withValues(alpha: 0.7),
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(word.meaning, style: Theme.of(context).textTheme.bodyMedium),
          if (word.grammaticalRole != null) ...[
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.secondary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                word.grammaticalRole!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.secondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Build context card
  Widget _buildContextCard() {
    final sentenceContext = widget.sentence.context;
    if (sentenceContext == null) return const SizedBox.shrink();

    return Card(
      child: Column(
        children: [
          InkWell(
            onTap: () {
              setState(() {
                _isContextExpanded = !_isContextExpanded;
              });
            },
            child: Padding(
              padding: const EdgeInsets.all(AppConfig.defaultPadding),
              child: Row(
                children: [
                  Icon(
                    Icons.lightbulb_outline,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '文脈・使い方',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Icon(
                    _isContextExpanded ? Icons.expand_less : Icons.expand_more,
                  ),
                ],
              ),
            ),
          ),
          if (_isContextExpanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(AppConfig.defaultPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (sentenceContext.situation != null) ...[
                    _buildContextItem(
                      Icons.location_on_outlined,
                      '場面',
                      sentenceContext.situation!,
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (sentenceContext.emotion != null) ...[
                    _buildContextItem(
                      Icons.mood_outlined,
                      '感情・トーン',
                      sentenceContext.emotion!,
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (sentenceContext.usageScenarios != null) ...[
                    _buildContextItem(
                      Icons.tips_and_updates_outlined,
                      '使用シーン',
                      sentenceContext.usageScenarios!,
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (sentenceContext.culturalNotes != null) ...[
                    _buildContextItem(
                      Icons.info_outline,
                      '文化的背景',
                      sentenceContext.culturalNotes!,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Build context item
  Widget _buildContextItem(IconData icon, String label, String content) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(content, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
      ],
    );
  }

  /// Build metadata card
  Widget _buildMetadataCard() {
    final createdAt = widget.sentence.createdAt;
    final formattedDate = createdAt != null
        ? '${createdAt.year}/${createdAt.month}/${createdAt.day}'
        : '不明';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppConfig.defaultPadding),
        child: Row(
          children: [
            Icon(
              Icons.calendar_today_outlined,
              size: 16,
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.6),
            ),
            const SizedBox(width: 8),
            Text(
              '作成日: $formattedDate',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Toggle favorite status
  Future<void> _toggleFavorite() async {
    final sentenceId = widget.sentence.id;
    if (sentenceId == null) return;

    await ref
        .read(sentenceControllerProvider.notifier)
        .toggleFavorite(sentenceId, !widget.sentence.isFavorite);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.sentence.isFavorite ? 'お気に入りに追加しました' : 'お気に入りから削除しました',
          ),
          duration: const Duration(seconds: 1),
        ),
      );

      setState(() {
        // Trigger rebuild
      });
    }
  }

  /// Share sentence
  void _shareSentence() {
    final text =
        '''
${widget.sentence.thaiText}
${widget.sentence.pronunciation}

${widget.sentence.japaneseTranslation}
''';

    Clipboard.setData(ClipboardData(text: text));

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('クリップボードにコピーしました'),
        duration: Duration(seconds: 2),
      ),
    );
  }
}
