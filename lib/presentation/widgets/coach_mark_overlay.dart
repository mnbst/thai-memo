import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';
import '../../services/analytics_service.dart';

/// 指定ウィジェットをスポットライトで強調し、吹き出しで機能を教える初回ガイド。
///
/// 使い方: 対象ウィジェットに [GlobalKey] を付け、レイアウト完了後に
/// [CoachMarkOverlay.show] を呼ぶ。表示制御（初回のみ等）は呼び出し側の責務。
///
/// 閉じ方は3通り。既定は「対象をタップして進む」で、読む前に押されないよう、
/// 表示から [_armDelay] の間はどこもタップを受け付けない。
///
/// - 既定: 対象をタップすると閉じる。対象の外を押しても閉じる（逃げ道）。
/// - `barrierDismissible: false`: 逃げ道を塞ぎ、対象を押すまで閉じない。
///   その操作をしないと先へ進めない案内（発音練習）で使う。
/// - `confirmLabel` 指定: 「わかった」ボタンで閉じられるようにする。
///   `targetTappable: false` と併せると対象は押させず、ボタンだけになる
///   （対象がカード全体など「押す場所」ではない案内）。
///
/// 対象を押すと別画面へ移る案内（クイズ中に例文へ戻る、まとめクイズを始める）
/// では [skippable] を立てる。案内を読んだうえで「今はやらない」を選べないと、
/// 進行中のクイズを中断させられたのと同じになる。
class CoachMarkOverlay {
  static OverlayEntry? _entry;

  /// 表示中のコーチマークが指しているウィジェット。
  /// 画面ごとの後片付けで、他画面が出したコーチマークまで閉じないための目印。
  static GlobalKey? _ownerKey;

  /// 表示中のコーチマークの識別子と送信先。閉じ方（tapped / dismissed /
  /// closed）は静的な [dismiss] 経由でも決まるので、表示中はここに持つ。
  static String? _visibleId;
  static AnalyticsService? _analytics;

  /// 表示中かどうか。
  static bool get isVisible => _entry != null;

  /// [targetKey] のウィジェットをスポットライト表示する。
  /// 対象が未描画（context/size なし）の場合は何もしない。
  ///
  /// [emphasis] に [message] 内の部分文字列を渡すと、その箇所を太字にする。
  ///
  /// 対象がスクロール内にある場合はスクロールへ追従し、暗幕上の縦ドラッグも
  /// 対象のスクロールへ転送する。
  /// [id] は分析用の識別子。表示・通過・離脱をこの単位で数える。
  /// [analytics] を渡さない場合は計測しない（テスト用）。
  static bool show(
    BuildContext context, {
    required GlobalKey targetKey,
    required String title,
    required String message,
    String? id,
    AnalyticsService? analytics,
    bool skippable = false,
    bool barrierDismissible = true,
    bool targetTappable = true,
    String? confirmLabel,
    String? emphasis,
    IconData icon = Icons.palette_outlined,
    void Function(String action)? onDismiss,
  }) {
    if (_entry != null) return false;

    final overlay = Overlay.of(context);
    final targetCtx = targetKey.currentContext;
    final targetBox = targetCtx?.findRenderObject() as RenderBox?;
    final overlayBox = overlay.context.findRenderObject() as RenderBox?;
    if (targetBox == null || !targetBox.hasSize || overlayBox == null) {
      return false;
    }

    final topLeft = targetBox.localToGlobal(Offset.zero, ancestor: overlayBox);
    final rect = topLeft & targetBox.size;

    void dismissWith(String action) {
      _log(action);
      _entry?.remove();
      _entry = null;
      _ownerKey = null;
      _visibleId = null;
      _analytics = null;
      onDismiss?.call(action);
    }

    _entry = OverlayEntry(
      builder: (_) => _CoachMarkContent(
        targetKey: targetKey,
        overlayState: overlay,
        initialRect: rect,
        title: title,
        message: message,
        emphasis: emphasis,
        icon: icon,
        // 対象を押して進んだのか、対象以外を押して抜けたのかを区別する。
        onTargetTap: targetTappable ? () => dismissWith('tapped') : null,
        onBarrierTap:
            barrierDismissible ? () => dismissWith('dismissed') : null,
        onSkip: skippable ? () => dismissWith('skipped') : null,
        confirmLabel: confirmLabel,
        onConfirm: () => dismissWith('confirmed'),
      ),
    );
    overlay.insert(_entry!);
    _ownerKey = targetKey;
    _visibleId = id;
    _analytics = analytics;
    _log('shown');
    return true;
  }

  static void _log(String action) {
    final id = _visibleId;
    final analytics = _analytics;
    if (id == null || analytics == null) return;
    unawaited(analytics.logCoachMark(id: id, action: action));
  }

  /// 表示中のコーチマークを即座に閉じる（onDismiss は呼ばない）。
  ///
  /// 押される前に画面が閉じられた場合なので `closed` として数える。
  /// 案内が届かないまま prefs の表示済みフラグだけが立つ経路であり、
  /// ここが多いならツアーの出し所がずれている。
  static void dismiss() {
    _log('closed');
    _entry?.remove();
    _entry = null;
    _ownerKey = null;
    _visibleId = null;
    _analytics = null;
  }

  /// [targetKey] を指しているコーチマークだけを閉じる。
  ///
  /// Overlay は Navigator 共有なので、画面の dispose で無条件に [dismiss] すると、
  /// 戻り先の画面が既に出したコーチマークまで消してしまう（表示直後に消えて
  /// ちらついて見える）。後片付けにはこちらを使う。
  static void dismissFor(GlobalKey targetKey) {
    if (_ownerKey == targetKey) dismiss();
  }
}

/// 説明を読ませてから対象を押せるようにするまでの間。
const _armDelay = Duration(milliseconds: 1200);

/// スポットの角丸。ボタンのように低い対象は端を丸め切り、カードのように
/// 高い対象はカード自体の角丸に合わせる。高さの半分で丸めると、縦に長い
/// 対象が円形にえぐられて何を指しているのか分からなくなる。
double _holeRadius(Rect hole) => math.min(hole.shortestSide / 2, 16);

class _CoachMarkContent extends StatefulWidget {
  final GlobalKey targetKey;
  final OverlayState overlayState;
  final Rect initialRect;
  final String title;
  final String message;
  final String? emphasis;
  final IconData icon;


  /// 案内した対象を押したとき。null なら対象は押させない。
  final VoidCallback? onTargetTap;

  /// 対象以外（暗幕）を押して抜けたとき。null なら逃げ道を塞ぐ。
  final VoidCallback? onBarrierTap;

  /// 「わかった」ボタンの文言。null ならボタンを出さない。
  final String? confirmLabel;

  /// 「わかった」を押したとき。
  final VoidCallback onConfirm;

  /// スキップを選んだとき。null ならスキップは出さない。
  final VoidCallback? onSkip;

  const _CoachMarkContent({
    required this.targetKey,
    required this.overlayState,
    required this.initialRect,
    required this.title,
    required this.message,
    required this.emphasis,
    required this.icon,
    required this.onTargetTap,
    required this.onBarrierTap,
    required this.onSkip,
    required this.confirmLabel,
    required this.onConfirm,
  });

  @override
  State<_CoachMarkContent> createState() => _CoachMarkContentState();
}

class _CoachMarkContentState extends State<_CoachMarkContent>
    with TickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  )..forward();

  /// 対象が押せるようになった後の呼吸（枠が明滅して押す場所を示す）。
  late final AnimationController _pulseController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  ScrollPosition? _scrollPosition;
  late Rect _targetRect = widget.initialRect;
  Timer? _armTimer;

  /// 対象タップを受け付ける状態か。表示直後は false。
  bool _armed = false;

  @override
  void initState() {
    super.initState();
    final ctx = widget.targetKey.currentContext;
    if (ctx != null) {
      _scrollPosition = Scrollable.maybeOf(ctx)?.position;
      _scrollPosition?.addListener(_onScroll);
    }
    _armTimer = Timer(_armDelay, () {
      if (!mounted) return;
      setState(() => _armed = true);
      _pulseController.repeat(reverse: true);
    });
  }

  @override
  void dispose() {
    _armTimer?.cancel();
    _scrollPosition?.removeListener(_onScroll);
    _pulseController.dispose();
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

  /// 本文を組み立てる。emphasis が本文に含まれていればそこだけ太字にする。
  TextSpan _messageSpan(TextStyle baseStyle) {
    final emphasis = widget.emphasis;
    final start = emphasis == null ? -1 : widget.message.indexOf(emphasis);
    if (emphasis == null || emphasis.isEmpty || start < 0) {
      return TextSpan(text: widget.message, style: baseStyle);
    }
    final end = start + emphasis.length;
    return TextSpan(
      style: baseStyle,
      children: [
        TextSpan(text: widget.message.substring(0, start)),
        TextSpan(
          text: emphasis,
          // 初回ガイドの体験期間と同じ強調（プライマリ色＋太字）に揃える。
          style: TextStyle(
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.w600,
          ),
        ),
        TextSpan(text: widget.message.substring(end)),
      ],
    );
  }

  /// 暗幕上の縦ドラッグを対象のスクロールへ転送する。
  void _forwardScroll(DragUpdateDetails details) {
    final position = _scrollPosition;
    if (position == null) return;
    final next = (position.pixels - details.delta.dy)
        .clamp(position.minScrollExtent, position.maxScrollExtent);
    position.jumpTo(next);
  }

  /// 穴の外側だけを覆う当たり判定。穴は下の対象へ素通しする。
  ///
  /// 全面を覆うと対象を押せなくなり、穴だけ [IgnorePointer] にすると
  /// 暗幕側のドラッグ転送が効かなくなるので、外周を4枚に分けて敷く。
  Widget _barrier(Rect hole, Size size) {
    Widget piece(double? left, double? top, double? width, double? height) {
      return Positioned(
        left: left ?? 0,
        top: top ?? 0,
        width: width,
        height: height,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          // 読ませる前は何も起きない。押せるようになった後は、対象以外を
          // 押した人が閉じ込められないよう逃げ道にする。
          // その操作をさせたい案内（onBarrierTap が null）では塞ぐ。
          onTap: _armed ? (widget.onBarrierTap ?? () {}) : () {},
          onVerticalDragUpdate: _forwardScroll,
          child: const SizedBox.expand(),
        ),
      );
    }

    return Stack(
      children: [
        piece(0, 0, size.width, hole.top.clamp(0.0, size.height)),
        piece(0, hole.bottom, size.width,
            (size.height - hole.bottom).clamp(0.0, size.height)),
        piece(0, hole.top, hole.left.clamp(0.0, size.width), hole.height),
        piece(hole.right, hole.top,
            (size.width - hole.right).clamp(0.0, size.width), hole.height),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final media = MediaQuery.of(context);
    final size = media.size;

    _targetRect = _currentTargetRect();

    // ハイライト枠（少し余白を持たせる）。
    final hole = _targetRect.inflate(8);

    // 対象が画面より高いことがある（カード全体を指す場合）。吹き出しの
    // 置き場は、画面に見えている範囲を基準に決める。
    final visibleTop = math.max(hole.top, media.padding.top);
    final visibleBottom =
        math.min(hole.bottom, size.height - media.padding.bottom);

    const bubbleMargin = 16.0;
    const bubbleSpace = 160.0;
    final spaceBelow = size.height - media.padding.bottom - visibleBottom;
    final spaceAbove = visibleTop - media.padding.top;

    // 下 → 上 の順に置き場を探し、どちらにも入らなければ画面上端に重ねる。
    // 収まらないまま対象の外へ置くと、吹き出しごと画面の外に出てしまう
    // （スクロールしないと読めない状態になる）。
    final placeBelow = spaceBelow >= bubbleSpace;
    final placeAbove = !placeBelow && spaceAbove >= bubbleSpace;

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
          // 当たり判定は穴の外側だけ。穴の中のタップは対象そのものに届く。
          Positioned.fill(child: _barrier(hole, size)),
          // 穴の中。読ませる前は対象も押させず、押せるようになったら
          // translucent にして対象のタップを通しつつ、押されたら閉じる。
          Positioned.fromRect(
            rect: hole,
            child: _armed && widget.onTargetTap != null
                ? Listener(
                    behavior: HitTestBehavior.translucent,
                    onPointerDown: (_) => widget.onTargetTap!(),
                    child: const SizedBox.expand(),
                  )
                : GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {},
                    onVerticalDragUpdate: _forwardScroll,
                    child: const SizedBox.expand(),
                  ),
          ),
          // ハイライト枠線。押せるようになったら明滅させる。
          Positioned.fromRect(
            rect: hole,
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _pulseController,
                builder: (context, _) {
                  final t = _armed ? _pulseController.value : 0.0;
                  return Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(_holeRadius(hole)),
                      border: Border.all(
                        color: cs.primary,
                        width: 2 + t * 1.5,
                      ),
                      boxShadow: _armed
                          ? [
                              BoxShadow(
                                color: cs.primary.withValues(alpha: 0.3 * t),
                                blurRadius: 8 + t * 12,
                                spreadRadius: t * 4,
                              ),
                            ]
                          : null,
                    ),
                  );
                },
              ),
            ),
          ),
          // 吹き出し。
          Positioned(
            left: bubbleMargin,
            right: bubbleMargin,
            top: placeBelow
                ? visibleBottom + 12
                : (placeAbove ? null : media.padding.top + 12),
            bottom: placeAbove ? size.height - visibleTop + 12 : null,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.94, end: 1.0).animate(
                CurvedAnimation(parent: _controller, curve: Curves.easeOut),
              ),
              alignment:
                  placeAbove ? Alignment.bottomCenter : Alignment.topCenter,
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
                      Text.rich(
                        _messageSpan(
                          theme.textTheme.bodyMedium
                                  ?.copyWith(color: cs.onSurfaceVariant) ??
                              TextStyle(color: cs.onSurfaceVariant),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          // 押す場所の案内は光ってから出す。先に出すと、読む前に
                          // 手が動いてしまう。
                          if (widget.onTargetTap != null)
                            AnimatedOpacity(
                              opacity: _armed ? 1 : 0,
                              duration: const Duration(milliseconds: 300),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.touch_app,
                                      size: 16, color: cs.primary),
                                  const SizedBox(width: 6),
                                  Text(
                                    L10n.of(context).coachTapHere,
                                    style: theme.textTheme.labelLarge?.copyWith(
                                      color: cs.primary,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          // 逃げ道は最初から見せる。遅れて現れると、閉じ方が
                          // ないと思わせたまま読ませることになる。
                          // 押せるのは一呼吸おいてから（誤爆で消さないため）。
                          if (widget.onSkip != null)
                            TextButton(
                              onPressed: _armed ? widget.onSkip : null,
                              child: Text(L10n.of(context).coachSkip),
                            ),
                          const Spacer(),
                          if (widget.confirmLabel != null)
                            AnimatedOpacity(
                              opacity: _armed ? 1 : 0,
                              duration: const Duration(milliseconds: 300),
                              child: FilledButton(
                                onPressed: _armed ? widget.onConfirm : null,
                                child: Text(widget.confirmLabel!),
                              ),
                            ),
                        ],
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
        Radius.circular(_holeRadius(hole)),
      ));
    final path = Path.combine(PathOperation.difference, overlay, cutout);
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_SpotlightPainter old) =>
      old.hole != hole || old.color != color;
}
