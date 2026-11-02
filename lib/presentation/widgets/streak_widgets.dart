import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

/// 節目のタイ語のほめ言葉と、その訳（表示言語）。節目が進むほど強くする。
(String, String) _praiseFor(int streak, L10n l10n) {
  if (streak <= 1) return ('สู้ๆ 💪', l10n.streakPraiseFight);
  if (streak < 7) return ('เก่งมาก 👍', l10n.streakPraiseGreat);
  if (streak < 14) return ('สุดยอด 🎉', l10n.streakPraiseAwesome);
  if (streak < 30) return ('ยอดเยี่ยม 🏆', l10n.streakPraiseExcellent);
  return ('เทพมาก 👑', l10n.streakPraiseLegend);
}

/// 紙吹雪と光で派手に祝う節目。7・14・30・50・100日、その先は100日ごと。
bool isStreakMilestone(int streak) =>
    const {7, 14, 30, 50, 100}.contains(streak) ||
    (streak > 100 && streak % 100 == 0);

/// 節目を大きく出す言い方。7・14日は週、30日は1か月、ほかは日数。
String _milestoneLabel(int streak, L10n l10n) {
  if (streak == 7 || streak == 14) return l10n.streakBurstWeeks(streak ~/ 7);
  if (streak == 30) return l10n.streakBurstMonth;
  return l10n.streakBurstDays(streak);
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

  /// 炎が消えたとき（タップで閉じたときも）。日数がまだ前のままなら、
  /// その場で新しい日数へ切り替えて弾ませる。
  void _finishBurst() {
    _removeBurst();
    if (!mounted || _held == null) return;
    _reveal?.cancel();
    setState(() => _held = null);
    _bounce.forward(from: 0);
  }

  void _celebrate(int streak) {
    if (MediaQuery.of(context).disableAnimations) return;
    final overlay = Overlay.maybeOf(context);
    // 中央のカードは毎日出す。出せないときはチップが弾むだけ。
    if (overlay == null) {
      _reveal?.cancel();
      _removeBurst();
      if (_held != null) setState(() => _held = null);
      _bounce.forward(from: 0);
      return;
    }
    _removeBurst();
    final l10n = L10n.of(context);
    final (praise, praiseMeaning) = _praiseFor(streak, l10n);
    final festive = isStreakMilestone(streak);
    final entry = OverlayEntry(
      builder: (_) => _StreakBurst(
        milestone: _milestoneLabel(streak, l10n),
        done: streak == 1 ? l10n.streakBurstStart : l10n.streakBurstDone,
        praise: praise,
        praiseMeaning: praiseMeaning,
        look: _lookFor(streak, Theme.of(context).colorScheme),
        festive: festive,
        onDone: _finishBurst,
      ),
    );
    _burst = entry;
    overlay.insert(entry);

    setState(() => _held = streak - 1);
    _reveal?.cancel();
    _reveal = Timer(
        _StreakBurst.durationFor(festive) - const Duration(milliseconds: 400),
        () {
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
/// タップするとすぐ閉じる。
class _StreakBurst extends StatefulWidget {
  const _StreakBurst({
    required this.milestone,
    required this.done,
    required this.praise,
    required this.praiseMeaning,
    required this.look,
    required this.festive,
    required this.onDone,
  });

  static Duration durationFor(bool festive) =>
      Duration(milliseconds: festive ? 3600 : 2600);

  /// 大きく出す達成（「1週間」「100日」）。
  final String milestone;

  /// 達成の添え書き（「続きました！」）。
  final String done;

  /// タイ語のほめ言葉と、その訳。
  final String praise;
  final String praiseMeaning;
  final _Look look;

  /// 節目の日。後ろに光の筋を回し、紙吹雪を散らし、端末を震わせる。
  final bool festive;
  final VoidCallback onDone;

  @override
  State<_StreakBurst> createState() => _StreakBurstState();
}

class _StreakBurstState extends State<_StreakBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: _StreakBurst.durationFor(widget.festive),
  )..forward().whenComplete(widget.onDone);

  @override
  void initState() {
    super.initState();
    if (widget.festive) {
      HapticFeedback.heavyImpact();
      Future.delayed(const Duration(milliseconds: 180), () {
        if (mounted) HapticFeedback.mediumImpact();
      });
    }
  }

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
    // 出ている間はタップを受け止め、どこを押してもすぐ閉じる。
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onDone,
      child: Stack(
        children: [
          // 後ろの例文と重ならないよう、画面を少し暗くしてカードを浮かせる。
          Positioned.fill(
            child: FadeTransition(
              opacity: _opacity,
              child: ColoredBox(color: Colors.black.withValues(alpha: 0.3)),
            ),
          ),
          if (widget.festive)
            Positioned.fill(
              child: FadeTransition(
                opacity: _opacity,
                child: ScaleTransition(
                  scale: _scale,
                  child: CustomPaint(painter: _RaysPainter(_c)),
                ),
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
                    padding: const EdgeInsets.fromLTRB(40, 32, 40, 28),
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
                          width: 88,
                          height: 88,
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
                              Icon(look.icon, size: 52, color: look.iconColor),
                        ),
                        const SizedBox(height: 8),
                        Material(
                          color: Colors.transparent,
                          child: Column(
                            children: [
                              // 主役は達成（「1週間 続きました！」）。ほめ言葉は添えるだけ。
                              // 数字だけ大きく、単位（日・週間・か月）は小さく軽くして重さを抜く。
                              // 数字は金のグラデーション（上が明るく下が深い）で、黒字の重さを抜く。
                              ShaderMask(
                                blendMode: BlendMode.srcIn,
                                shaderCallback: (r) => const LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [Color(0xFFD8B46A), _flameDeep],
                                ).createShader(r),
                                child: Text.rich(
                                  TextSpan(children: [
                                    for (final m in RegExp(r'\d+|\D+')
                                        .allMatches(widget.milestone))
                                      TextSpan(
                                        text: m[0],
                                        style: RegExp(r'^\d').hasMatch(m[0]!)
                                            ? const TextStyle(
                                                fontSize: 52,
                                                fontWeight: FontWeight.w600,
                                                letterSpacing: -1,
                                              )
                                            : const TextStyle(
                                                fontSize: 22,
                                                fontWeight: FontWeight.w500,
                                              ),
                                      ),
                                  ]),
                                  style: theme.textTheme.displaySmall
                                      ?.copyWith(height: 1.15),
                                ),
                              ),
                              Text(
                                widget.done,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                  color: cs.onSurface,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                widget.praise,
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w600,
                                  color: cs.onSurface,
                                ),
                              ),
                              Text(
                                widget.praiseMeaning,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontSize: 13,
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
          if (widget.festive)
            Positioned.fill(
              child: CustomPaint(
                painter: _ConfettiPainter(_c, _StreakBurst.durationFor(true)),
              ),
            ),
        ],
      ),
    );
  }
}

/// 節目のカードの後ろで、ゆっくり回る金の光の筋。
class _RaysPainter extends CustomPainter {
  _RaysPainter(this.t) : super(repaint: t);
  final Animation<double> t;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide * 0.75;
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(t.value * math.pi / 3);
    final paint = Paint()
      ..shader = RadialGradient(colors: [
        AppColors.gold.withValues(alpha: 0.55),
        AppColors.gold.withValues(alpha: 0),
      ]).createShader(Rect.fromCircle(center: Offset.zero, radius: r));
    const n = 12;
    for (var i = 0; i < n; i++) {
      final a = i * 2 * math.pi / n;
      final path = Path()
        ..moveTo(0, 0)
        ..lineTo(r * math.cos(a - 0.09), r * math.sin(a - 0.09))
        ..lineTo(r * math.cos(a + 0.09), r * math.sin(a + 0.09))
        ..close();
      canvas.drawPath(path, paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_RaysPainter old) => false;
}

/// 節目に画面中央から打ち上がって落ちる紙吹雪。
class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.t, this.duration) : super(repaint: t);
  final Animation<double> t;
  final Duration duration;

  static const _colors = [
    AppColors.gold,
    Color(0xFFE8CF95),
    _flameDeep,
    AppColors.indigo,
    Color(0xFFFFFFFF),
  ];
  static final _pieces = () {
    final rnd = math.Random(7);
    return [
      for (var i = 0; i < 110; i++)
        (
          // 上向きに広がる角度（真上 ±75°）と初速。
          angle: -math.pi / 2 + (rnd.nextDouble() - 0.5) * math.pi * 0.85,
          speed: 650 + rnd.nextDouble() * 750,
          spin: (rnd.nextDouble() - 0.5) * 14,
          sway: rnd.nextDouble() * math.pi * 2,
          w: 6 + rnd.nextDouble() * 5,
          h: 9 + rnd.nextDouble() * 7,
          color: _colors[i % _colors.length],
          delay: rnd.nextDouble() * 0.12,
        ),
    ];
  }();

  @override
  void paint(Canvas canvas, Size size) {
    final total = duration.inMilliseconds / 1000;
    final origin = size.center(Offset.zero);
    const gravity = 1400.0;
    final paint = Paint();
    for (final p in _pieces) {
      final s = t.value * total - p.delay;
      if (s <= 0) continue;
      // 空気抵抗で横の勢いを落とし、ひらひら揺らす。
      final drag = math.exp(-1.8 * s);
      final vx = p.speed * math.cos(p.angle);
      final vy = p.speed * math.sin(p.angle);
      final x =
          origin.dx + vx * (1 - drag) / 1.8 + math.sin(s * 6 + p.sway) * 14;
      final y =
          origin.dy + vy * (1 - drag) / 1.8 + 0.5 * gravity * s * s * 0.35;
      final fade = (1 - (t.value - 0.8) / 0.2).clamp(0.0, 1.0);
      paint.color = p.color.withValues(alpha: fade);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(p.spin * s);
      // 裏返るように縦幅を伸び縮みさせる。
      final flip = math.cos(s * 9 + p.sway).abs();
      canvas.drawRect(
        Rect.fromCenter(center: Offset.zero, width: p.w, height: p.h * flip),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => false;
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
