import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thai_memo/l10n/app_localizations.dart';
import 'package:thai_memo/presentation/widgets/notification_coach_dialog.dart';

/// ダイアログを開くだけの土台。戻り値を検証するため結果を保持する。
Widget _host({required void Function(bool) onResult}) {
  return MaterialApp(
    // テストは日本語の文言を検証する。実行環境のロケール（en）に
    // 引きずられないよう明示的に ja で描画する。
    locale: const Locale('ja'),
    localizationsDelegates: L10n.localizationsDelegates,
    supportedLocales: L10n.supportedLocales,
    home: Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () async =>
              onResult(await showNotificationCoachDialog(context)),
          child: const Text('open'),
        ),
      ),
    ),
  );
}

void main() {
  group('shouldShowNotificationCoach', () {
    test('表示済みなら出さない', () {
      expect(
        shouldShowNotificationCoach(coachShown: true, permissionGranted: false),
        isFalse,
      );
      expect(
        shouldShowNotificationCoach(coachShown: true, permissionGranted: true),
        isFalse,
      );
    });

    test('既にOS許可済みなら出さない', () {
      expect(
        shouldShowNotificationCoach(coachShown: false, permissionGranted: true),
        isFalse,
      );
    });

    test('許可状態が判定不能なら出さない（既読にもしないので次の機会に回る）', () {
      expect(
        shouldShowNotificationCoach(coachShown: false, permissionGranted: null),
        isFalse,
      );
    });

    test('未表示かつ未許可のときだけ出す', () {
      expect(
        shouldShowNotificationCoach(
            coachShown: false, permissionGranted: false),
        isTrue,
      );
    });
  });

  group('NotificationCoachDialog', () {
    testWidgets('通知の価値と操作を提示する', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ja'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: const Scaffold(body: NotificationCoachDialog()),
        ),
      );

      expect(find.text('通知でタイ語学習を習慣にしましょう'), findsOneWidget);

      // 「時刻を決める → その時刻に届く」の順序が読める形で並んでいること。
      // 文言そのものより、この2段構成が崩れていないことを見る。
      expect(find.text('1'), findsOneWidget);
      expect(find.textContaining('時刻を決めます'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.textContaining('自動で届きます'), findsOneWidget);

      // 習慣化の理由づけと、通知の見た目のプレビュー。
      expect(find.textContaining('無理なく続けられます'), findsOneWidget);
      expect(find.text('通知の例）'), findsOneWidget);

      // 主導線でその場でOS許可要求まで進む。設定画面へ辿らせる導線は持たない。
      expect(find.widgetWithText(FilledButton, '通知をオンにする'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'あとで'), findsOneWidget);
      expect(find.byIcon(Icons.notifications_none_rounded), findsOneWidget);
    });

  });

  group('showNotificationCoachDialog', () {
    testWidgets('「通知をオンにする」で true', (tester) async {
      bool? result;
      await tester.pumpWidget(_host(onResult: (r) => result = r));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('通知をオンにする'));
      await tester.pumpAndSettle();

      expect(result, isTrue);
      expect(find.byType(NotificationCoachDialog), findsNothing);
    });

    testWidgets('「あとで」で false（許可要求を出さない）', (tester) async {
      bool? result;
      await tester.pumpWidget(_host(onResult: (r) => result = r));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('あとで'));
      await tester.pumpAndSettle();

      expect(result, isFalse);
      expect(find.byType(NotificationCoachDialog), findsNothing);
    });

    testWidgets('バリアタップで閉じた場合も false（許可要求を出さない）', (tester) async {
      bool? result;
      await tester.pumpWidget(_host(onResult: (r) => result = r));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // ダイアログ外（バリア）をタップ
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(result, isFalse);
      expect(find.byType(NotificationCoachDialog), findsNothing);
    });
  });
}
