import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:thai_memo/services/anonymous_sign_in_coordinator.dart';

void main() {
  testWidgets('重複起動せず、ログアウト後には再び匿名認証する', (tester) async {
    var authenticated = false;
    var calls = 0;
    final gate = Completer<void>();
    final coordinator = AnonymousSignInCoordinator(
      canSignIn: () => !authenticated,
      signIn: () async {
        calls++;
        await gate.future;
        authenticated = true;
      },
    );
    addTearDown(coordinator.dispose);
    coordinator.ensureSignedIn();
    coordinator.ensureSignedIn();
    expect(calls, 1);
    gate.complete();
    await tester.pump();
    authenticated = false;
    coordinator.ensureSignedIn();
    await tester.pump();
    expect(calls, 2);
    expect(authenticated, isTrue);
  });

  testWidgets('失敗は待って再試行し、掃除中は匿名ユーザーを作らない', (tester) async {
    var cleaning = true;
    var authenticated = false;
    var calls = 0;
    final coordinator = AnonymousSignInCoordinator(
      canSignIn: () => !cleaning && !authenticated,
      signIn: () async {
        calls++;
        if (calls == 1) throw StateError('offline');
        authenticated = true;
      },
    );
    addTearDown(coordinator.dispose);
    coordinator.ensureSignedIn();
    expect(calls, 0);
    cleaning = false;
    coordinator.ensureSignedIn();
    await tester.pump();
    coordinator.ensureSignedIn();
    expect(calls, 1);
    await tester.pump(const Duration(seconds: 3));
    expect(calls, 2);
    expect(authenticated, isTrue);
  });

  testWidgets('破棄した後は再試行しない', (tester) async {
    var calls = 0;
    final coordinator = AnonymousSignInCoordinator(
      canSignIn: () => true,
      signIn: () async {
        calls++;
        throw StateError('offline');
      },
    );
    coordinator.ensureSignedIn();
    await tester.pump();
    coordinator.dispose();
    await tester.pump(const Duration(seconds: 6));
    expect(calls, 1);
  });
}
