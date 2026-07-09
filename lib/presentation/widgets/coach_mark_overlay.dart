import 'package:flutter/material.dart';

/// 指定ウィジェットをスポットライトで強調し、吹き出しで機能を教える初回ガイド。
///
/// 使い方: 対象ウィジェットに [GlobalKey] を付け、レイアウト完了後に
/// [CoachMarkOverlay.show] を呼ぶ。表示制御（初回のみ等）は呼び出し側の責務。
class CoachMarkOverlay {
  static OverlayEntry? _entry;

  /// 表示中かどうか。
  static bool get isVisible => _entry != null;

  /// [targetKey] のウィジェットをスポットライト表示する。
  /// 対象が未描画（context/size なし）の場合は何もしない。
  ///
  /// [interactive] が true の場合:
  /// - 全面がタップを無視（下の対象は押せない・背景タップでは閉じない）。
  ///   閉じる操作は吹き出しの「わかった」ボタンのみ。
  /// - 縦スクロールは対象のスクロールへ転送し、スポットも一緒に追従する。
  static void show(
    BuildContext context, {
    required GlobalKey targetKey,
    required String title,
    required String message,
    String buttonLabel = 'わかった',
    IconData icon = Icons.palette_outlined,
    String? stepLabel,
    bool interactive = false,
    VoidCallback? onDismiss,
  }) {
    if (_entry != null) return;

    final overlay = Overlay.of(context);
    final targetCtx = targetKey.currentContext;
    final targetBox = targetCtx?.findRenderObject() as RenderBox?;
    final overlayBox = overlay.context.findRenderObject() as RenderBox?;
    if (targetBox == null || !targetBox.hasSize || overlayBox == null) return;

    final topLeft = targetBox.localToGlobal(Offset.zero, ancestor: overlayBox);
    final rect = topLeft & targetBox.size;

    void dismiss() {
      _entry?.remove();
      _entry = null;
      onDismiss?.call();
    }

    _entry = OverlayEntry(
      builder: (_) => _CoachMarkContent(
        targetKey: targetKey,
        overlayState: overlay,
        initialRect: rect,
        title: title,
        message: message,
        buttonLabel: buttonLabel,
        icon: icon,
        stepLabel: stepLabel,
        interactive: interactive,
        onDismiss: dismiss,
      ),
    );
    overlay.insert(_entry!);
  }

  /// 表示中のコーチマークを即座に閉じる（onDismiss は呼ばない）。
  static void dismiss() {
    _entry?.remove();
    _entry = null;
  }
}

class _CoachMarkContent extends StatefulWidget {
  final GlobalKey targetKey;
  final OverlayState overlayState;
  final Rect initialRect;
  final String title;
  final String message;
  final String buttonLabel;
  final IconData icon;
  final String? stepLabel;
  final bool interactive;
  final VoidCallback onDismiss;

  const _CoachMarkContent({
    required this.targetKey,
    required this.overlayState,
    required this.initialRect,
    required this.title,
    required this.message,
    required this.buttonLabel,
    required this.icon,
    required this.stepLabel,
    required this.interactive,
    required this.onDismiss,
  });

  @override
  State<_CoachMarkContent> createState() => _CoachMarkContentState();
}

class _CoachMarkContentState extends State<_CoachMarkContent>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  )..forward();

  ScrollPosition? _scrollPosition;
  late Rect _targetRect = widget.initialRect;

  @override
  void initState() {
    super.initState();
    if (widget.interactive) {
      final ctx = widget.targetKey.currentContext;
      if (ctx != null) {
        _scrollPosition = Scrollable.maybeOf(ctx)?.position;
        _scrollPosition?.addListener(_onScroll);
      }
    }
  }

  @override
  void dispose() {
    _scrollPosition?.removeListener(_onScroll);
    _controller.dispose();
    super.dispose();
  }

  /// スクロールに合わせてスポット位置を追従させる。
  void _onScroll() {
    if (mounted) setState(() {});
  }

  /// 対象の現在位置を再計算する。取得できない場合は前回値を維持する。
  Rect _currentTargetRect() {
    final targetBox =
        widget.targetKey.currentContext?.findRenderObject() as RenderBox?;
    final overlayBox =
        widget.overlayState.context.findRenderObject() as RenderBox?;
    if (targetBox == null || !targetBox.hasSize || overlayBox == null) {
      return _targetRect;
    }
    final topLeft = targetBox.localToGlobal(Offset.zero, ancestor: overlayBox);
    return topLeft & targetBox.size;
  }

  /// 暗幕上の縦ドラッグを対象のスクロールへ転送する。
  void _forwardScroll(DragUpdateDetails details) {
    final position = _scrollPosition;
    if (position == null) return;
    final next = (position.pixels - details.delta.dy)
        .clamp(position.minScrollExtent, position.maxScrollExtent);
    position.jumpTo(next);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final media = MediaQuery.of(context);
    final size = media.size;

    if (widget.interactive) {
      _targetRect = _currentTargetRect();
    }

    // ハイライト枠（少し余白を持たせる）。
    final hole = _targetRect.inflate(8);

    // 吹き出しは対象の下に置き、画面下端に収まらなければ上に置く。
    const bubbleMargin = 16.0;
    final placeBelow = hole.bottom + 140 < size.height - media.padding.bottom;

    return FadeTransition(
      opacity: CurvedAnimation(parent: _controller, curve: Curves.easeOut),
      child: Stack(
        children: [
          // 暗幕（描画のみ・当たり判定なし）。スポットはくり抜き。
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _SpotlightPainter(
                  hole: hole,
                  color: Colors.black.withValues(alpha: 0.72),
                ),
              ),
            ),
          ),
          // 当たり判定レイヤ（全面）。タップは無視し、interactive のときのみ
          // 縦スクロールを対象へ転送する（スポットは追従するが下の対象は押せない）。
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.interactive ? () {} : widget.onDismiss,
              onVerticalDragUpdate:
                  widget.interactive ? _forwardScroll : null,
            ),
          ),
          // ハイライト枠線。
          Positioned.fromRect(
            rect: hole,
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(hole.height / 2),
                  border: Border.all(color: cs.primary, width: 2),
                ),
              ),
            ),
          ),
          // 吹き出し。
          Positioned(
            left: bubbleMargin,
            right: bubbleMargin,
            top: placeBelow ? hole.bottom + 12 : null,
            bottom: placeBelow ? null : size.height - hole.top + 12,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.94, end: 1.0).animate(
                CurvedAnimation(parent: _controller, curve: Curves.easeOut),
              ),
              alignment:
                  placeBelow ? Alignment.topCenter : Alignment.bottomCenter,
              child: Material(
                color: cs.surface,
                elevation: 8,
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (widget.stepLabel != null) ...[
                        Text(
                          widget.stepLabel!,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: cs.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                      ],
                      Row(
                        children: [
                          Icon(widget.icon, size: 20, color: cs.primary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              widget.title,
                              style: theme.textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        widget.message,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton(
                          onPressed: widget.onDismiss,
                          child: Text(widget.buttonLabel),
                        ),
                      ),
                    ],
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

/// 半透明バリアに角丸の穴をくり抜くペインター。
class _SpotlightPainter extends CustomPainter {
  final Rect hole;
  final Color color;

  const _SpotlightPainter({required this.hole, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final overlay = Path()..addRect(Offset.zero & size);
    final cutout = Path()
      ..addRRect(RRect.fromRectAndRadius(
        hole,
        Radius.circular(hole.height / 2),
      ));
    final path = Path.combine(PathOperation.difference, overlay, cutout);
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_SpotlightPainter old) =>
      old.hole != hole || old.color != color;
}
