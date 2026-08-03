import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thai_memo/presentation/widgets/notification_coach_dialog.dart';

/// ダイアログを開くだけの土台。戻り値を検証するため結果を保持する。
Widget _host({required void Function(bool) onResult}) {
  return MaterialApp(
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
        const MaterialApp(home: Scaffold(body: NotificationCoachDialog())),
      );

      expect(find.text('例文を毎日の習慣に'), findsOneWidget);
      expect(
        find.text('あなたの語彙に合う例文を、毎日お届けします。'),
        findsOneWidget,
      );
      expect(find.text('通知時刻は設定画面で変更できます。'), findsOneWidget);
      expect(find.textContaining('習慣にできます'), findsNothing);
      expect(find.widgetWithText(FilledButton, 'わかった'), findsOneWidget);
      expect(find.text('あとで'), findsNothing);
      expect(find.byIcon(Icons.notifications_none_rounded), findsOneWidget);
    });
  });

  group('showNotificationCoachDialog', () {
    testWidgets('「わかった」で true', (tester) async {
      bool? result;
      await tester.pumpWidget(_host(onResult: (r) => result = r));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('わかった'));
      await tester.pumpAndSettle();

      expect(result, isTrue);
      expect(find.byType(NotificationCoachDialog), findsNothing);
    });

    testWidgets('バリアタップで閉じた場合も false（設定へ案内しない）', (tester) async {
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
