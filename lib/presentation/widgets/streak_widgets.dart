import 'dart:async';

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

/// 演出で出すタイ語のほめ言葉。言語設定によらずタイ語で出す。
/// 1日目は応援、あとはチップの節目に合わせて強くしていく。
String _praiseFor(int streak) {
  if (streak <= 1) return 'สู้ๆ 💪'; // がんばれ
  if (streak < 7) return 'เก่งมาก 👍'; // すごいね
  if (streak < 14) return 'สุดยอด 🎉'; // 最高
  if (streak < 30) return 'ยอดเยี่ยม 🏆'; // 素晴らしい
  return 'เทพมาก 👑'; // 神レベル
}

/// 学習画面ヘッダー、語彙スコアの隣に置く連続日数。
/// 連続が伸びたら、画面中央に炎を出してからチップを弾ませる。
class StreakChip extends ConsumerStatefulWidget {
  const StreakChip({super.key});

  @override
  ConsumerState<StreakChip> createState() => _StreakChipState();
}

class _StreakChipState extends ConsumerState<StreakChip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _bounce = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  );
  late final Animation<double> _scale = TweenSequence([
    TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.3), weight: 35),
    TweenSequenceItem(
      tween: Tween(begin: 1.3, end: 1.0)
          .chain(CurveTween(curve: Curves.elasticOut)),
      weight: 65,
    ),
  ]).animate(_bounce);
  OverlayEntry? _burst;
  Timer? _reveal;

  /// 演出中だけ、伸びる前の日数を出しておく。中央の炎が消えるころに
  /// 新しい日数へ切り替え、目線をチップへ移す。
  int? _held;

  @override
  void dispose() {
    _reveal?.cancel();
    _removeBurst();
    _bounce.dispose();
    super.dispose();
  }

  void _removeBurst() {
    _burst?.remove();
    _burst = null;
  }

  void _celebrate(int streak) {
    if (MediaQuery.of(context).disableAnimations) return;
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;
    _removeBurst();
    final title = L10n.of(context).streakTitle(streak);
    final entry = OverlayEntry(
      builder: (_) => _StreakBurst(
        title: title,
        praise: _praiseFor(streak),
        look: _lookFor(streak, Theme.of(context).colorScheme),
        onDone: _removeBurst,
      ),
    );
    _burst = entry;
    overlay.insert(entry);

    setState(() => _held = streak - 1);
    _reveal?.cancel();
    _reveal = Timer(const Duration(milliseconds: 2200), () {
      if (!mounted) return;
      setState(() => _held = null);
      _bounce.forward(from: 0);
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(streakCelebrationProvider, (_, __) {
      _celebrate(ref.read(streakProvider).current);
    });
    final streak = _held ?? ref.watch(streakProvider).current;
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final look = _lookFor(streak, cs);
    const duration = Duration(milliseconds: 400);
    final label =
        streak > 0 ? l10n.streakChipDays(streak) : l10n.streakChipStart;
    return ScaleTransition(
      scale: _scale,
      child: AnimatedContainer(
        duration: duration,
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
            // 白抜き→塗りの炎は、ぽんと膨らんで入れ替える。
            AnimatedSwitcher(
              duration: duration,
              transitionBuilder: (child, anim) => ScaleTransition(
                scale: CurvedAnimation(parent: anim, curve: Curves.easeOutBack),
                child: child,
              ),
              child: Icon(look.icon,
                  key: ValueKey(look.icon), size: 16, color: look.iconColor),
            ),
            const SizedBox(width: 5),
            // 日数は下からせり上がって入れ替える。
            ClipRect(
              child: AnimatedSwitcher(
                duration: duration,
                transitionBuilder: (child, anim) {
                  final incoming = child.key == ValueKey(label);
                  return SlideTransition(
                    position: Tween(
                      begin: Offset(0, incoming ? 1 : -1),
                      end: Offset.zero,
                    ).animate(anim),
                    child: FadeTransition(opacity: anim, child: child),
                  );
                },
                child: Text(
                  label,
                  key: ValueKey(label),
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: look.text,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 画面中央に弾んで出て、少し浮きながら消える炎。見た目はチップと同じ節目で変わる。
/// タップは素通しする。
class _StreakBurst extends StatefulWidget {
  const _StreakBurst({
    required this.title,
    required this.praise,
    required this.look,
    required this.onDone,
  });

  final String title;
  final String praise;
  final _Look look;
  final VoidCallback onDone;

  @override
  State<_StreakBurst> createState() => _StreakBurstState();
}

class _StreakBurstState extends State<_StreakBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  )..forward().whenComplete(widget.onDone);

  late final Animation<double> _scale = CurvedAnimation(
    parent: _c,
    curve: const Interval(0, 0.25, curve: Curves.elasticOut),
  );
  late final Animation<double> _opacity = TweenSequence([
    TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 10),
    TweenSequenceItem(tween: ConstantTween(1.0), weight: 75),
    TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 15),
  ]).animate(_c);
  late final Animation<Offset> _rise = Tween(
    begin: Offset.zero,
    end: const Offset(0, -0.15),
  ).animate(CurvedAnimation(
    parent: _c,
    curve: const Interval(0.6, 1, curve: Curves.easeIn),
  ));

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final look = widget.look;
    final cs = theme.colorScheme;
    return IgnorePointer(
      child: Stack(
        children: [
          // 後ろの例文と重ならないよう、画面を少し暗くしてカードを浮かせる。
          Positioned.fill(
            child: FadeTransition(
              opacity: _opacity,
              child: ColoredBox(color: Colors.black.withValues(alpha: 0.3)),
            ),
          ),
          Center(
            child: SlideTransition(
              position: _rise,
              child: FadeTransition(
                opacity: _opacity,
                child: ScaleTransition(
                  scale: _scale,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(32, 28, 32, 22),
                    decoration: BoxDecoration(
                      color: cs.surface,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: const [
                        BoxShadow(color: Colors.black26, blurRadius: 24),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 96,
                          height: 96,
                          decoration: BoxDecoration(
                            color: look.bg,
                            shape: BoxShape.circle,
                            border: Border.all(color: look.border, width: 2),
                            boxShadow: [
                              BoxShadow(
                                color: look.iconColor.withValues(alpha: 0.35),
                                blurRadius: 24,
                              ),
                            ],
                          ),
                          child:
                              Icon(look.icon, size: 56, color: look.iconColor),
                        ),
                        const SizedBox(height: 14),
                        Material(
                          color: Colors.transparent,
                          child: Column(
                            children: [
                              Text(
                                widget.praise,
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.goldInk,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                widget.title,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
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
