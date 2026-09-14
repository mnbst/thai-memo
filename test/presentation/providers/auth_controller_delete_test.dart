import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thai_memo/l10n/app_localizations.dart';
import 'package:thai_memo/presentation/providers/auth_provider.dart';
import 'package:thai_memo/services/firebase_auth_service.dart';

class _Auth extends Fake implements FirebaseAuthService {
  Future<void> Function()? delete;
  Future<void> Function()? logout;
  Future<User?> Function()? googleLink;
  User? user;
  @override
  User? get currentUser => user;
  @override
  String? get displayName => null;
  @override
  String? get email => null;
  @override
  bool get isLinkedAccount => true;
  @override
  Future<void> deleteAccount() => delete!();
  @override
  Future<void> signOut() => logout!();
  @override
  Future<User?> linkWithGoogle() => googleLink!();
}

class _User extends Fake implements User {
  _User(this.uid);
  @override
  final String uid;
}

void main() {
  test('再認証のキャンセル・削除失敗では端末データを消さない', () async {
    for (final reason in ['canceled', 'network-request-failed']) {
      var cleared = false;
      final auth = _Auth()
        ..delete = () async {
          throw FirebaseAuthServiceException(reason);
        };
      final controller = AuthController(
        auth,
        () => lookupL10n(const Locale('ja')),
        clearLocalData: () async {
          cleared = true;
        },
      );
      expect(await controller.deleteAccount(), isNotNull);
      expect(cleared, isFalse);
      expect(controller.state.isLoading, isFalse);
      controller.dispose();
    }
  });

  test('削除成功後に掃除し、掃除完了まで処理中を維持する', () async {
    final deleted = Completer<void>();
    final cleaned = Completer<void>();
    var clearing = false;
    final auth = _Auth()..delete = () => deleted.future;
    final controller = AuthController(
      auth,
      () => lookupL10n(const Locale('ja')),
      clearLocalData: () async {
        clearing = true;
        await cleaned.future;
      },
    );
    addTearDown(controller.dispose);
    final operation = controller.deleteAccount();
    expect(clearing, isFalse);
    deleted.complete();
    await Future<void>.delayed(Duration.zero);
    expect(clearing, isTrue);
    expect(controller.state.isLoading, isTrue);
    cleaned.complete();
    expect(await operation, isNull);
    expect(controller.state.isLoading, isFalse);
  });

  test('サインアウト完了後に元ユーザーの端末学習データを消す', () async {
    final signedOut = Completer<void>();
    final cleaned = Completer<void>();
    String? clearedUid;
    final auth = _Auth()..user = _User('user-1');
    auth.logout = () async {
      await signedOut.future;
      auth.user = null;
    };
    final controller = AuthController(
      auth,
      () => lookupL10n(const Locale('ja')),
      clearLocalData: () async {},
      clearUserLocalData: (uid) async {
        clearedUid = uid;
        await cleaned.future;
      },
    );
    addTearDown(controller.dispose);

    final operation = controller.signOut();
    expect(clearedUid, isNull);
    signedOut.complete();
    await Future<void>.delayed(Duration.zero);
    expect(clearedUid, 'user-1');
    expect(controller.state.isLoading, isTrue);
    cleaned.complete();
    expect(await operation, isNull);
    expect(controller.state.isLoading, isFalse);
  });

  test('リンクが既存アカウントへの切替になった場合は匿名ユーザーのデータを消す', () async {
    String? clearedUid;
    final auth = _Auth()..user = _User('anonymous-1');
    auth.googleLink = () async {
      auth.user = _User('existing-1');
      return auth.user;
    };
    final controller = AuthController(
      auth,
      () => lookupL10n(const Locale('ja')),
      clearLocalData: () async {},
      clearUserLocalData: (uid) async => clearedUid = uid,
    );
    addTearDown(controller.dispose);

    expect(await controller.linkWithGoogle(), isNull);
    expect(clearedUid, 'anonymous-1');
  });
}
