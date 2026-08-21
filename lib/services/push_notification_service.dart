// =============================================================================
// push_notification_service.dart
// 毎日例文のプッシュ通知（FCM）まわり。
//
// サーバー（deliverDailySentence）が配信対象を選ぶのに必要なフィールドを
// users/{uid} に書く役割を持つ:
//   fcm_token                 … 送信先。これが無いユーザーには配信されない
//   timezone                  … IANA名。ローカル時刻の判定に使う
//   preferred_generation_hour … 配信希望時刻（時のみ）
//   notify_utc_hour           … 上記2つから導く配信対象クエリ用の絞り込みキー
//
// 通知本文は例文そのものだが、表示はペイロードではなく Firestore から行う
// （DailySentenceService）。通知を開かなくても例文が手元に揃うようにするため。
// =============================================================================

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_timezone/flutter_timezone.dart';

/// 配信希望時刻のデフォルト（ユーザーのローカル10時）
const int kDefaultGenerationHour = 10;

/// タイムゾーンが取得できなかった場合のフォールバック
const String kFallbackTimezone = 'Asia/Tokyo';

/// 送信先トークンの取得を諦めるまでの時間。
///
/// iOS の getToken() は APNs トークンが端末に届くまで返らない。上限を置かないと
/// 許可した直後の呼び出しが返らず、トグルが結果を待ったまま固まる。
const Duration kTokenFetchTimeout = Duration(seconds: 10);

/// [PushNotificationService.enable] の結果。
enum PushEnableResult {
  /// 許可が得られ、送信先トークンも登録できた。配信対象に入っている。
  enabled,

  /// OS に拒否された。iOS ではアプリから再要求できないため、案内するしかない。
  denied,

  /// 許可は得られたが、トークンを登録できないまま時間切れになった。
  ///
  /// 許可自体は残るのでアプリ内設定はオンのままにする。登録は
  /// onTokenRefresh か次回起動の [PushNotificationService.sync] で完了する。
  pending,

  /// 暫定許可のまま昇格を断られた。通知は届くが音もバナーも出ない。
  ///
  /// 配信対象ではあるのでオフには戻さない。
  quiet,
}

/// 現地の [preferredHour] が UTC の何時の起動に当たるかを返す。
///
/// 配信バッチ（deliverDailySentence）は毎時起動し、users を
/// notify_utc_hour == 現在のUTC時 で絞り込む。全件走査を避けるための
/// 非正規化フィールドで、設定変更を即座に反映させるためクライアントでも書く。
/// （サーバー側は dailyBatch が毎日全ユーザー分を書き直す）
///
/// オフセットの引き算ではなく24通りを実際にローカル変換して探すため、
/// +5:30 / +5:45 のような分単位オフセットや DST でも正しい値になる。
/// その現地時刻が存在しない日（DST春の切り替え）は null を返す。
int? notifyUtcHour(int preferredHour, {DateTime? base}) {
  final now = (base ?? DateTime.now()).toUtc();
  for (var utcHour = 0; utcHour < 24; utcHour++) {
    final candidate = DateTime.utc(now.year, now.month, now.day, utcHour);
    if (candidate.toLocal().hour == preferredHour) return utcHour;
  }
  return null;
}

class PushNotificationService {
  PushNotificationService({
    FirebaseMessaging? messaging,
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    Duration tokenFetchTimeout = kTokenFetchTimeout,
  })  : _messaging = messaging ?? FirebaseMessaging.instance,
        _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance,
        _tokenFetchTimeout = tokenFetchTimeout;

  final FirebaseMessaging _messaging;
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  /// トークン取得の打ち切り時間。テストから短くするためだけの seam。
  final Duration _tokenFetchTimeout;

  StreamSubscription<String>? _tokenRefreshSubscription;
  bool _registrationEnabled = false;

  DocumentReference<Map<String, dynamic>>? get _userDoc {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return null;
    return _firestore.collection('users').doc(uid);
  }

  /// アプリ起動時に呼ぶ。アプリ内設定とOSの許可状態を突き合わせて登録を整える。
  ///
  /// ここでは許可ダイアログを出さない。iOSの許可ダイアログは一度拒否されると
  /// アプリからは二度と出せないため、価値が伝わる前に出すと配信対象から恒久的に
  /// 外れてしまう。要求は設定画面のコーチングダイアログ経由（[enable]）に一本化し、
  /// 未許可（notDetermined）のままなら通知はオフとして扱う。
  /// OSの設定で後から通知を切られた場合はトークンを消す。
  ///
  /// 実際に通知を受け取れる状態かを返す。false のとき呼び出し側はアプリ内設定を
  /// オフに戻し、UIとOSの状態が食い違わないようにする。
  Future<bool> sync({required bool desiredEnabled}) async {
    _tokenRefreshSubscription ??= _messaging.onTokenRefresh.listen(_saveToken);

    try {
      if (!desiredEnabled) {
        await _disableRegistration(deleteDeviceToken: false);
        return false;
      }

      final settings = await _messaging.getNotificationSettings();
      if (_isGranted(settings)) {
        await _enableRegistration();
        return true;
      }
      await _disableRegistration(deleteDeviceToken: false);
      return false;
    } catch (_) {
      // 通信・プラットフォーム側の失敗は次回起動で回復する。
      // ここで false を返すとユーザー設定を勝手にオフにしてしまうため維持する。
      return desiredEnabled;
    }
  }

  bool _isGranted(NotificationSettings settings) =>
      settings.authorizationStatus == AuthorizationStatus.authorized ||
      settings.authorizationStatus == AuthorizationStatus.provisional;

  /// OSの通知許可が既に得られているか。ダイアログは出さない。
  ///
  /// 暫定許可（provisional）も「得られている」に含む。配信対象に入れるか
  /// どうかの判定はこちらを使う。
  ///
  /// 取得に失敗したときは null（判定不能）を返す。呼び出し側はこの回のみ案内を
  /// 見送り、「案内済み」としては記録しないこと。true を返して既許可扱いにすると、
  /// 一度の取得失敗でそのユーザーが恒久的に案内対象から外れる。
  Future<bool?> hasPermission() async {
    try {
      return _isGranted(await _messaging.getNotificationSettings());
    } catch (_) {
      return null;
    }
  }

  /// バナー・音を伴う「目立つ配信」まで許可されているか。
  ///
  /// 暫定許可は通知センターに静かに積まれるだけなので false を返す。昇格を
  /// 案内すべきかの判定はこちらを使う。[hasPermission] で判定すると、暫定許可を
  /// 取った時点で案内対象から外れてしまい、誰も昇格しなくなる。
  Future<bool?> hasProminentPermission() async {
    try {
      final settings = await _messaging.getNotificationSettings();
      return settings.authorizationStatus == AuthorizationStatus.authorized;
    } catch (_) {
      return null;
    }
  }

  void dispose() {
    _tokenRefreshSubscription?.cancel();
    _tokenRefreshSubscription = null;
  }

  /// 許可ダイアログを出さずに送信先トークンだけ確保する（iOS のみ）。
  ///
  /// iOS の provisional authorization。通知は音もバナーも無しで通知センターに
  /// だけ届く。ダイアログが出ないので価値を体験する前に呼んでも邪魔にならず、
  /// 正式な許可（[enable]）へ進む前に離脱した人にも配信できる。
  /// 届いた通知の「目立つように配信」からユーザー自身が昇格させることもできる。
  ///
  /// 取れたときだけ true を返す。呼び出し側はアプリ内設定もオンにすること。
  /// オフのままだと次回起動の [sync] が登録を消してしまう。
  Future<bool> enableProvisionally() async {
    // Android の POST_NOTIFICATIONS に暫定許可は無く、呼ぶとダイアログが出る。
    if (defaultTargetPlatform != TargetPlatform.iOS) return false;
    try {
      // 本人が既に許可・拒否を決めているなら触らない。拒否を上書きはできないし、
      // 許可済みを暫定に落とすこともない。
      final current = await _messaging.getNotificationSettings();
      if (current.authorizationStatus != AuthorizationStatus.notDetermined) {
        return false;
      }

      final settings = await _messaging.requestPermission(provisional: true);
      if (!_isGranted(settings)) return false;
      return await _enableRegistration();
    } on TimeoutException {
      // 暫定許可自体は下りている。登録は onTokenRefresh か次回起動の [sync] で
      // 完了するので、アプリ内設定はオンにさせる。
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 通知を有効にする。必要なら許可ダイアログを出す。
  ///
  /// [PushEnableResult.denied] のときだけ呼び出し側はトグルをオフに戻す。
  /// [PushEnableResult.pending] は許可済みなのでオンのまま残すこと。
  ///
  /// 許可ダイアログ自体には上限を置かない。ユーザーが答えるまで返らないのは
  /// 正常で、打ち切ると答えた結果を取りこぼす。答えないまま離れた場合は
  /// 呼び出し側の計測（要求前のイベント）で切り分ける。
  Future<PushEnableResult> enable() async {
    try {
      final settings = await _messaging.requestPermission();
      if (!_isGranted(settings)) {
        await _disableRegistration(deleteDeviceToken: false);
        return PushEnableResult.denied;
      }

      final registered = await _enableRegistration();
      await _resetNotifyBackoff();
      if (!registered) return PushEnableResult.pending;
      // 暫定許可の人に要求すると昇格ダイアログになる。断られた場合は暫定の
      // ままなので、成功と同じには扱わない（通知は静かに届き続ける）。
      return settings.authorizationStatus == AuthorizationStatus.provisional
          ? PushEnableResult.quiet
          : PushEnableResult.enabled;
    } on TimeoutException {
      // 許可は得られている。登録だけが終わっていないので、オンのまま残して
      // onTokenRefresh か次回起動の sync() に任せる。ここでオフに戻すと
      // 二度と要求できない iOS では通知を諦めることになる。
      return PushEnableResult.pending;
    } catch (_) {
      // 許可取得に失敗したまま古い登録が残ると、UIはオフなのに通知だけ届く。
      try {
        await _disableRegistration(deleteDeviceToken: false);
      } catch (_) {
        _registrationEnabled = false;
      }
      return PushEnableResult.denied;
    }
  }

  /// 通知を無効にする。トークンを消すのでサーバー側の配信対象から外れる。
  Future<void> disable() async {
    try {
      await _disableRegistration(deleteDeviceToken: true);
    } catch (_) {
      // 失敗しても daily_reminder_enabled: false が書けていれば配信は止まる
    }
  }

  /// 配信希望時刻（時のみ）を保存する。
  Future<void> setPreferredHour(int hour) async {
    await _userDoc?.set(
      {
        'preferred_generation_hour': hour,
        'timezone': await _resolveTimezone(),
        // 算出できない日（DST春の飛び時刻）は書かず、既存値を残す。
        ...(() {
          final utcHour = notifyUtcHour(hour);
          return utcHour == null ? {} : {'notify_utc_hour': utcHour};
        }()),
      },
      SetOptions(merge: true),
    );
  }

  /// テーマ設定をサーバーへミラーする。
  ///
  /// テーマはローカルの SharedPreferences にしか無く配信バッチから見えないため、
  /// Premium ユーザーの毎日例文に設定を反映させる目的でこれだけ複製する。
  /// null（おまかせ）はフィールドごと消す。
  Future<void> setPreferredTopic(String? topic) async {
    try {
      await _userDoc?.set(
        {
          'preferred_topic': topic ?? FieldValue.delete(),
        },
        SetOptions(merge: true),
      );
    } catch (_) {
      // 反映は次回の設定変更・起動時に再試行される
    }
  }

  /// アプリ言語をサーバーへミラーする。
  ///
  /// 言語もローカルの SharedPreferences にしか無く配信バッチから見えないため、
  /// 毎日例文の通知本文を出し分ける目的でこれだけ複製する。
  /// クライアント起点の callable には引数で渡すので、ここは通知専用。
  Future<void> setAppLanguage(String lang) async {
    try {
      await _userDoc?.set(
        {'app_language': lang},
        SetOptions(merge: true),
      );
    } catch (_) {
      // 反映は次回の設定変更・起動時に再試行される
    }
  }

  /// 通知トグルON＝再開の意思表示として、配信バックオフの段階を0に戻す。
  ///
  /// 停止段階（notify_tier == 4）まで進んだユーザーは自分で例文を生成しない限り
  /// 配信が再開されないため、トグル操作を解除の入口にする。
  /// ルール上クライアントは0へのリセットのみ書ける。
  Future<void> _resetNotifyBackoff() async {
    try {
      await _userDoc?.set(
        {'notify_tier': 0, 'notify_tier_misses': 0},
        SetOptions(merge: true),
      );
    } catch (_) {
      // 失敗しても通知の有効化自体は成立している。段階は次の反応シグナルで戻る
    }
  }

  /// 送信先トークンを登録する。サーバーに書けたときだけ true を返す。
  ///
  /// 時間切れのときは [TimeoutException] を投げる。呼び出し側は許可の有無と
  /// 区別して扱うこと。
  Future<bool> _enableRegistration() async {
    _registrationEnabled = true;
    // iOS はデフォルトだとフォアグラウンド中の通知を表示しない。配信は1日1回で
    // 見逃されると意味がないため、アプリを開いていても出るようにする。
    await _messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );
    final token = await _messaging.getToken().timeout(_tokenFetchTimeout);
    if (token == null) return false;
    return _saveToken(token);
  }

  Future<void> _disableRegistration({required bool deleteDeviceToken}) async {
    _registrationEnabled = false;
    final doc = _userDoc;
    if (doc != null && await _isOwnRegistration(doc)) {
      await doc.update({
        'daily_reminder_enabled': false,
        'fcm_token': FieldValue.delete(),
      });
    }
    // 端末側のトークン破棄はサーバー登録の持ち主に関係なく行う。
    if (deleteDeviceToken) await _messaging.deleteToken();
  }

  /// サーバーに登録されているトークンが自端末のものか。
  ///
  /// fcm_token / daily_reminder_enabled は users/{uid} の単一フィールドで
  /// 端末間で共有される。通知オフの端末を起動しただけで別端末の配信が止まる
  /// のを避けるため、自分が登録した状態のときだけ書き換える。
  /// 判定できない場合は「他端末のもの」とみなして触らない。
  Future<bool> _isOwnRegistration(
    DocumentReference<Map<String, dynamic>> doc,
  ) async {
    try {
      final registered = (await doc.get()).data()?['fcm_token'] as String?;
      if (registered == null) return false;
      return registered == await _messaging.getToken();
    } catch (_) {
      return false;
    }
  }

  /// サーバーに書けたときだけ true を返す。
  ///
  /// サインイン前は書き先が無い。ここを黙って成功扱いにすると、アプリは通知オンの
  /// つもりなのにサーバーから見ると配信対象に入っていない状態が続く。
  Future<bool> _saveToken(String token) async {
    if (!_registrationEnabled) return false;
    final doc = _userDoc;
    if (doc == null) return false;
    // タイムゾーンはトークン更新のたびに書き直す。端末の移動・DST切り替えに追従させる。
    await doc.set(
      {
        'daily_reminder_enabled': true,
        'fcm_token': token,
        'timezone': await _resolveTimezone(),
      },
      SetOptions(merge: true),
    );
    return true;
  }

  Future<String> _resolveTimezone() async {
    try {
      return (await FlutterTimezone.getLocalTimezone()).identifier;
    } catch (_) {
      return kFallbackTimezone;
    }
  }
}
