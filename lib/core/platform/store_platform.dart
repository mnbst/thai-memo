import 'package:flutter/foundation.dart';

/// Android のパッケージ名。tester は別アプリ（android/app/build.gradle と揃える）。
const String _androidPackageName = String.fromEnvironment('ENV') == 'tester'
    ? 'com.thaimemo.thai_memo.test'
    : 'com.thaimemo.thai_memo';

/// アプリを配布しているストア。iOS と Android で違う振る舞いはここに集める。
///
/// 画面やサービスで `Platform.isIOS` を個別に見ると、片方だけ直す漏れが起きる。
/// 分岐が要るときはこの enum のプロパティを足し、呼び出し側は値を引くだけにする。
/// 判定は [defaultTargetPlatform] で行う（テストで差し替えられるように）。
enum StorePlatform {
  appStore(
    id: 'ios',
    subscriptionsUrl: 'https://apps.apple.com/account/subscriptions',
  ),
  googlePlay(
    id: 'android',
    subscriptionsUrl: 'https://play.google.com/store/account/subscriptions'
        '?package=$_androidPackageName',
  );

  const StorePlatform({required this.id, required this.subscriptionsUrl});

  /// サーバー（verifySubscription）と Firestore の subscription.platform に
  /// 入る値。ARB の select（`{store, select, android{…} other{…}}`）にも渡す。
  final String id;

  /// 購読の管理画面（解約・プラン変更）。アプリから直接開ける。
  final String subscriptionsUrl;

  /// Apple でのサインインを出すか。Android は Google のみ。
  bool get supportsAppleSignIn => this == appStore;

  /// いま動いている端末のストア。Web など対象外では App Store 扱い。
  static StorePlatform get current =>
      defaultTargetPlatform == TargetPlatform.android ? googlePlay : appStore;

  /// Firestore の subscription.platform から引く。不明なら null。
  static StorePlatform? fromId(Object? id) {
    for (final store in values) {
      if (store.id == id) return store;
    }
    return null;
  }
}
