// =============================================================================
// vocab_word_screen.dart
// 語の詳細。発音・意味・語彙ランク・覚え具合・綴りの分解と、その語を含む例文の
// 一覧を出す。
// 例文をタップすると例文の詳細画面（DetailScreen）へ。
// =============================================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/thai_sentence.dart';
import '../../data/models/vocab_word.dart';
import '../../l10n/app_localizations.dart';
import '../providers/analytics_provider.dart';
import '../providers/sentence_provider.dart';
import '../providers/tts_provider.dart';
import '../providers/vocab_progress_provider.dart';
import '../widgets/spelling_breakdown_view.dart';
import '../widgets/vocab_gauge.dart';
import 'detail_screen.dart';

class VocabWordScreen extends ConsumerWidget {
  static const routeName = 'vocab_word';

  final VocabEntry entry;

  const VocabWordScreen({super.key, required this.entry});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: cs.onSurfaceVariant,
    );

    // 例文の詳細でお気に入りや削除をしたら、戻ったときに反映する。
    final entries = ref.watch(vocabEntriesProvider).valueOrNull;
    final current = entries
            ?.where((e) => e.progress.word == entry.progress.word)
            .firstOrNull ??
        entry;
    final word = current.progress;
    final mastery = word.mastery;
    final syllables = current.sentences
            .expand((s) => s.wordBreakdowns)
            .where((b) => b.wordText == word.word)
            .firstOrNull
            ?.syllables
            ?.map((s) => s.text)
            .toList() ??
        const <String>[];
    void logReview(String action) => unawaited(
          ref
              .read(analyticsServiceProvider)
              .logReviewTab(action: action, value: mastery.name),
        );

    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        top: false,
        // 綴りの分解で上が伸びるので、例文の一覧ごと画面全体でスクロールする。
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
              AppConfig.screenPadding, 0, AppConfig.screenPadding, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Material(
                color: cs.surface,
                borderRadius: BorderRadius.circular(14),
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // タイ語と訳は別の列にして、それぞれの列の中で折り返す。
                          Expanded(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.baseline,
                              textBaseline: TextBaseline.alphabetic,
                              children: [
                                Flexible(
                                  child: Text(
                                    word.word,
                                    style: const TextStyle(
                                      fontSize: 34,
                                      // タイ文字は太らせると声調記号が潰れる。
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                                if (current.meaning.isNotEmpty) ...[
                                  const SizedBox(width: 12),
                                  Flexible(
                                    child: Text(
                                      current.meaning,
                                      style: const TextStyle(fontSize: 20),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          IconButton.filledTonal(
                            icon: const Icon(Icons.volume_up),
                            onPressed: () {
                              logReview('word_tts');
                              ref
                                  .read(ttsServiceProvider)
                                  .speak(word.word, slow: true);
                            },
                          ),
                        ],
                      ),
                      if (current.pronunciation.isNotEmpty)
                        Text(
                          current.pronunciation,
                          style: TextStyle(
                            fontSize: 17,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          if (word.rank > 0) ...[
                            Text(l10n.vocabRankValue(word.rank), style: muted),
                            const SizedBox(width: 10),
                          ],
                          Text(
                            mastery.label(l10n),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: mastery.inkColor(context),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      VocabGauge(word: word, width: double.infinity),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              WordSpellingSection(word: word.word, syllables: syllables),
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 6),
                child: Text(
                  l10n.vocabExamples(current.sentences.length),
                  style: muted,
                ),
              ),
              Material(
                color: cs.surface,
                borderRadius: BorderRadius.circular(14),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    for (var i = 0; i < current.sentences.length; i++) ...[
                      if (i > 0) Divider(height: 1, color: cs.outlineVariant),
                      _sentenceTile(
                          context, ref, current.sentences[i], logReview, muted),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sentenceTile(
    BuildContext context,
    WidgetRef ref,
    ThaiSentence sentence,
    void Function(String) logReview,
    TextStyle? muted,
  ) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return ListTile(
      title: Text(
        sentence.thaiText,
        style: theme.textTheme.titleMedium?.copyWith(
          fontSize: 18,
          fontWeight: FontWeight.w500,
          height: 1.5,
        ),
      ),
      subtitle: Text(
        sentence.japaneseTranslation,
        style: muted,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            sentence.isFavorite ? Icons.favorite : Icons.favorite_border,
            size: 20,
            color:
                sentence.isFavorite ? AppColors.vermilion : cs.onSurfaceVariant,
          ),
          const SizedBox(width: 4),
          Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
        ],
      ),
      onTap: () async {
        logReview('sentence_open');
        await Navigator.push(
          context,
          MaterialPageRoute(
            settings: const RouteSettings(
              name: DetailScreen.routeName,
            ),
            builder: (_) => DetailScreen(
              sentence: sentence,
              source: 'history',
            ),
          ),
        );
        ref.invalidate(allSentencesProvider);
      },
    );
  }
}
