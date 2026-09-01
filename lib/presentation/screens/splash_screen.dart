import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_colors.dart';

/// ネイティブ起動画面（brandBlue + 160pt のアイコン）と完全に同じ絵。
/// Flutter の最初のフレームがこれを描くことで、OS 側からの引き継ぎが見えなくなる。
class SplashVisual extends StatelessWidget {
  final double iconOpacity;

  const SplashVisual({super.key, this.iconOpacity = 1});

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: ColoredBox(
        color: AppColors.brandBlue,
        child: Center(
          child: Opacity(
            opacity: iconOpacity,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(36),
              child: Image.asset('assets/appicon.png', width: 160, height: 160),
            ),
          ),
        ),
      ),
    );
  }
}

/// 起動時のちらつきを消すためのスプラッシュ。
///
/// ネイティブ起動画面と同じ絵を最初のフレームから出し、
/// アイコン → 青一色 → アプリ本体の順に一方向へ溶かす。
/// 色を戻したり途中で別の画面を挟んだりしない（＝チカチカしない）。
class SplashScreen extends StatefulWidget {
  final Widget child;

  const SplashScreen({super.key, required this.child});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _iconOpacity;
  late final Animation<double> _veilOpacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 900),
      vsync: this,
    );

    // アイコンが先に消え、そのあと青いベールが本体へ溶ける。
    _iconOpacity = Tween<double>(begin: 1, end: 0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.4, curve: Curves.easeIn),
      ),
    );
    _veilOpacity = Tween<double>(begin: 1, end: 0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.35, 1.0, curve: Curves.easeInOut),
      ),
    );

    // 最初のフレームを描いてから開始する。遅延は入れない。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            if (_controller.isCompleted) return const SizedBox.shrink();
            return IgnorePointer(
              child: Opacity(
                opacity: _veilOpacity.value,
                child: SplashVisual(iconOpacity: _iconOpacity.value),
              ),
            );
          },
        ),
      ],
    );
  }
}
