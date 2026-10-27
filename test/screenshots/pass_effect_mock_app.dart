// =============================================================================
// pass_effect_mock_app.dart
// 発音練習の合格演出（80点以上＝合格、90点以上＝タイ人レベル）のアニメーションを、Firebase なしで
// シミュレーターで確かめるモック。例文の詳細画面の発音練習を模して描く。
// 上のボタンで場面を切り替え、マイクか「もう一度」で再生し直す。
//
//   flutter run -t test/screenshots/pass_effect_mock_app.dart
// =============================================================================

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:thai_memo/core/theme/app_colors.dart';
import 'package:thai_memo/core/theme/app_theme.dart';
import 'package:thai_memo/presentation/providers/settings_provider.dart';

void main() => runApp(const _MockApp());

class _MockApp extends StatelessWidget {
  const _MockApp();

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildAppLightTheme(ThaiFont.sarabun),
        home: const _Home(),
      );
}

const _ok = Color(0xFF2E7D32);
const _close = Color(0xFFEF6C00);

/// 称号の配色。true で新案、false で旧案（比較用）。
final _newPalette = ValueNotifier(true);

const _passLine = 80;
const _nativeLine = 90;
const _normal = Duration(milliseconds: 1600);
const _slow = Duration(milliseconds: 6400);

typedef _Word = ({String th, String roman});

const _words = <_Word>[
  (th: 'ร้าน', roman: 'ráan'),
  (th: 'นี้', roman: 'níi'),
  (th: 'อร่อย', roman: 'à-rɔ̀i'),
  (th: 'มาก', roman: 'mâak'),
  (th: 'เลย', roman: 'ləəi'),
  (th: 'นะ', roman: 'ná'),
];

/// 80点以上で「合格」、90点以上で「タイ人レベル」。
enum _Tier { none, pass, native }

enum _Scene { below, pass, nativeFirst, nativeRepeat }

extension on _Scene {
  String get label => switch (this) {
        _Scene.below => '72',
        _Scene.pass => '84 合格',
        _Scene.nativeFirst => '96 初回',
        _Scene.nativeRepeat => '93 2回目',
      };
  int get score => switch (this) {
        _Scene.below => 72,
        _Scene.pass => 84,
        _Scene.nativeFirst => 96,
        _Scene.nativeRepeat => 93,
      };
  _Tier get tier => score >= _nativeLine
      ? _Tier.native
      : score >= _passLine
          ? _Tier.pass
          : _Tier.none;

  /// その段に初めて届いた回。2回目以降は演出を控えめにする。
  bool get first => this != _Scene.nativeRepeat;
  List<Color> get verdicts => switch (this) {
        _Scene.below => const [_ok, _close, _close, _ok, _ok, _ok],
        _Scene.pass => const [_ok, _ok, _close, _ok, _ok, _ok],
        _ => const [_ok, _ok, _ok, _ok, _ok, _ok],
      };
}

class _Home extends StatefulWidget {
  const _Home();

  @override
  State<_Home> createState() => _HomeState();
}

class _HomeState extends State<_Home> with SingleTickerProviderStateMixin {
  // 0〜0.5: リングが伸びる / 0.5〜: 合格の演出（膨らむ・光の粒・称号）
  late final _c = AnimationController(vsync: this, duration: _normal);
  _Scene _scene = _Scene.pass;
  bool _hapticFired = false;

  @override
  void initState() {
    super.initState();
    _c.addListener(() {
      if (!_hapticFired && _scene.tier != _Tier.none && _c.value >= 0.5) {
        _hapticFired = true;
        _scene.tier == _Tier.native
            ? HapticFeedback.mediumImpact()
            : HapticFeedback.lightImpact();
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _play());
  }

  void _play() {
    _hapticFired = false;
    _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        leading: const Icon(Icons.arrow_back_ios_new),
        title: const Text('例文の詳細'),
        centerTitle: true,
        actions: const [
          Icon(Icons.share_outlined),
          SizedBox(width: 16),
          Icon(Icons.favorite_border),
          SizedBox(width: 16),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          _Controls(
            scene: _scene,
            slow: _c.duration == _slow,
            onScene: (s) {
              setState(() => _scene = s);
              _play();
            },
            onReplay: _play,
            onSpeed: () {
              setState(
                  () => _c.duration = _c.duration == _slow ? _normal : _slow);
              _play();
            },
          ),
          const SizedBox(height: 10),
          const _SentenceCard(),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: () {},
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.indigo,
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
                icon: const Icon(Icons.play_arrow),
                label: const Text('お手本を聞く'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _play,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.goldInk,
                  backgroundColor: const Color(0xFFF1E8D6),
                  side: const BorderSide(color: AppColors.gold, width: 1.5),
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
                icon: const Icon(Icons.mic),
                label: const Text('発音練習'),
              ),
            ),
          ]),
          const SizedBox(height: 16),
          Row(children: [
            Icon(Icons.mic_none, size: 18, color: scheme.primary),
            const SizedBox(width: 6),
            Text('発音してみる', style: theme.textTheme.titleMedium),
          ]),
          const SizedBox(height: 10),
          AnimatedBuilder(
            animation: _c,
            builder: (context, _) => _ResultHeader(scene: _scene, t: _c.value),
          ),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final (i, w) in _words.indexed)
              _WordChip(word: w, color: _scene.verdicts[i]),
          ]),
          const SizedBox(height: 10),
          Text('語をタップすると、お手本の聞き比べと直し方が出ます',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

/// モック専用の操作（場面・再生し直し・速度）。本番の画面には無い。
class _Controls extends StatelessWidget {
  const _Controls({
    required this.scene,
    required this.slow,
    required this.onScene,
    required this.onReplay,
    required this.onSpeed,
  });

  final _Scene scene;
  final bool slow;
  final ValueChanged<_Scene> onScene;
  final VoidCallback onReplay;
  final VoidCallback onSpeed;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black26, style: BorderStyle.solid),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(children: [
        SegmentedButton<_Scene>(
          showSelectedIcon: false,
          segments: [
            for (final s in _Scene.values)
              ButtonSegment(value: s, label: Text(s.label)),
          ],
          selected: {scene},
          onSelectionChanged: (v) => onScene(v.first),
        ),
        const SizedBox(height: 6),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          TextButton.icon(
              onPressed: onReplay,
              icon: const Icon(Icons.replay),
              label: const Text('もう一度')),
          ValueListenableBuilder<bool>(
            valueListenable: _newPalette,
            builder: (context, fresh, _) => TextButton.icon(
                onPressed: () {
                  _newPalette.value = !fresh;
                  onReplay();
                },
                icon: const Icon(Icons.palette_outlined),
                label: Text(fresh ? '配色 新' : '配色 旧')),
          ),
          TextButton.icon(
              onPressed: onSpeed,
              icon: const Icon(Icons.slow_motion_video),
              label: Text(slow ? 'スロー 1/4' : '通常速度')),
        ]),
      ]),
    );
  }
}

class _SentenceCard extends StatelessWidget {
  const _SentenceCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const paper = AppColors.paper;
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 22),
      decoration: BoxDecoration(
        color: AppColors.indigo,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(children: const [
              TextSpan(text: 'ร้านนี้'),
              TextSpan(text: 'อร่อย', style: TextStyle(color: AppColors.gold)),
              TextSpan(text: 'มากเลยนะ'),
            ]),
            style: theme.textTheme.headlineMedium?.copyWith(
                color: paper, fontWeight: FontWeight.w700, fontSize: 34),
          ),
          const SizedBox(height: 6),
          Text('ráan níi à-rɔ̀i mâak ləəi ná',
              style: theme.textTheme.bodyLarge?.copyWith(
                  color: paper.withValues(alpha: 0.8),
                  fontStyle: FontStyle.italic)),
          const SizedBox(height: 14),
          Container(height: 1, color: AppColors.gold.withValues(alpha: 0.6)),
          const SizedBox(height: 14),
          Text('このお店、本当においしいね。',
              style: theme.textTheme.bodyLarge?.copyWith(color: paper)),
        ],
      ),
    );
  }
}

double _seg(double t, double begin, double end,
        [Curve curve = Curves.linear]) =>
    curve.transform(((t - begin) / (end - begin)).clamp(0.0, 1.0));

class _ResultHeader extends StatelessWidget {
  const _ResultHeader({required this.scene, required this.t});
  final _Scene scene;
  final double t;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tier = scene.tier;
    final first = scene.first;
    final okCount = scene.verdicts.where((c) => c == _ok).length;
    final closeCount = scene.verdicts.length - okCount;

    // 称号は膨らみの直後に下から出す。
    final badge = _seg(t, 0.55, 0.75, Curves.easeOutBack);
    final sub = _seg(t, 0.7, 0.85);

    return Row(
      children: [
        _Ring(scene: scene, t: t),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (tier != _Tier.none)
                SizedBox(
                  height: 34,
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: Opacity(
                      opacity: badge.clamp(0.0, 1.0),
                      child: Transform.translate(
                        offset: Offset(0, 12 * (1 - badge)),
                        child: _Badge(tier: tier, prominent: first),
                      ),
                    ),
                  ),
                ),
              Text('${scene.verdicts.length}語中 $okCount語が通じた',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              if (tier != _Tier.native) ...[
                Text('「อร่อย」を直そう',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: scheme.onSurfaceVariant)),
                Opacity(
                  opacity: sub,
                  child: Text(
                      tier == _Tier.none
                          ? 'あと${_passLine - scene.score}点で合格'
                          : 'あと${_nativeLine - scene.score}点でタイ人レベル',
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.goldInk,
                          fontWeight: FontWeight.w700)),
                ),
              ] else
                Opacity(
                  opacity: sub,
                  child: Text(
                    first ? 'この例文で初めて90点を超えました' : 'この例文は達成済み',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
              const SizedBox(height: 4),
              Wrap(spacing: 12, children: [
                _Count(color: _ok, label: 'OK', count: okCount),
                if (closeCount > 0)
                  _Count(color: _close, label: '惜しい', count: closeCount),
              ]),
            ],
          ),
        ),
      ],
    );
  }
}

class _Ring extends StatelessWidget {
  const _Ring({required this.scene, required this.t});
  final _Scene scene;
  final double t;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fill = _seg(t, 0, 0.5, Curves.easeOutCubic);
    final shown = scene.score * fill;
    final native = scene.tier == _Tier.native;
    final passed = scene.tier != _Tier.none;
    final first = scene.first;

    // タイ人レベルだけリングを太らせ、金の濃淡で塗る。
    final passT = native ? _seg(t, 0.5, 0.7) : 0.0;
    final stroke = 5.0 + 2.5 * passT;

    // 初めて届いた回だけ膨らむ。合格は小さく、タイ人レベルは大きく光の粒も散らす。
    final pulseT = passed && first ? _seg(t, 0.5, 0.72) : 0.0;
    final scale = 1 + (native ? 0.15 : 0.07) * math.sin(math.pi * pulseT);
    final sparkT = native && first ? _seg(t, 0.5, 0.95, Curves.easeOut) : 0.0;
    final glowPeak =
        native && first ? math.sin(math.pi * _seg(t, 0.5, 0.85)) : 0.0;
    final glowRest = native ? 0.3 * passT : 0.0;
    final glow = math.max(glowPeak * 0.7, glowRest);

    return SizedBox(
      width: 110,
      height: 110,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (sparkT > 0 && sparkT < 1)
            CustomPaint(
                size: const Size(110, 110), painter: _SparklePainter(sparkT)),
          Transform.scale(
            scale: scale,
            child: Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: native
                    ? Color.lerp(Colors.transparent,
                        AppColors.gold.withValues(alpha: 0.06), passT)
                    : null,
                boxShadow: [
                  if (glow > 0)
                    BoxShadow(
                      color: AppColors.gold.withValues(alpha: glow),
                      blurRadius: 10 + 18 * glowPeak,
                      spreadRadius: 2 * glowPeak,
                    ),
                ],
              ),
              child: CustomPaint(
                painter: _RingPainter(
                  progress: shown / 100,
                  stroke: stroke,
                  track: scheme.outlineVariant,
                  color: scheme.tertiary,
                  shine: passT,
                  marker: switch (scene.tier) {
                    _Tier.none => _passLine,
                    _Tier.pass => _nativeLine,
                    _Tier.native => null,
                  },
                ),
                child: Center(
                  child: Text(
                    '${shown.round()}',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      fontSize: 26,
                      color: Color.lerp(
                          scheme.onSurface, AppColors.goldInk, passT),
                      fontFeatures: const [FontFeature.tabularFigures()],
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

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.progress,
    required this.stroke,
    required this.track,
    required this.color,
    required this.shine,
    required this.marker,
  });
  final double progress;
  final double stroke;
  final Color track;
  final Color color;

  /// 0〜1。1 で明るい金→濃い金のグラデーションになる。
  final double shine;

  /// 次の段の点数に目盛りを打つ。タイ人レベルでは打たない。
  final int? marker;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset(stroke / 2, stroke / 2) &
        Size(size.width - stroke, size.height - stroke);
    canvas.drawArc(
        rect,
        0,
        math.pi * 2,
        false,
        Paint()
          ..color = track
          ..strokeWidth = stroke
          ..style = PaintingStyle.stroke);
    final arc = Paint()
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    if (shine > 0) {
      arc.shader = SweepGradient(
        startAngle: -math.pi / 2,
        endAngle: math.pi * 1.5,
        colors: [
          Color.lerp(color, const Color(0xFFF0D58C), shine)!,
          color,
          Color.lerp(color, AppColors.goldInk, shine)!,
        ],
        transform: const GradientRotation(-math.pi / 2),
      ).createShader(rect);
    } else {
      arc.color = color;
    }
    canvas.drawArc(rect, -math.pi / 2, math.pi * 2 * progress, false, arc);
    if (marker case final line?) {
      final a = -math.pi / 2 + math.pi * 2 * line / 100;
      final c = size.center(Offset.zero);
      final r = rect.width / 2;
      final d = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(
          c + d * (r - 6),
          c + d * (r + 6),
          Paint()
            ..color = AppColors.indigo
            ..strokeWidth = 2.5
            ..strokeCap = StrokeCap.round);
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) => true;
}

/// リングの縁から外へ飛んで消える光の粒。
class _SparklePainter extends CustomPainter {
  _SparklePainter(this.t);
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final paint = Paint()
      ..color = AppColors.gold.withValues(alpha: (1 - t).clamp(0.0, 1.0));
    for (var i = 0; i < 10; i++) {
      final a = -math.pi / 2 + i * math.pi / 5 + 0.15;
      final r = 40 + 15 * t + (i.isEven ? 2 : -2);
      final p = c + Offset(math.cos(a), math.sin(a)) * r;
      final s = (i.isEven ? 5.0 : 3.2) * (1 - 0.5 * t);
      final path = Path()
        ..moveTo(p.dx, p.dy - s)
        ..quadraticBezierTo(p.dx, p.dy, p.dx + s, p.dy)
        ..quadraticBezierTo(p.dx, p.dy, p.dx, p.dy + s)
        ..quadraticBezierTo(p.dx, p.dy, p.dx - s, p.dy)
        ..quadraticBezierTo(p.dx, p.dy, p.dx, p.dy - s);
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_SparklePainter old) => old.t != t;
}

/// 称号。合格は翡翠、タイ人レベルは金。初めて届いた回は塗り、2回目以降は線だけ。
class _Badge extends StatelessWidget {
  const _Badge({required this.tier, required this.prominent});
  final _Tier tier;
  final bool prominent;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
        valueListenable: _newPalette,
        builder: (context, fresh, _) =>
            fresh ? _buildNew(context) : _buildOld(context),
      );

  /// 新案。合格は淡い翡翠の面＋線（語チップと違う丸い札・低い背丈）、
  /// タイ人レベルは金の塗りに紺の文字。
  Widget _buildNew(BuildContext context) {
    final native = tier == _Tier.native;
    const jadeInk = Color(0xFF2F6A58);
    const jadeLine = Color(0xFF9DB5A6);
    const jadeFace = Color(0xFFE2E8DF);
    final fg =
        native ? (prominent ? AppColors.indigo : AppColors.goldInk) : jadeInk;
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: native && prominent ? 12 : 10,
          vertical: native && prominent ? 5 : 2),
      decoration: BoxDecoration(
        gradient: prominent && native
            ? const LinearGradient(
                colors: [Color(0xFFD9B86A), AppColors.gold, AppColors.goldInk])
            : null,
        color: prominent && !native ? jadeFace : null,
        border: prominent && native
            ? null
            : Border.all(color: native ? AppColors.gold : jadeLine),
        borderRadius: BorderRadius.circular(999),
        boxShadow: prominent && native
            ? const [
                BoxShadow(
                    color: Color(0x55C39A4E),
                    blurRadius: 10,
                    offset: Offset(0, 3))
              ]
            : null,
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(
            native
                ? Icons.workspace_premium_rounded
                : Icons.check_circle_outline_rounded,
            size: native && prominent ? 18 : 15,
            color: fg),
        const SizedBox(width: 4),
        Text(native ? 'タイ人レベル' : '合格',
            style: (native
                    ? Theme.of(context).textTheme.labelLarge
                    : Theme.of(context).textTheme.labelMedium)
                ?.copyWith(
                    fontWeight: native ? FontWeight.w800 : FontWeight.w700,
                    color: fg,
                    letterSpacing: 0.5)),
      ]),
    );
  }

  /// 旧案（比較用）。合格は翡翠のベタ塗り、タイ人レベルは白文字。
  Widget _buildOld(BuildContext context) {
    final native = tier == _Tier.native;
    final ink = native ? AppColors.goldInk : AppColors.jade;
    final fg = prominent ? Colors.white : ink;
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: prominent ? 12 : 9, vertical: prominent ? 5 : 3),
      decoration: BoxDecoration(
        gradient: prominent && native
            ? const LinearGradient(
                colors: [Color(0xFFD9B86A), AppColors.gold, AppColors.goldInk])
            : null,
        color: prominent && !native ? AppColors.jade : null,
        border: prominent ? null : Border.all(color: ink),
        borderRadius: BorderRadius.circular(999),
        boxShadow: prominent && native
            ? const [
                BoxShadow(
                    color: Color(0x55C39A4E),
                    blurRadius: 10,
                    offset: Offset(0, 3))
              ]
            : null,
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(
            native
                ? Icons.workspace_premium_rounded
                : Icons.check_circle_rounded,
            size: prominent ? 18 : 15,
            color: fg),
        const SizedBox(width: 4),
        Text(native ? 'タイ人レベル' : '合格',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w800, color: fg, letterSpacing: 0.5)),
      ]),
    );
  }
}

class _Count extends StatelessWidget {
  const _Count({required this.color, required this.label, required this.count});
  final Color color;
  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 4),
      Text('$label $count',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant)),
    ]);
  }
}

class _WordChip extends StatelessWidget {
  const _WordChip({required this.word, required this.color});
  final _Word word;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final close = color == _close;
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: close ? const Color(0xFFF6D9C0) : const Color(0xFFE6E8D8),
        border: Border.all(
          color: close ? _close : const Color(0xFFA9C6A0),
          width: close ? 1.5 : 1,
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(word.th, style: theme.textTheme.titleMedium),
          Text(word.roman,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}
