import 'package:flutter/material.dart';

/// 右フリックで前の画面に戻す。
///
/// CupertinoPageRoute の戻るジェスチャは左端20px以内からしか始められず、
/// Android のシステムジェスチャとも競合しやすい。画面のどこからでも戻せるよう、
/// 横方向の投げ捨てを拾って pop する。縦スクロールとは方向が違うので競合しない。
///
/// ルート側も CupertinoPageRoute にしておくと、左端からのドラッグでは
/// 追従するアニメーションで戻れる（こちらはその補助）。
class SwipeBack extends StatelessWidget {
  const SwipeBack({super.key, required this.child});

  final Widget child;

  /// これ以上の速さで右に振ったら戻す（px/秒）
  static const double _velocityThreshold = 300;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onHorizontalDragEnd: (details) {
        final velocity = details.primaryVelocity;
        if (velocity != null && velocity > _velocityThreshold) {
          Navigator.maybePop(context);
        }
      },
      child: child,
    );
  }
}
