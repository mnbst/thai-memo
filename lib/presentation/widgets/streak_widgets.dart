import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../l10n/app_localizations.dart';
import '../providers/streak_provider.dart';

/// 炎は金寄り（「伸びている＝金」に合わせる）。エラーの朱は使わない。
const _flame = Color(0xFFB9852E);
const _flameDeep = Color(0xFFA06A1E);

class _Look {
  const _Look(this.icon, this.iconColor, this.bg, this.border, this.text);
  final IconData icon;
  final Color iconColor;
  final Color bg;
  final Color border;
  final Color text;
}

/// 炎は1系統のまま、節目ごとにチップが温まる。
///   0日      : 白抜きの炎（灰）
///   1〜6日   : 炎（金）
///   7〜13日  : ＋淡い金の地
///   14〜29日 : ＋金の縁
///   30日〜   : 深藍の地に金の炎（例文カードと同じ組み合わせ）
_Look _lookFor(int streak, ColorScheme cs) {
  if (streak == 0) {
    return _Look(Icons.local_fire_department_outlined, cs.onSurfaceVariant,
        cs.surface, cs.outlineVariant, cs.onSurfaceVariant);
  }
  if (streak < 7) {
    return _Look(Icons.local_fire_department, _flame, cs.surface,
        cs.outlineVariant, cs.onSurface);
  }
  if (streak < 14) {
    return _Look(Icons.local_fire_department, _flameDeep, cs.tertiaryContainer,
        cs.tertiaryContainer, cs.onSurface);
  }
  if (streak < 30) {
    return _Look(Icons.local_fire_department, _flameDeep, cs.tertiaryContainer,
        AppColors.gold, cs.onTertiaryContainer);
  }
  return const _Look(Icons.local_fire_department, AppColors.gold,
      AppColors.indigo, AppColors.gold, Color(0xFFF4EFE4));
}

/// 学習画面ヘッダー、語彙スコアの隣に置く連続日数。
class StreakChip extends ConsumerWidget {
  const StreakChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final streak = ref.watch(streakProvider).current;
    final l10n = L10n.of(context);
    final cs = Theme.of(context).colorScheme;
    final look = _lookFor(streak, cs);
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: look.bg,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: look.border, width: 1.2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(look.icon, size: 16, color: look.iconColor),
          const SizedBox(width: 5),
          Text(
            streak > 0 ? l10n.streakChipDays(streak) : l10n.streakChipStart,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: look.text,
                ),
          ),
        ],
      ),
    );
  }
}

/// 設定画面、語彙スコアの下に置く連続日数のカード。直近7日の帯と次の節目。
class StreakCard extends ConsumerWidget {
  const StreakCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(streakProvider);
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final look = _lookFor(summary.current, cs);
    final next = summary.nextMilestone;
    final title = summary.current > 0
        ? l10n.streakTitle(summary.current)
        : summary.hasHistory
            ? l10n.streakRestart
            : l10n.streakStart;
    final weekdays = l10n.streakWeekdayLetters.characters.toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: look.bg,
                    shape: BoxShape.circle,
                    border: Border.all(color: look.border, width: 1.2),
                  ),
                  child: Icon(look.icon, size: 18, color: look.iconColor),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                if (summary.best > 0)
                  Text(
                    l10n.streakBest(summary.best),
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: cs.onSurfaceVariant),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (var offset = 6; offset >= 0; offset--)
                  _DayMark(
                    summary: summary,
                    day: summary.today.subtract(Duration(days: offset)),
                    label: offset == 0
                        ? l10n.streakToday
                        : weekdays[summary.today
                                .subtract(Duration(days: offset))
                                .weekday -
                            1],
                  ),
              ],
            ),
            if (summary.current > 0 && next != null) ...[
              const SizedBox(height: 12),
              Text(
                l10n.streakNextMilestone(next - summary.current, next),
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: AppColors.goldInk),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DayMark extends StatelessWidget {
  const _DayMark({
    required this.summary,
    required this.day,
    required this.label,
  });

  final StreakSummary summary;
  final DateTime day;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isToday = day == summary.today;
    final done = summary.isDone(day);
    final first = summary.firstDate;
    // 記録を始める前の日は丸を描かない（最初から欠けて見せない）。
    final beforeStart = !isToday && (first == null || day.isBefore(first));

    return Column(
      children: [
        SizedBox(
          width: 30,
          height: 30,
          child: beforeStart
              ? Center(
                  child: Text('―',
                      style: TextStyle(color: cs.outlineVariant, fontSize: 14)),
                )
              : Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: done ? AppColors.gold : null,
                    border: Border.all(
                      color:
                          done || isToday ? AppColors.gold : cs.outlineVariant,
                      width: 1.5,
                    ),
                  ),
                  child: done
                      ? const Icon(Icons.check, size: 16, color: Colors.white)
                      : null,
                ),
        ),
        const SizedBox(height: 5),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: isToday ? cs.onSurface : cs.onSurfaceVariant,
            fontWeight: isToday ? FontWeight.w700 : null,
          ),
        ),
      ],
    );
  }
}
