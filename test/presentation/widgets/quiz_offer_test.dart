import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thai_memo/l10n/app_localizations.dart';
import 'package:thai_memo/presentation/providers/quiz_offer_experiment_provider.dart';
import 'package:thai_memo/presentation/widgets/quiz_offer.dart';

void main() {
  Future<void> pumpOffer(
    WidgetTester tester, {
    required QuizOfferVariant variant,
    required VoidCallback onPressed,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        // テストは日本語の文言を検証する。実行環境のロケール（en）に
        // 引きずられないよう明示的に ja で描画する。
        locale: const Locale('ja'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: QuizOffer(
            variant: variant,
            targetKey: GlobalKey(),
            onPressed: onPressed,
          ),
        ),
      ),
    );
  }

  testWidgets('control群は既存の確認クイズ導線だけを表示する', (tester) async {
    var taps = 0;
    await pumpOffer(
      tester,
      variant: QuizOfferVariant.controlBottom,
      onPressed: () => taps += 1,
    );

    expect(find.byKey(const ValueKey('quiz_offer_control_v1')), findsOneWidget);
    expect(find.byKey(const ValueKey('quiz_offer_inline_v1')), findsNothing);
    expect(find.text('確認クイズへ'), findsOneWidget);
    expect(find.text('1問だけ確認'), findsNothing);

    await tester.tap(find.text('確認クイズへ'));
    expect(taps, 1);
  });

  testWidgets('inline群は低負荷を伝える1問導線を表示する', (tester) async {
    var taps = 0;
    await pumpOffer(
      tester,
      variant: QuizOfferVariant.inlineOneQuestion,
      onPressed: () => taps += 1,
    );

    expect(find.byKey(const ValueKey('quiz_offer_inline_v1')), findsOneWidget);
    expect(find.byKey(const ValueKey('quiz_offer_control_v1')), findsNothing);
    expect(find.text('1問だけ確認'), findsOneWidget);
    expect(find.text('1問だけやってみる'), findsOneWidget);
    expect(find.text('確認クイズへ'), findsNothing);

    await tester.tap(find.text('1問だけやってみる'));
    expect(taps, 1);
  });
}
