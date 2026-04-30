import 'dart:async';
import 'package:flutter/material.dart';
import 'package:thai_memo/core/constants/loading_tips.dart';

/// 例文生成中に母音の読み方や文化Tipsを8秒ごとに自動切替＋スワイプで手動切替するウィジェット
class LoadingTipCarousel extends StatefulWidget {
  const LoadingTipCarousel({super.key});

  @override
  State<LoadingTipCarousel> createState() => _LoadingTipCarouselState();
}

class _LoadingTipCarouselState extends State<LoadingTipCarousel> {
  static List<LoadingTip> _shuffled = List.of(LoadingTips.all)..shuffle();
  static int _index = 0;

  late LoadingTip _currentTip;
  Timer? _timer;
  bool _swipingRight = true;

  @override
  void initState() {
    super.initState();
    _currentTip = _nextTip();
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 14), (_) {
      _swipingRight = true;
      setState(() => _currentTip = _nextTip());
    });
  }

  void _switchTip({required bool swipeRight}) {
    _swipingRight = swipeRight;
    setState(() => _currentTip = _nextTip());
    _startTimer();
  }

  LoadingTip _nextTip() {
    if (_index >= _shuffled.length) {
      _shuffled = List.of(LoadingTips.all)..shuffle();
      _index = 0;
    }
    return _shuffled[_index++];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GestureDetector(
      onHorizontalDragEnd: (details) {
        if (details.primaryVelocity == null) return;
        _switchTip(swipeRight: details.primaryVelocity! > 0);
      },
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 400),
        transitionBuilder: (child, animation) {
          final isEntering = child.key == ValueKey(_currentTip.title);
          final offset = _swipingRight
              ? (isEntering ? const Offset(1, 0) : const Offset(-1, 0))
              : (isEntering ? const Offset(-1, 0) : const Offset(1, 0));
          return SlideTransition(
            position: Tween<Offset>(begin: offset, end: Offset.zero)
                .animate(CurvedAnimation(parent: animation, curve: Curves.easeInOut)),
            child: FadeTransition(opacity: animation, child: child),
          );
        },
        child: Padding(
          key: ValueKey(_currentTip.title),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _currentTip.title,
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                _currentTip.example != null
                    ? '${_currentTip.content}\n例: ${_currentTip.example}'
                    : _currentTip.content,
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
