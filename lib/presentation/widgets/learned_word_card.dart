// =============================================================================
// learned_word_card.dart
// クイズの回答で語が「覚えた」に入ったときに、画面を暗くして出すカード。
// 3秒で消える。タップでもすぐ閉じて、下の解説を読める。
// =============================================================================

import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../l10n/app_localizations.dart';

Future<void> showLearnedWordCard(
  BuildContext context, {
  required String word,
  required String pronunciation,
  required String meaning,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black.withValues(alpha: 0.6),
    transitionDuration: const Duration(milliseconds: 200),
    transitionBuilder: (_, animation, __, child) => FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.8, end: 1).animate(
          CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
        ),
        child: child,
      ),
    ),
    pageBuilder: (_, __, ___) => LearnedWordCard(
      word: word,
      pronunciation: pronunciation,
      meaning: meaning,
    ),
  );
}

class LearnedWordCard extends StatefulWidget {
  static const Duration visibleFor = Duration(seconds: 3);

  final String word;
  final String pronunciation;
  final String meaning;

  const LearnedWordCard({
    super.key,
    required this.word,
    required this.pronunciation,
    required this.meaning,
  });

  @override
  State<LearnedWordCard> createState() => _LearnedWordCardState();
}

class _LearnedWordCardState extends State<LearnedWordCard> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(LearnedWordCard.visibleFor, _close);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _close() {
    _timer?.cancel();
    if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: const Alignment(0, -0.3),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Material(
          color: theme.colorScheme.surface,
          elevation: 12,
          borderRadius: BorderRadius.circular(24),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: _close,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 28, 28, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.check_circle,
                      color: AppColors.jade, size: 44),
                  const SizedBox(height: 10),
                  Text(
                    L10n.of(context).vocabLearnedAdded,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: AppColors.jade,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  // 長い語は折り返さず、1行に収まるまで縮める。
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      widget.word,
                      maxLines: 1,
                      softWrap: false,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontSize: 64,
                        // タイ文字は太らせると声調記号が潰れる。
                        fontWeight: FontWeight.w500,
                        height: 1.4,
                      ),
                    ),
                  ),
                  if (widget.pronunciation.isNotEmpty)
                    Text(
                      widget.pronunciation,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  if (widget.meaning.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      widget.meaning,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleLarge,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
