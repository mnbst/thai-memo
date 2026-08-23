import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thai_memo/services/push_notification_service.dart';

import '../helpers/fake_firebase.dart';

/// 許可状態と getToken の振る舞いだけ差し替えられる最小の FirebaseMessaging。
class _FakeMessaging extends Fake implements FirebaseMessaging {
  _FakeMessaging({
    this.status = AuthorizationStatus.authorized,
    this.token = 'tok-1',
    this.hangsOnGetToken = false,
  });

  AuthorizationStatus status;
  String? token;

  /// iOS で APNs トークンが届かず getToken() が返らない状態の再現。
  bool hangsOnGetToken;

  /// requestPermission に provisional を渡して呼ばれた回数／通常要求の回数。
  int provisionalRequests = 0;
  int prominentRequests = 0;

  /// 要求後に遷移させる許可状態。null なら [status] のまま。
  AuthorizationStatus? statusAfterRequest;

  final _tokenRefresh = StreamController<String>.broadcast();

  @override
  Stream<String> get onTokenRefresh => _tokenRefresh.stream;

  @override
  Future<NotificationSettings> requestPermission({
    bool alert = true,
    bool announcement = false,
    bool badge = true,
    bool carPlay = false,
    bool criticalAlert = false,
    bool provisional = false,
    bool sound = true,
    bool providesAppNotificationSettings = false,
  }) async {
    if (provisional) {
      provisionalRequests++;
    } else {
      prominentRequests++;
    }
    status = statusAfterRequest ??
        (provisional ? AuthorizationStatus.provisional : status);
    return _FakeSettings(status);
  }

  @override
  Future<NotificationSettings> getNotificationSettings() async =>
      _FakeSettings(status);

  @override
  Future<void> setForegroundNotificationPresentationOptions({
    bool alert = false,
    bool badge = false,
    bool sound = false,
  }) async {}

  @override
  Future<String?> getToken({
    String? vapidKey,
    String? serviceWorkerScriptPath,
  }) {
    if (hangsOnGetToken) return Completer<String?>().future;
    return Future.value(token);
  }

  @override
  Future<void> deleteToken() async {}
}

class _FakeSettings extends Fake implements NotificationSettings {
  _FakeSettings(this.authorizationStatus);

  @override
  final AuthorizationStatus authorizationStatus;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeFirestore firestore;
  late FakeFirebaseAuth auth;

  PushNotificationService service(_FakeMessaging messaging) =>
      PushNotificationService(
        messaging: messaging,
        firestore: firestore,
        auth: auth,
        tokenFetchTimeout: const Duration(milliseconds: 50),
      );

  setUp(() {
    firestore = FakeFirestore();
    auth = FakeFirebaseAuth()..user = FakeUser(uid: 'u1', isAnonymous: true);
  });

  test('許可され、トークンも登録できたら enabled', () async {
    final result = await service(_FakeMessaging()).enable();

    expect(result, PushEnableResult.enabled);
    expect(firestore.users['u1']?['fcm_token'], 'tok-1');
    expect(firestore.users['u1']?['daily_reminder_enabled'], true);
  });

  test('OSに拒否されたら denied で、トークンは登録しない', () async {
    final result = await service(
      _FakeMessaging(status: AuthorizationStatus.denied),
    ).enable();

    expect(result, PushEnableResult.denied);
    expect(firestore.users['u1'], isNull);
  });

  test('getToken が返ってこなくても打ち切って pending を返す', () async {
    final result =
        await service(_FakeMessaging(hangsOnGetToken: true)).enable();

    // 許可は取れているので denied にはしない。登録は次回の同期に持ち越す。
    expect(result, PushEnableResult.pending);
    expect(firestore.users['u1'], isNull);
  });

  test('トークンが取れなければ pending', () async {
    final result = await service(_FakeMessaging(token: null)).enable();

    expect(result, PushEnableResult.pending);
    expect(firestore.users['u1'], isNot(contains('fcm_token')));
  });

  test('サインイン前は書き先が無いので enabled にしない', () async {
    auth.user = null;

    final result = await service(_FakeMessaging()).enable();

    expect(result, PushEnableResult.pending);
    expect(firestore.users, isEmpty);
  });

  // 暫定許可の取得はやめたが、過去バージョンで暫定のまま残っている端末は
  // enable() から昇格させる経路をそのまま使う。
  group('過去バージョン由来の暫定許可', () {
    setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.iOS);
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test('暫定許可のまま昇格を断られたら quiet', () async {
      final messaging = _FakeMessaging(status: AuthorizationStatus.provisional)
        ..statusAfterRequest = AuthorizationStatus.provisional;

      expect(await service(messaging).enable(), PushEnableResult.quiet);
      // 配信対象からは外さない。
      expect(firestore.users['u1']?['fcm_token'], 'tok-1');
    });

    test('昇格に応じたら enabled', () async {
      final messaging = _FakeMessaging(status: AuthorizationStatus.provisional)
        ..statusAfterRequest = AuthorizationStatus.authorized;

      expect(await service(messaging).enable(), PushEnableResult.enabled);
    });
  });

}
