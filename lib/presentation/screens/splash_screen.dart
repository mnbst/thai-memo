import 'dart:ui';

import 'package:flutter/material.dart';

class SplashScreen extends StatefulWidget {
  final Widget child;

  const SplashScreen({super.key, required this.child});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _blurAnimation;
  late final Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    // blur: 20 → 0
    _blurAnimation = Tween<double>(begin: 20, end: 0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.7, curve: Curves.easeOut),
      ),
    );

    // opacity: 1 → 0 (スプラッシュをフェードアウト)
    _opacityAnimation = Tween<double>(begin: 1, end: 0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.6, 1.0, curve: Curves.easeIn),
      ),
    );

    // 少し待ってからアニメーション開始
    Future.delayed(const Duration(milliseconds: 500), () {
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
            return Opacity(
              opacity: _opacityAnimation.value,
              child: Container(
                color: Theme.of(context).scaffoldBackgroundColor,
                child: Center(
                  child: ImageFiltered(
                    imageFilter: ImageFilter.blur(
                      sigmaX: _blurAnimation.value,
                      sigmaY: _blurAnimation.value,
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(36),
                      child: Image.asset(
                        'static/appicon.png',
                        width: 160,
                        height: 160,
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
