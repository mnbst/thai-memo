import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:thai_memo/core/constants/loading_tips.dart';

/// 例文生成中に母音の読み方や文化Tipsを8秒ごとに自動切替＋スワイプで手動切替するウィジェット
class LoadingTipCarousel extends StatefulWidget {
  const LoadingTipCarousel({super.key});

  @override
  State<LoadingTipCarousel> createState() => _LoadingTipCarouselState();
}

class _LoadingTipCarouselState extends State<LoadingTipCarousel> {
  final _random = Random();
  late LoadingTip _currentTip;
  Timer? _timer;
  bool _swipingRight = true;

  @override
  void initState() {
    super.initState();
    _currentTip = _randomTip();
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) {
      _swipingRight = true;
      setState(() => _currentTip = _randomTip());
    });
  }

  void _switchTip({required bool swipeRight}) {
    _swipingRight = swipeRight;
    setState(() => _currentTip = _randomTip());
    _startTimer();
  }

  LoadingTip _randomTip() {
    return LoadingTips.all[_random.nextInt(LoadingTips.all.length)];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isVowel = _currentTip.category == '母音';

    return GestureDetector(
      onHorizontalDragEnd: (details) {
        if (details.primaryVelocity == null) return;
        _switchTip(swipeRight: details.primaryVelocity! < 0);
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
        child: Card(
          key: ValueKey(_currentTip.title),
          margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      isVowel ? Icons.record_voice_over : Icons.temple_buddhist,
                      size: 16,
                      color: isVowel ? theme.colorScheme.primary : theme.colorScheme.secondary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _currentTip.category,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: isVowel ? theme.colorScheme.primary : theme.colorScheme.secondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _currentTip.title,
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  _currentTip.content,
                  style: theme.textTheme.bodySmall,
                ),
                if (_currentTip.example != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    '例: ${_currentTip.example}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
