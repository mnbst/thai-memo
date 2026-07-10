/// FirebaseAuthService.authenticateWithCredential のテスト
///
/// 匿名ユーザーのサインイン（アカウントリンク＝昇格）の分岐を検証する:
/// - 匿名 + link=true → linkWithCredential（uid・データ保持）
/// - 既にそのアカウントが存在 → signInWithCredential にフォールバック（既存uidへ）
/// - 非匿名 / link=false → 通常サインイン
library;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thai_memo/services/firebase_auth_service.dart';

import '../helpers/fake_firebase.dart';

void main() {
  late FakeFirebaseAuth auth;
  final service = FirebaseAuthService.instance;
  final credential = GoogleAuthProvider.credential(idToken: 'dummy-token');

  setUp(() {
    auth = FakeFirebaseAuth();
    FirebaseAuthService.authOverride = auth;
  });

  tearDown(() {
    FirebaseAuthService.authOverride = null;
  });

  test('匿名ユーザー + link=true はリンク（昇格）され、uidが保持される', () async {
    final anon = FakeUser(uid: 'anon-uid', isAnonymous: true);
    var signInCalled = false;
    anon.onLinkWithCredential = (_) async {
      final linked = FakeUser(uid: 'anon-uid', isAnonymous: false);
      auth.user = linked;
      return FakeUserCredential(linked);
    };
    auth.user = anon;
    auth.onSignInWithCredential = (_) async {
      signInCalled = true;
      fail('link時はsignInWithCredentialを呼ばない');
    };

    final user =
        await service.authenticateWithCredential(credential, link: true);

    expect(user!.uid, 'anon-uid');
    expect(user.isAnonymous, isFalse);
    expect(signInCalled, isFalse);
  });

  test('リンク先アカウントが既存の場合は既存アカウントへサインインする（匿名uidは破棄）', () async {
    final anon = FakeUser(uid: 'anon-uid', isAnonymous: true)
      ..onLinkWithCredential = (_) async {
        throw FirebaseAuthException(code: 'credential-already-in-use');
      };
    auth.user = anon;
    auth.onSignInWithCredential = (_) async {
      final existing = FakeUser(uid: 'existing-uid', isAnonymous: false);
      auth.user = existing;
      return FakeUserCredential(existing);
    };

    final user =
        await service.authenticateWithCredential(credential, link: true);

    expect(user!.uid, 'existing-uid');
  });

  test('リンク失敗時のフォールバックは例外に含まれる credential を優先して使う', () async {
    // Apple の credential は nonce が一回限りで、link 試行で消費済みの
    // credential を再利用するとサインインに失敗する。Firebase が例外に
    // 詰めて返す再利用可能な credential を使うことを検証する。
    final updatedCredential =
        GoogleAuthProvider.credential(idToken: 'updated-token');
    final anon = FakeUser(uid: 'anon-uid', isAnonymous: true)
      ..onLinkWithCredential = (_) async {
        throw FirebaseAuthException(
          code: 'credential-already-in-use',
          credential: updatedCredential,
        );
      };
    auth.user = anon;
    AuthCredential? usedCredential;
    auth.onSignInWithCredential = (c) async {
      usedCredential = c;
      final existing = FakeUser(uid: 'existing-uid', isAnonymous: false);
      auth.user = existing;
      return FakeUserCredential(existing);
    };

    final user =
        await service.authenticateWithCredential(credential, link: true);

    expect(user!.uid, 'existing-uid');
    expect(usedCredential, same(updatedCredential));
  });

  test('非匿名ユーザーは link=true でも通常サインインになる', () async {
    auth.user = FakeUser(uid: 'signed-uid', isAnonymous: false);
    auth.onSignInWithCredential = (_) async {
      final user = FakeUser(uid: 'other-uid', isAnonymous: false);
      auth.user = user;
      return FakeUserCredential(user);
    };

    final user =
        await service.authenticateWithCredential(credential, link: true);

    expect(user!.uid, 'other-uid');
  });

  test('link=false は匿名ユーザーでも通常サインインになる', () async {
    final anon = FakeUser(uid: 'anon-uid', isAnonymous: true)
      ..onLinkWithCredential = (_) async {
        fail('link=false時はlinkWithCredentialを呼ばない');
      };
    auth.user = anon;
    auth.onSignInWithCredential = (_) async {
      final user = FakeUser(uid: 'existing-uid', isAnonymous: false);
      auth.user = user;
      return FakeUserCredential(user);
    };

    final user =
        await service.authenticateWithCredential(credential, link: false);

    expect(user!.uid, 'existing-uid');
  });

  test('想定外の認証エラーは FirebaseAuthServiceException になる', () async {
    auth.user = FakeUser(uid: 'anon-uid', isAnonymous: true)
      ..onLinkWithCredential = (_) async {
        throw FirebaseAuthException(code: 'network-request-failed');
      };

    expect(
      () => service.authenticateWithCredential(credential, link: true),
      throwsA(isA<FirebaseAuthServiceException>()),
    );
  });
}
