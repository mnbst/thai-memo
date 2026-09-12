/// 買い切り移行の案内ダイアログのテスト
///
/// 検証する仕様:
/// - 追加料金が無いことと、自動更新を自分で止める必要があることを同じ画面で出す
/// - 「移行する」は true、「あとで」は false を返す
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thai_memo/l10n/app_localizations.dart';
import 'package:thai_memo/presentation/widgets/premium_lifetime_migration_dialog.dart';

/// ダイアログを開き、閉じたあとの戻り値を読む関数を返す。
Future<bool? Function()> _open(WidgetTester tester) async {
  bool? result;
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      locale: const Locale('ja'),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              result = await showPremiumLifetimeMigrationDialog(context);
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return () => result;
}

void main() {
  testWidgets('新設の経緯・無料移行・追加料金なし・解約は本人、を一画面で出す', (tester) async {
    await _open(tester);

    expect(find.text('買い切りプランを新設しました'), findsOneWidget);
    expect(find.textContaining('いまなら無料で'), findsOneWidget);
    expect(find.text('追加のお支払いはありません'), findsOneWidget);
    // 解約が本人任せである点を落とすと、上の一行が嘘になる。
    expect(find.textContaining('ご自身で停止してください'), findsOneWidget);
  });

  testWidgets('「移行する」は true、「あとで」は false を返す', (tester) async {
    var moved = await _open(tester);
    await tester.tap(find.text('買い切りに移行する'));
    await tester.pumpAndSettle();
    expect(moved(), isTrue);

    moved = await _open(tester);
    await tester.tap(find.text('あとで'));
    await tester.pumpAndSettle();
    expect(moved(), isFalse);
  });

  testWidgets('移行するとローディングを挟んで完了ダイアログが出る', (tester) async {
    final completer = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        locale: const Locale('ja'),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showLifetimeMigrationFlow(
                context,
                migrate: () => completer.future,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('買い切りに移行する'));
    await tester.pump();
    await tester.pump();
    expect(find.text('移行しています…'), findsOneWidget);

    completer.complete();
    await tester.pumpAndSettle();
    expect(find.text('移行しています…'), findsNothing);
    expect(find.text('買い切りプランに移行しました'), findsOneWidget);
  });

  testWidgets('移行に失敗したら失敗ダイアログを出す', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        locale: const Locale('ja'),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showLifetimeMigrationFlow(
                context,
                migrate: () => Future<void>.error(StateError('boom')),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('買い切りに移行する'));
    await tester.pumpAndSettle();

    expect(find.text('移行できませんでした'), findsOneWidget);
  });
}
