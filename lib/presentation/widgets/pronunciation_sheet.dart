// =============================================================================
// pronunciation_sheet.dart
// ホームの今日の例文カードから発音練習を開くボトムシート。
//
// 中身は詳細画面と同じ PronunciationPractice。ホームのカードは全体が詳細への
// タップ領域で、しかも判定結果は縦に長い（帯＋コーチ＋ピッチカーブ）ため、
// カード内へ展開せずシートに逃がす。
//
// 録音は onTapDown/onTapUp で取るので、シートのドラッグと取り合うと押している
// 途中で閉じてしまう。enableDrag は切り、閉じるのは×かシート外タップのみ。
// =============================================================================

import 'package:flutter/material.dart';

import '../../data/models/thai_sentence.dart';
import '../../domain/sentence_tone_spans.dart';
import '../../l10n/app_localizations.dart';
import 'pronunciation_practice.dart';
import 'sentence_audio_player.dart';

/// 発音練習を出せる例文か。出せないなら入口ごと隠す。
bool canPractisePronunciation(ThaiSentence sentence) {
  if (sentence.id == null) return false;
  return !buildSentenceToneSpans(
    sentence.wordBreakdowns,
    thaiText: sentence.thaiText,
  ).isEmpty;
}

Future<void> showPronunciationSheet(
  BuildContext context,
  ThaiSentence sentence,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    enableDrag: false,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) => _PronunciationSheet(sentence: sentence),
  );
}

class _PronunciationSheet extends StatelessWidget {
  const _PronunciationSheet({required this.sentence});

  final ThaiSentence sentence;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    sentence.thaiText,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                  tooltip: l10n.commonClose,
                ),
              ],
            ),
            Text(
              sentence.pronunciation,
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(height: 12),
            // 判定結果が伸びるぶんはシート内でスクロールさせる
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // お手本を聞いてから話す。ここに再生が無いと、聞かずに
                    // 録音するしかない（カードからは詳細へ移らずに開くため）。
                    SentenceAudioPlayer(
                      text: sentence.thaiText,
                      words: sentence.wordBreakdowns
                          .map((w) => w.wordText)
                          .toList(),
                    ),
                    const SizedBox(height: 12),
                    PronunciationPractice(
                      scope: 'sheet',
                      sentenceId: sentence.id,
                      words: sentence.wordBreakdowns,
                      thaiText: sentence.thaiText,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
