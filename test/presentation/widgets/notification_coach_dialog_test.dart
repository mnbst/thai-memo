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

    group('断った人への再案内', () {
      bool reprompt({
        bool? canRequest = true,
        String? version = '1.4.17',
        String? reprompted,
        bool? permissionGranted = false,
      }) =>
          shouldShowNotificationCoach(
            coachShown: true,
            permissionGranted: permissionGranted,
            canRequestPermission: canRequest,
            repromptVersion: version,
            repromptedVersion: reprompted,
          );

      test('このリリースでまだ再案内していなければ出す', () {
        expect(reprompt(), isTrue);
        expect(reprompt(reprompted: '1.4.16'), isTrue);
      });

      test('同じリリースでは二度出さない', () {
        expect(reprompt(reprompted: '1.4.17'), isFalse);
      });

      test('再案内の印が無いリリースでは出さない', () {
        expect(reprompt(version: null), isFalse);
      });

      test('OSで拒否済み・判定不能なら出さない（iOSは再要求できない）', () {
        expect(reprompt(canRequest: false), isFalse);
        expect(reprompt(canRequest: null), isFalse);
      });

      test('OS許可済みなら出さない', () {
        expect(reprompt(permissionGranted: true), isFalse);
      });
    });
  });

  group('assignNotificationRepromptArm', () {
    const exp = 'notif_reprompt_1.4.17';

    test('分析スクリプト（Python）と同じ群になる', () {
      // scripts/notif_reprompt_experiment.py の arm() で計算した値。
      expect(assignNotificationRepromptArm('uid-a', exp),
          NotificationRepromptArm.holdout);
      expect(assignNotificationRepromptArm('uid-b', exp),
          NotificationRepromptArm.show);
      expect(assignNotificationRepromptArm('uid-c', exp),
          NotificationRepromptArm.holdout);
      expect(assignNotificationRepromptArm('uid-d', exp),
          NotificationRepromptArm.show);
    });

    test('おおむね半々に分かれる', () {
      final shown = List.generate(1000, (i) => 'user-$i')
          .where((uid) =>
              assignNotificationRepromptArm(uid, exp) ==
              NotificationRepromptArm.show)
          .length;
      expect(shown, inInclusiveRange(450, 550));
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

      expect(find.text('毎日、例文が通知で届きます'), findsOneWidget);

      // 続けやすい理由の1行と、通知の見た目のプレビュー。
      expect(find.text('同じ時間に届くので、続けやすくなります'), findsOneWidget);
      expect(find.text('ขอบคุณสำหรับกาแฟนะครับ'), findsOneWidget);

      // 主導線でその場でOS許可要求まで進む。設定画面へ辿らせる導線は持たない。
      expect(find.widgetWithText(FilledButton, '通知をオンにする'), findsOneWidget);
      expect(find.widgetWithText(TextButton, '今はしない'), findsOneWidget);
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

      await tester.tap(find.text('今はしない'));
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
