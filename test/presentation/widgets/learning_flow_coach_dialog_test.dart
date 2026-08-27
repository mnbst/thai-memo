import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thai_memo/l10n/app_localizations.dart';
import 'package:thai_memo/presentation/widgets/learning_flow_coach_dialog.dart';

/// ダイアログを開くだけの土台。閉じたことを検証するため結果を保持する。
Widget _host({required VoidCallback onClosed}) {
  return MaterialApp(
    // 実行環境のロケール（en）に引きずられないよう ja を明示する。
    locale: const Locale('ja'),
    localizationsDelegates: L10n.localizationsDelegates,
    supportedLocales: L10n.supportedLocales,
    home: Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            await LearningFlowCoachDialog.show(context);
            onClosed();
          },
          child: const Text('open'),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('くり返しの図だけを1枚で見せる', (tester) async {
    var closed = 0;
    await tester.pumpWidget(_host(onClosed: () => closed += 1));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('今後の進め方'), findsOneWidget);
    expect(find.text('お疲れ様でした。ここまでが一通りの流れです。'), findsOneWidget);
    expect(find.text('例文とクイズをくり返す'), findsOneWidget);
    expect(find.text('例文'), findsNWidgets(2));
    expect(find.text('クイズ'), findsNWidgets(2));
    expect(find.text('5問クイズ'), findsOneWidget);
    // 5問クイズの解き方は解いた直後に出す。ここでは話さない。
    expect(find.text('5問クイズのコツ'), findsNothing);
    expect(find.text('次へ'), findsNothing);

    await tester.tap(find.text('このまま続ける'));
    await tester.pumpAndSettle();

    expect(find.byType(LearningFlowCoachDialog), findsNothing);
    expect(closed, 1);
  });

  testWidgets('barrier では閉じない。最後まで読ませる', (tester) async {
    var closed = 0;
    await tester.pumpWidget(_host(onClosed: () => closed += 1));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(find.byType(LearningFlowCoachDialog), findsOneWidget);
    expect(closed, 0);
  });
}
