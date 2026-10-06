import 'package:flutter/material.dart';

/// iPad など幅の広い画面では、アプリ全体を縦長の列にして中央に寄せる。
///
/// 画面は iPhone の幅を前提に作ってあり、そのまま横に伸ばすと1行が長すぎて
/// 読めず、カードもまばらになる。MaterialApp.builder で Navigator ごと包むので、
/// 画面遷移・ダイアログ・ボトムシートもすべてこの列の中に出る。
class TabletWidthLimit extends StatelessWidget {
  const TabletWidthLimit({super.key, required this.child});

  /// 列の幅（論理ピクセル）。大きめの iPhone の倍弱で、iPad の縦でも横でも
  /// 左右に余白が残る。
  static const double maxWidth = 680;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    if (media.size.width <= maxWidth) return child;

    final theme = Theme.of(context);
    return ColoredBox(
      color: theme.scaffoldBackgroundColor,
      child: Center(
        child: Container(
          width: maxWidth,
          decoration: BoxDecoration(
            border: Border.symmetric(
              vertical: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
          ),
          // 列の中の画面が MediaQuery の幅でレイアウトを決めても、
          // 端末の幅ではなく列の幅を見るようにする。
          child: MediaQuery(
            data: media.copyWith(size: Size(maxWidth, media.size.height)),
            child: child,
          ),
        ),
      ),
    );
  }
}
