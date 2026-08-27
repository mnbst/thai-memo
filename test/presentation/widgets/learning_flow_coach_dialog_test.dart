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
  testWidgets('1ページ目はくり返しの図、2ページ目は5問クイズの解き方', (tester) async {
    var closed = 0;
    await tester.pumpWidget(_host(onClosed: () => closed += 1));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // 1ページ目。例文 → クイズ のくり返しと、その先の5問クイズ。
    expect(find.text('今後の進め方'), findsOneWidget);
    expect(find.text('例文とクイズをくり返す'), findsOneWidget);
    expect(find.text('例文'), findsNWidgets(2));
    expect(find.text('クイズ'), findsNWidgets(2));
    expect(find.text('5問クイズ'), findsOneWidget);
    expect(find.text('1 / 2'), findsOneWidget);

    await tester.tap(find.text('次へ'));
    await tester.pumpAndSettle();

    // 2ページ目。5問クイズの解き方だけを話す。
    expect(find.text('例文5つごとの5問クイズ'), findsOneWidget);
    expect(
      find.text('タイ文字が読めないうちは「例文を復習する」で確認できます'),
      findsOneWidget,
    );
    expect(
      find.text('語彙スコアを伸ばすには、タイ語だけを見て答えてみましょう'),
      findsOneWidget,
    );
    expect(find.text('2 / 2'), findsOneWidget);
    expect(find.text('次へ'), findsNothing);

    await tester.tap(find.text('はじめる'));
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
