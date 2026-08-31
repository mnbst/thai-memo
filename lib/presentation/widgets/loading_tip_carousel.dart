import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/config/app_config.dart';
import '../../l10n/app_localizations.dart';
import '../../core/constants/loading_tips.dart';

/// 生成待ちの面。待っている画面はどれもこの1枚に揃える。
///
/// 待ち時間の見た目が画面ごとに違うと、同じ「生成中」でも別のことが
/// 起きているように見える。
class LoadingCard extends StatelessWidget {
  const LoadingCard({super.key, required this.message});

  /// 何を待っているか（「例文を準備中…」など）。
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(AppConfig.defaultPadding * 2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(message),
              const SizedBox(height: 24),
              const LoadingTipCarousel(),
            ],
          ),
        ),
      ),
    );
  }
}

/// 例文生成中に母音の読み方や文化Tipsを8秒ごとに自動切替＋スワイプで手動切替するウィジェット
class LoadingTipCarousel extends StatefulWidget {
  const LoadingTipCarousel({super.key});

  @override
  State<LoadingTipCarousel> createState() => _LoadingTipCarouselState();
}

class _LoadingTipCarouselState extends State<LoadingTipCarousel> {
  /// 表示順（Tipsの添字）。文言は言語で変わるので、順番だけを覚えておき
  /// 実際の Tip は build 時に解決する。
  static List<int> _order = _shuffledOrder();
  static int _index = 0;

  static List<int> _shuffledOrder() =>
      List<int>.generate(LoadingTips.count, (i) => i)..shuffle();

  late int _currentTipIndex;
  Timer? _timer;
  bool _swipingRight = true;

  @override
  void initState() {
    super.initState();
    _currentTipIndex = _nextTip();
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
      setState(() => _currentTipIndex = _nextTip());
    });
  }

  void _switchTip({required bool swipeRight}) {
    _swipingRight = swipeRight;
    setState(() => _currentTipIndex = _nextTip());
    _startTimer();
  }

  int _nextTip() {
    if (_index >= _order.length) {
      _order = _shuffledOrder();
      _index = 0;
    }
    return _order[_index++];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentTip = LoadingTips.at(L10n.of(context), _currentTipIndex);

    return GestureDetector(
      onHorizontalDragEnd: (details) {
        if (details.primaryVelocity == null) return;
        _switchTip(swipeRight: details.primaryVelocity! > 0);
      },
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 400),
        transitionBuilder: (child, animation) {
          final isEntering = child.key == ValueKey(currentTip.title);
          final offset = _swipingRight
              ? (isEntering ? const Offset(1, 0) : const Offset(-1, 0))
              : (isEntering ? const Offset(-1, 0) : const Offset(1, 0));
          return SlideTransition(
            position: Tween<Offset>(begin: offset, end: Offset.zero).animate(
                CurvedAnimation(parent: animation, curve: Curves.easeInOut)),
            child: FadeTransition(opacity: animation, child: child),
          );
        },
        child: Padding(
          key: ValueKey(currentTip.title),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                currentTip.title,
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                currentTip.example != null
                    ? L10n.of(context).tipWithExample(
                        currentTip.content, currentTip.example!)
                    : currentTip.content,
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
