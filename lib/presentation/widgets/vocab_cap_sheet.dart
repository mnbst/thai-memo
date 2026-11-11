import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme/app_colors.dart';
import '../../l10n/app_localizations.dart';
import '../providers/analytics_provider.dart';
import '../screens/paywall_screen.dart';
import 'vocab_level.dart';

const _shownKey = 'vocab_cap_sheet_shown';

/// free が語彙スコア100に届いたとき、まとめクイズの結果の上に1度だけ出すシート。
///
/// 結果カードの小さな1行（quiz_vocab_cap_banner）は30日でタップ4人と気づかれて
/// いなかった。到達を祝ってから、この先が premium だと段で見せる。
class VocabCapSheet extends StatelessWidget {
  const VocabCapSheet({super.key, this.onContinue});

  /// 「プレミアムで続ける」。省略時はペイウォールを開く。
  final VoidCallback? onContinue;

  /// まだ出していなければ出す。出したら端末に記録し、2度目からは出さない。
  static Future<void> showOnce(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_shownKey) ?? false) return;
    await prefs.setBool(_shownKey, true);
    if (!context.mounted) return;
    // 表示数。押した数は paywall_view（source=vocab_cap_sheet）で数える。
    unawaited(
      ProviderScope.containerOf(context, listen: false)
          .read(analyticsServiceProvider)
          .logPaywallBanner(action: 'shown', source: 'vocab_cap_sheet'),
    );
    await show(context);
  }

  static Future<void> show(BuildContext context, {VoidCallback? onContinue}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.94,
        child: VocabCapSheet(onContinue: onContinue),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 12),
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  const Text('🎉', style: TextStyle(fontSize: 30)),
                  Text(
                    l10n.vocabWords(freeVocabScoreLimit),
                    style: textTheme.displayLarge?.copyWith(
                      fontSize: 60,
                      height: 1.1,
                      fontWeight: FontWeight.w800,
                      color: colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.vocabCapSheetTitle,
                    textAlign: TextAlign.center,
                    style: textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    l10n.vocabCapSheetBody,
                    textAlign: TextAlign.center,
                    style: textTheme.bodyMedium
                        ?.copyWith(color: colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 18),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      child: Column(
                        children: [
                          _Step(
                            label: l10n.vocabWordsRange(
                                1, freeVocabScoreLimit - 1),
                            state: _StepState.done,
                          ),
                          _Step(
                            label: l10n.vocabWords(freeVocabScoreLimit),
                            state: _StepState.current,
                            pill: l10n.vocabCapSheetHere,
                          ),
                          _Step(
                            label: l10n.vocabWordsRange(
                                freeVocabScoreLimit + 1, 300),
                            state: _StepState.locked,
                            pill: l10n.vocabCapSheetPremium,
                          ),
                          _Step(
                            label: l10n.vocabWordsRange(301, 1000),
                            state: _StepState.locked,
                          ),
                          _Step(
                            label: l10n.vocabWordsOver(1001),
                            state: _StepState.locked,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _Feature(text: l10n.vocabCapSheetFeatureCap),
                  _Feature(text: l10n.vocabCapSheetFeatureUnlimited),
                  _Feature(text: l10n.vocabCapSheetFeatureTopic),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.gold,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: () {
                final navigator = Navigator.of(context);
                // シートを閉じたあとも生きている context でペイウォールを開く
                final rootContext = navigator.context;
                navigator.pop();
                if (onContinue != null) {
                  onContinue!();
                } else {
                  PaywallScreen.show(rootContext, source: 'vocab_cap_sheet');
                }
              },
              child: Text(
                l10n.vocabCapSheetCta,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.vocabCapSheetLater),
          ),
        ],
      ),
    );
  }
}

enum _StepState { done, current, locked }

class _Step extends StatelessWidget {
  const _Step({required this.label, required this.state, this.pill});

  final String label;
  final _StepState state;
  final String? pill;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final locked = state == _StepState.locked;

    final (Color dotColor, IconData icon, Color iconColor) = switch (state) {
      _StepState.done => (AppColors.jade, Icons.check, Colors.white),
      _StepState.current => (
          colorScheme.primary,
          Icons.circle,
          colorScheme.onPrimary
        ),
      _StepState.locked => (
          colorScheme.surfaceContainerHighest,
          Icons.lock,
          colorScheme.onSurfaceVariant
        ),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
            child: Icon(icon, size: 12, color: iconColor),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: textTheme.bodyMedium?.copyWith(
                color: locked ? colorScheme.onSurfaceVariant : null,
                fontWeight:
                    state == _StepState.current ? FontWeight.w800 : null,
              ),
            ),
          ),
          if (pill != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: locked
                    ? AppColors.gold
                    : colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                pill!,
                style: textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: locked ? Colors.white : colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Feature extends StatelessWidget {
  const _Feature({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.check, size: 18, color: AppColors.jade),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}
