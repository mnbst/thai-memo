import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/app_colors.dart';
import '../../l10n/app_localizations.dart';
import '../providers/analytics_provider.dart';

/// 最初の例文でだけ出す「学習の手順」（学習タブ）と、その例文の詳細で出す
/// 案内（DetailGuideCard）の共通の状態。
///
/// 1本目で止まる人が多い（prod 10月: 止まった人の6割）。読み物や暗幕の案内は
/// 読まれても次の操作につながらなかったので、例文の上に手順を3つだけ並べ、
/// 今やる1つを光らせる。暗幕は出さず、例文を読む邪魔をしない。
enum FirstSetStep { listenSentence, openDetail, quiz }

/// 最初の例文の ID を端末に1つだけ決めて持つ。
///
/// 決めるのは学習タブに初めて例文が出たとき。確認クイズを解いたことがある人
/// （アップデートした既存ユーザー・別端末）は空文字を入れて、どの例文にも
/// 出さない。null はまだ決めていない。
class FirstSentenceIdController extends StateNotifier<String?> {
  FirstSentenceIdController({bool load = true}) : super(null) {
    if (load) unawaited(_load());
  }

  /// モック・テスト用。最初から [state] を最初の例文として持つ。
  FirstSentenceIdController.fixed(super.state);

  bool _decided = false;

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(AppConfig.prefKeyFirstSentenceId);
    if (saved != null && mounted) {
      _decided = true;
      state = saved;
    }
  }

  /// [sentenceId] を最初の例文にしてよいか確かめて決める。既に決まっていれば何もしない。
  Future<void> claim(
    String sentenceId, {
    required Future<bool> Function() isNewLearner,
  }) async {
    if (_decided || state != null) return;
    _decided = true;
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(AppConfig.prefKeyFirstSentenceId);
    final value = saved ?? (await isNewLearner() ? sentenceId : '');
    if (saved == null) {
      await prefs.setString(AppConfig.prefKeyFirstSentenceId, value);
    }
    if (mounted) state = value;
  }
}

final firstSentenceIdProvider =
    StateNotifierProvider<FirstSentenceIdController, String?>(
  (ref) => FirstSentenceIdController(),
);

/// 済んだ手順。端末に残し、翌日開いてもチェックはそのまま。
class FirstStepsDoneController extends StateNotifier<Set<FirstSetStep>> {
  FirstStepsDoneController({bool load = true}) : super(const {}) {
    if (load) unawaited(_load());
  }

  /// モック・テスト用。
  FirstStepsDoneController.fixed(super.done);

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final names = prefs.getStringList(AppConfig.prefKeyFirstStepsDone) ?? [];
    if (!mounted) return;
    state = {
      ...state,
      for (final step in FirstSetStep.values)
        if (names.contains(step.name)) step,
    };
  }

  /// 済んだことにする。初めて済んだときだけ true。
  Future<bool> mark(FirstSetStep step) async {
    if (state.contains(step)) return false;
    state = {...state, step};
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      AppConfig.prefKeyFirstStepsDone,
      [for (final s in state) s.name],
    );
    return true;
  }
}

final firstStepsDoneProvider =
    StateNotifierProvider<FirstStepsDoneController, Set<FirstSetStep>>(
  (ref) => FirstStepsDoneController(),
);

/// [sentenceId] が最初の例文か。
bool isFirstSentence(WidgetRef ref, String? sentenceId) {
  final first = ref.watch(firstSentenceIdProvider);
  return sentenceId != null && first != null && first == sentenceId;
}

/// 最初の例文のとき、[step] を済んだことにして計測する。
void markFirstStep(WidgetRef ref, String? sentenceId, FirstSetStep step) {
  final first = ref.read(firstSentenceIdProvider);
  if (sentenceId == null || first != sentenceId) return;
  unawaited(
    ref.read(firstStepsDoneProvider.notifier).mark(step).then((isNew) {
      if (isNew) {
        unawaited(ref
            .read(analyticsServiceProvider)
            .logCoachMark(id: 'first_steps', action: step.name));
      }
    }),
  );
}

class FirstSetSteps extends ConsumerStatefulWidget {
  const FirstSetSteps({super.key, required this.sentenceId, this.onStartQuiz});

  final String? sentenceId;

  /// 3つ目の「解く」。押すとそのまま確認クイズを始める。
  final VoidCallback? onStartQuiz;

  @override
  ConsumerState<FirstSetSteps> createState() => _FirstSetStepsState();
}

class _FirstSetStepsState extends ConsumerState<FirstSetSteps> {
  bool _shownLogged = false;

  @override
  Widget build(BuildContext context) {
    if (!isFirstSentence(ref, widget.sentenceId)) {
      return const SizedBox.shrink();
    }
    if (!_shownLogged) {
      _shownLogged = true;
      unawaited(ref
          .read(analyticsServiceProvider)
          .logCoachMark(id: 'first_steps', action: 'shown'));
    }
    final done = ref.watch(firstStepsDoneProvider);
    FirstSetStep? current;
    for (final step in FirstSetStep.values) {
      if (!done.contains(step)) {
        current = step;
        break;
      }
    }

    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    String label(FirstSetStep step) => switch (step) {
          FirstSetStep.listenSentence => l10n.firstStepsListenSentence,
          FirstSetStep.openDetail => l10n.firstStepsOpenDetail,
          FirstSetStep.quiz => l10n.firstStepsQuiz,
        };
    String hint(FirstSetStep step) => switch (step) {
          FirstSetStep.listenSentence => l10n.firstStepsListenSentenceHint,
          FirstSetStep.openDetail => l10n.firstStepsOpenDetailHint,
          FirstSetStep.quiz => l10n.firstStepsQuizHint,
        };

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppConfig.cardBorderRadius),
        side: BorderSide(color: cs.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  l10n.firstStepsTitle,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Text(
                  '${done.length} / ${FirstSetStep.values.length}',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (final (i, step) in FirstSetStep.values.indexed)
              _StepRow(
                number: i + 1,
                label: label(step),
                hint: step == current ? hint(step) : null,
                done: done.contains(step),
                active: step == current,
                action: step == FirstSetStep.quiz && step == current
                    ? FilledButton(
                        onPressed: widget.onStartQuiz,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.jade,
                          visualDensity: VisualDensity.compact,
                        ),
                        child: Text(l10n.firstStepsQuizStart),
                      )
                    : null,
              ),
          ],
        ),
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.number,
    required this.label,
    required this.done,
    required this.active,
    this.hint,
    this.action,
  });

  final int number;
  final String label;
  final String? hint;
  final bool done;
  final bool active;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final color = done
        ? cs.onSurfaceVariant
        : active
            ? AppColors.jade
            : cs.onSurfaceVariant.withValues(alpha: 0.6);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: done
                  ? AppColors.jade
                  : active
                      ? AppColors.jade.withValues(alpha: 0.12)
                      : Colors.transparent,
              border: Border.all(
                color: done || active ? AppColors.jade : cs.outlineVariant,
                width: active ? 2 : 1,
              ),
            ),
            child: done
                ? const Icon(Icons.check_rounded, size: 16, color: Colors.white)
                : Text(
                    '$number',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: active ? cs.onSurface : color,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                    decoration: done ? TextDecoration.lineThrough : null,
                    decorationColor: cs.onSurfaceVariant,
                  ),
                ),
                if (hint != null)
                  Text(
                    hint!,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: cs.onSurfaceVariant),
                  ),
              ],
            ),
          ),
          if (action != null) ...[const SizedBox(width: 8), action!],
        ],
      ),
    );
  }
}
