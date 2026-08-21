import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:thai_memo/l10n/app_localizations.dart';
import 'package:thai_memo/presentation/widgets/coach_mark_overlay.dart';

import '../../helpers/fake_firebase.dart';

/// コーチマークの対象になるボタンを1つだけ持つ画面。
class _Host extends StatefulWidget {
  const _Host({
    required this.onTargetTap,
    this.analytics,
    this.skippable = false,
    this.barrierDismissible = true,
    this.targetTappable = true,
    this.confirmLabel,
  });

  final VoidCallback onTargetTap;
  final FakeAnalyticsService? analytics;
  final bool skippable;
  final bool barrierDismissible;
  final bool targetTappable;
  final String? confirmLabel;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  final _targetKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: FilledButton(
          key: _targetKey,
          onPressed: widget.onTargetTap,
          child: const Text('対象'),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => CoachMarkOverlay.show(
          context,
          targetKey: _targetKey,
          id: 'target',
          analytics: widget.analytics,
          skippable: widget.skippable,
          barrierDismissible: widget.barrierDismissible,
          targetTappable: widget.targetTappable,
          confirmLabel: widget.confirmLabel,
          title: 'タイトル',
          message: 'メッセージ',
        ),
        child: const Icon(Icons.play_arrow),
      ),
    );
  }
}

Widget _app(
  VoidCallback onTargetTap, {
  FakeAnalyticsService? analytics,
  bool skippable = false,
  bool barrierDismissible = true,
  bool targetTappable = true,
  String? confirmLabel,
}) {
  return MaterialApp(
    localizationsDelegates: const [
      L10n.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: L10n.supportedLocales,
    locale: const Locale('ja'),
    home: _Host(
      onTargetTap: onTargetTap,
      analytics: analytics,
      skippable: skippable,
      barrierDismissible: barrierDismissible,
      targetTappable: targetTappable,
      confirmLabel: confirmLabel,
    ),
  );
}

void main() {
  tearDown(CoachMarkOverlay.dismiss);

  Future<void> showCoach(WidgetTester tester) async {
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('「わかった」ボタンは持たず、一呼吸おいてタップ案内が出る',
      (tester) async {
    await tester.pumpWidget(_app(() {}));
    await showCoach(tester);

    expect(find.text('メッセージ'), findsOneWidget);
    expect(find.text('わかった'), findsNothing);
    // 読ませる前は押す場所を示さない。
    final hint = tester.widget<AnimatedOpacity>(
      find.ancestor(
        of: find.text('光っている場所をタップ'),
        matching: find.byType(AnimatedOpacity),
      ),
    );
    expect(hint.opacity, 0);

    await tester.pump(const Duration(milliseconds: 1500));
    final armedHint = tester.widget<AnimatedOpacity>(
      find.ancestor(
        of: find.text('光っている場所をタップ'),
        matching: find.byType(AnimatedOpacity),
      ),
    );
    expect(armedHint.opacity, 1);
  });

  testWidgets('一呼吸の前は対象を押しても何も起きない', (tester) async {
    var tapped = 0;
    await tester.pumpWidget(_app(() => tapped++));
    await showCoach(tester);

    await tester.tap(find.text('対象'), warnIfMissed: false);
    await tester.pump();

    expect(tapped, 0);
    expect(CoachMarkOverlay.isVisible, isTrue);
  });

  testWidgets('一呼吸の後は対象がそのまま押せて、コーチマークも閉じる',
      (tester) async {
    var tapped = 0;
    await tester.pumpWidget(_app(() => tapped++));
    await showCoach(tester);
    await tester.pump(const Duration(milliseconds: 1500));

    await tester.tap(find.text('対象'));
    await tester.pumpAndSettle();

    expect(tapped, 1);
    expect(CoachMarkOverlay.isVisible, isFalse);
  });

  testWidgets('一呼吸の後は対象の外を押すと閉じる（閉じ込めない）', (tester) async {
    var tapped = 0;
    await tester.pumpWidget(_app(() => tapped++));
    await showCoach(tester);
    await tester.pump(const Duration(milliseconds: 1500));

    await tester.tapAt(const Offset(20, 40));
    await tester.pumpAndSettle();

    expect(tapped, 0);
    expect(CoachMarkOverlay.isVisible, isFalse);
  });

  testWidgets('対象を押して進むと shown → tapped を送る', (tester) async {
    final analytics = FakeAnalyticsService();
    await tester.pumpWidget(_app(() {}, analytics: analytics));
    await showCoach(tester);
    await tester.pump(const Duration(milliseconds: 1500));

    await tester.tap(find.text('対象'));
    await tester.pumpAndSettle();

    expect(analytics.coachMarkEvents, [
      {'id': 'target', 'action': 'shown'},
      {'id': 'target', 'action': 'tapped'},
    ]);
  });

  testWidgets('対象の外を押して抜けると dismissed を送る', (tester) async {
    final analytics = FakeAnalyticsService();
    await tester.pumpWidget(_app(() {}, analytics: analytics));
    await showCoach(tester);
    await tester.pump(const Duration(milliseconds: 1500));

    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();

    expect(
      analytics.coachMarkEvents.map((e) => e['action']),
      ['shown', 'dismissed'],
    );
  });

  testWidgets('押される前に閉じられたら closed を送る', (tester) async {
    final analytics = FakeAnalyticsService();
    await tester.pumpWidget(_app(() {}, analytics: analytics));
    await showCoach(tester);

    CoachMarkOverlay.dismiss();
    await tester.pumpAndSettle();

    expect(
      analytics.coachMarkEvents.map((e) => e['action']),
      ['shown', 'closed'],
    );
  });

  testWidgets('既定ではスキップを出さない', (tester) async {
    await tester.pumpWidget(_app(() {}));
    await showCoach(tester);
    await tester.pump(const Duration(milliseconds: 1500));

    expect(find.text('あとで'), findsNothing);
  });

  testWidgets('skippable なら一呼吸の後にスキップが押せる', (tester) async {
    var tapped = 0;
    final analytics = FakeAnalyticsService();
    await tester.pumpWidget(
      _app(() => tapped++, analytics: analytics, skippable: true),
    );
    await showCoach(tester);

    // 読ませる前は押せない。
    expect(
      tester.widget<TextButton>(find.widgetWithText(TextButton, 'あとで')).onPressed,
      isNull,
    );

    await tester.pump(const Duration(milliseconds: 1500));
    await tester.tap(find.text('あとで'));
    await tester.pumpAndSettle();

    // 対象へは進まず、コーチマークだけ閉じる。
    expect(tapped, 0);
    expect(CoachMarkOverlay.isVisible, isFalse);
    expect(
      analytics.coachMarkEvents.map((e) => e['action']),
      ['shown', 'skipped'],
    );
  });

  testWidgets('barrierDismissible: false は対象の外を押しても閉じない',
      (tester) async {
    var tapped = 0;
    await tester
        .pumpWidget(_app(() => tapped++, barrierDismissible: false));
    await showCoach(tester);
    await tester.pump(const Duration(milliseconds: 1500));

    await tester.tapAt(const Offset(20, 20));
    // 閉じないので settle は使えない（枠の明滅が回り続ける）。
    await tester.pump();
    expect(CoachMarkOverlay.isVisible, isTrue);

    // 対象を押せば進める。
    await tester.tap(find.text('対象'));
    await tester.pumpAndSettle();
    expect(tapped, 1);
    expect(CoachMarkOverlay.isVisible, isFalse);
  });

  testWidgets('confirmLabel 指定時は対象を押させず、ボタンで閉じる',
      (tester) async {
    var tapped = 0;
    final analytics = FakeAnalyticsService();
    await tester.pumpWidget(
      _app(
        () => tapped++,
        analytics: analytics,
        confirmLabel: 'わかった',
        targetTappable: false,
      ),
    );
    await showCoach(tester);
    await tester.pump(const Duration(milliseconds: 1500));

    // 対象は押しても反応しない（カード全体を光らせているだけ）。
    await tester.tap(find.text('対象'), warnIfMissed: false);
    await tester.pump();
    expect(tapped, 0);
    expect(CoachMarkOverlay.isVisible, isTrue);

    await tester.tap(find.text('わかった'));
    await tester.pumpAndSettle();
    expect(CoachMarkOverlay.isVisible, isFalse);
    expect(
      analytics.coachMarkEvents.map((e) => e['action']),
      ['shown', 'confirmed'],
    );
  });

  testWidgets('confirmLabel と対象タップは併用できる', (tester) async {
    var tapped = 0;
    final analytics = FakeAnalyticsService();
    await tester.pumpWidget(
      _app(() => tapped++, analytics: analytics, confirmLabel: 'わかった'),
    );
    await showCoach(tester);
    await tester.pump(const Duration(milliseconds: 1500));

    // 「光っている場所をタップ」の案内も残る。
    expect(find.text('光っている場所をタップ'), findsOneWidget);
    expect(find.text('わかった'), findsOneWidget);

    await tester.tap(find.text('対象'));
    await tester.pumpAndSettle();
    expect(tapped, 1);
    expect(
      analytics.coachMarkEvents.map((e) => e['action']),
      ['shown', 'tapped'],
    );
  });

  testWidgets('画面より高い対象でも吹き出しが画面内に収まる', (tester) async {
    final targetKey = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          L10n.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: L10n.supportedLocales,
        locale: const Locale('ja'),
        home: Builder(
          builder: (context) => Scaffold(
            body: SingleChildScrollView(
              // 画面（600x800）より高いカードを対象にする。
              child: Container(key: targetKey, height: 1600),
            ),
            floatingActionButton: FloatingActionButton(
              onPressed: () => CoachMarkOverlay.show(
                context,
                targetKey: targetKey,
                title: 'タイトル',
                message: 'メッセージ',
                targetTappable: false,
                confirmLabel: 'わかった',
              ),
              child: const Icon(Icons.play_arrow),
            ),
          ),
        ),
      ),
    );
    await showCoach(tester);
    await tester.pump(const Duration(milliseconds: 1500));

    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    final bubble = tester.getRect(find.text('メッセージ'));
    expect(bubble.top, greaterThanOrEqualTo(0));
    expect(bubble.bottom, lessThanOrEqualTo(screen.height));

    // 「わかった」も画面内にあり、押せる。
    final confirm = tester.getRect(find.text('わかった'));
    expect(confirm.bottom, lessThanOrEqualTo(screen.height));
    await tester.tap(find.text('わかった'));
    await tester.pumpAndSettle();
    expect(CoachMarkOverlay.isVisible, isFalse);
  });
}
