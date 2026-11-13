import 'package:flutter/material.dart';

/// ガイド画面の節を包み、[active] なら開いた直後にその節まで送る。
///
/// コツ問題の解答からガイドを開いたとき、出題元の節を探させないため。
/// 節が画面の上端に来るように送る（alignment 0）。AppBar の直下に詰まって
/// 見えるので、少しだけ上に余白を残す。
class GuideSectionAnchor extends StatefulWidget {
  final bool active;
  final Widget child;

  const GuideSectionAnchor({
    super.key,
    required this.active,
    required this.child,
  });

  @override
  State<GuideSectionAnchor> createState() => _GuideSectionAnchorState();
}

class _GuideSectionAnchorState extends State<GuideSectionAnchor> {
  @override
  void initState() {
    super.initState();
    if (!widget.active) return;
    // 画面遷移のアニメーションと重ねると動きが二重に見えるので、
    // 開き切ってから送る。
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future<void>.delayed(const Duration(milliseconds: 350));
      if (!mounted) return;
      await Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOutCubic,
        alignment: 0.02,
      );
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
